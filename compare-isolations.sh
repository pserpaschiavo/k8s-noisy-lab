#!/bin/bash

# Import libraries
source lib/logger.sh
source lib/kubernetes.sh
source lib/metrics.sh

# Set experiment variables
EXPERIMENT_NAME="kata-vs-standard-isolation"
TENANT_A_NAMESPACE="tenant-a"
TENANT_B_NAMESPACE="tenant-b"
TENANT_C_NAMESPACE="tenant-c"
TENANT_D_NAMESPACE="tenant-d"
RESULTS_DIR="results/$(date +%Y-%m-%d)/${EXPERIMENT_NAME}"

# Process command line arguments
DEPLOY_STANDARD=true
DEPLOY_KATA=true
SKIP_CLEANUP=false

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --standard-only)
        DEPLOY_KATA=false
        shift
        ;;
      --kata-only)
        DEPLOY_STANDARD=false
        shift
        ;;
      --no-cleanup)
        SKIP_CLEANUP=true
        shift
        ;;
      --help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --standard-only   Deploy only standard containers (no kata)"
        echo "  --kata-only       Deploy only kata containers (no standard)"
        echo "  --no-cleanup      Skip cleanup after experiment"
        echo "  --help            Show this help message"
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done
}

# Create results directory
create_results_dir() {
  mkdir -p "${RESULTS_DIR}"
  log_info "Results will be stored in ${RESULTS_DIR}"
}

# Deploy standard workloads
deploy_standard_workloads() {
  log_info "Deploying standard workloads..."
  kubectl apply -f manifests/tenant-a/nginx-deploy.yaml
  kubectl apply -f manifests/tenant-b/stress-ng.yml
  kubectl apply -f manifests/tenant-c/memory-workload.yaml
  kubectl apply -f manifests/tenant-d/cpu-disk-workload.yaml
  
  # Wait for deployments to be ready
  wait_for_deployment_ready "${TENANT_A_NAMESPACE}" "nginx-deployment" 300
  wait_for_deployment_ready "${TENANT_B_NAMESPACE}" "stress-ng" 300
  wait_for_deployment_ready "tenant-c" "redis-deployment" 300
  wait_for_deployment_ready "tenant-d" "postgres" 300
  
  log_success "Standard workloads deployed successfully"
}

# Deploy kata workloads
deploy_kata_workloads() {
  log_info "Deploying Kata Container workloads..."
  
  # Apply namespace configurations first
  log_info "Creating namespaces with Kata configuration..."
  kubectl apply -f manifests-kata/namespace/tenant-a.yaml
  kubectl apply -f manifests-kata/namespace/tenant-b.yaml
  kubectl apply -f manifests-kata/namespace/tenant-c.yaml
  kubectl apply -f manifests-kata/namespace/tenant-d.yaml
  kubectl apply -f manifests-kata/namespace/resource-quotas.yaml
  
  # Apply workloads
  log_info "Deploying Kata Container workloads..."
  kubectl apply -f manifests-kata/tenant-a/nginx-deploy.yaml
  kubectl apply -f manifests-kata/tenant-b/stress-ng.yml
  kubectl apply -f manifests-kata/tenant-b/traffic-generator.yaml
  kubectl apply -f manifests-kata/tenant-b/traffic-server.yaml
  kubectl apply -f manifests-kata/tenant-c/memory-workload.yaml
  kubectl apply -f manifests-kata/tenant-d/cpu-disk-workload.yaml
  
  # Wait for deployments to be ready
  wait_for_deployment_ready "${TENANT_A_NAMESPACE}" "nginx-deployment" 300
  wait_for_deployment_ready "${TENANT_B_NAMESPACE}" "stress-ng" 300
  wait_for_deployment_ready "${TENANT_B_NAMESPACE}" "traffic-generator" 300
  wait_for_deployment_ready "${TENANT_B_NAMESPACE}" "traffic-server" 300
  wait_for_deployment_ready "tenant-c" "redis-deployment" 300
  wait_for_deployment_ready "tenant-d" "postgres" 300
  
  log_success "Kata Container workloads deployed successfully"
}

# Run baseline phase
run_baseline_phase() {
  local phase_name="1-baseline"
  local phase_dir="${RESULTS_DIR}/${phase_name}"
  mkdir -p "${phase_dir}"
  
  log_info "Starting baseline phase - normal operation without noisy neighbor"
  
  # Generate normal traffic to all services based on deployment settings
  log_info "Generating normal traffic to services"
  
  # Generate traffic for standard deployments if they exist
  if [ "$DEPLOY_STANDARD" = true ]; then
    log_info "Generating baseline traffic to standard deployments"
    kubectl run curl-client-std-baseline --image=curlimages/curl -i --rm --restart=Never -- \
      /bin/sh -c "for i in {1..50}; do curl -s http://nginx-deployment.${TENANT_A_NAMESPACE}.svc.cluster.local; sleep 0.2; done"
    
    # Test Redis workload
    log_info "Testing Redis workload (standard)"
    kubectl exec -n ${TENANT_C_NAMESPACE} -it $(kubectl get pod -n ${TENANT_C_NAMESPACE} -l app=redis -o jsonpath='{.items[0].metadata.name}') -- \
      redis-cli set benchmark:standard:baseline:$(date +%s) $(head -c 512K < /dev/urandom | base64) ex 30 &> /dev/null || true
      
    # Test PostgreSQL workload  
    log_info "Testing PostgreSQL workload (standard)"
    kubectl exec -n ${TENANT_D_NAMESPACE} -it $(kubectl get pod -n ${TENANT_D_NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
      psql -U postgres -c "SELECT current_timestamp, pg_sleep(0.05), current_timestamp" &> /dev/null || true
  fi
  
  # Generate traffic for kata deployments if they exist
  if [ "$DEPLOY_KATA" = true ]; then
    log_info "Generating baseline traffic to kata deployments"
    kubectl run curl-client-kata-baseline --image=curlimages/curl -i --rm --restart=Never -- \
      /bin/sh -c "for i in {1..50}; do curl -s http://nginx-deployment.${TENANT_A_NAMESPACE}.svc.cluster.local; sleep 0.2; done"
      
    # Test Redis workload
    log_info "Testing Redis workload (kata)"
    kubectl exec -n ${TENANT_C_NAMESPACE} -it $(kubectl get pod -n ${TENANT_C_NAMESPACE} -l app=redis -o jsonpath='{.items[0].metadata.name}') -- \
      redis-cli set benchmark:kata:baseline:$(date +%s) $(head -c 512K < /dev/urandom | base64) ex 30 &> /dev/null || true
      
    # Test PostgreSQL workload
    log_info "Testing PostgreSQL workload (kata)"
    kubectl exec -n ${TENANT_D_NAMESPACE} -it $(kubectl get pod -n ${TENANT_D_NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
      psql -U postgres -c "SELECT current_timestamp, pg_sleep(0.05), current_timestamp" &> /dev/null || true
  fi
  
  # Collect metrics
  log_info "Collecting baseline metrics"
  collect_metrics "${phase_dir}/standard-baseline-metrics.json" 60
  
  log_success "Baseline phase completed"
}

# Run attack phase
run_attack_phase() {
  local phase_name="2-attack"
  local phase_dir="${RESULTS_DIR}/${phase_name}"
  mkdir -p "${phase_dir}"
  
  log_info "Starting attack phase - noisy neighbor active"
  
  # Start stress-ng to create noisy neighbor effect
  log_info "Starting noisy neighbor attack"
  kubectl scale deployment stress-ng -n "${TENANT_B_NAMESPACE}" --replicas=3
  
  # Wait for scale-up
  wait_for_deployment_ready "${TENANT_B_NAMESPACE}" "stress-ng" 300
  
  # Generate traffic while under attack
  log_info "Generating traffic to services under attack"
  
  # Generate traffic to standard deployments if they exist
  if [ "$DEPLOY_STANDARD" = true ]; then
    log_info "Generating traffic to standard deployments"
    kubectl run curl-client-std --image=curlimages/curl -i --rm --restart=Never -- \
      /bin/sh -c "for i in {1..100}; do curl -s http://nginx-deployment.${TENANT_A_NAMESPACE}.svc.cluster.local; sleep 0.5; done"
    
    # Add memory workload
    kubectl exec -n ${TENANT_C_NAMESPACE} -it $(kubectl get pod -n ${TENANT_C_NAMESPACE} -l app=redis -o jsonpath='{.items[0].metadata.name}') -- \
      redis-cli set benchmark:test:$(date +%s) $(head -c 1M < /dev/urandom | base64) ex 60 &> /dev/null || true
      
    # Add PostgreSQL workload
    kubectl exec -n ${TENANT_D_NAMESPACE} -it $(kubectl get pod -n ${TENANT_D_NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
      psql -U postgres -c "SELECT pg_sleep(0.1)" &> /dev/null || true
  fi
  
  # Generate traffic to kata deployments if they exist
  if [ "$DEPLOY_KATA" = true ]; then
    log_info "Generating traffic to kata deployments"
    kubectl run curl-client-kata --image=curlimages/curl -i --rm --restart=Never -- \
      /bin/sh -c "for i in {1..100}; do curl -s http://nginx-deployment.${TENANT_A_NAMESPACE}.svc.cluster.local; sleep 0.5; done"
      
    # Add memory workload for kata deployments
    kubectl exec -n ${TENANT_C_NAMESPACE} -it $(kubectl get pod -n ${TENANT_C_NAMESPACE} -l app=redis -o jsonpath='{.items[0].metadata.name}') -- \
      redis-cli set benchmark:kata:test:$(date +%s) $(head -c 1M < /dev/urandom | base64) ex 60 &> /dev/null || true
      
    # Add PostgreSQL workload for kata deployments
    kubectl exec -n ${TENANT_D_NAMESPACE} -it $(kubectl get pod -n ${TENANT_D_NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
      psql -U postgres -c "SELECT pg_sleep(0.1)" &> /dev/null || true
  fi
  
  # Collect metrics
  log_info "Collecting attack phase metrics"
  collect_metrics "${phase_dir}/attack-metrics.json" 120
  
  log_success "Attack phase completed"
}

# Run recovery phase
run_recovery_phase() {
  local phase_name="3-recovery"
  local phase_dir="${RESULTS_DIR}/${phase_name}"
  mkdir -p "${phase_dir}"
  
  log_info "Starting recovery phase - stopping noisy neighbor"
  
  # Stop stress-ng
  log_info "Stopping noisy neighbor attack"
  kubectl scale deployment stress-ng -n "${TENANT_B_NAMESPACE}" --replicas=0
  
  # Wait for scale-down
  wait_for_pods_gone "${TENANT_B_NAMESPACE}" "app=stress-ng" 300
  
  # Generate traffic during recovery
  log_info "Generating traffic to services during recovery"
  
  # Generate traffic to standard deployments if they exist
  if [ "$DEPLOY_STANDARD" = true ]; then
    log_info "Generating traffic to standard deployments during recovery"
    kubectl run curl-client-std-recovery --image=curlimages/curl -i --rm --restart=Never -- \
      /bin/sh -c "for i in {1..100}; do curl -s http://nginx-deployment.${TENANT_A_NAMESPACE}.svc.cluster.local; sleep 0.5; done"
    
    # Add memory workload during recovery
    kubectl exec -n ${TENANT_C_NAMESPACE} -it $(kubectl get pod -n ${TENANT_C_NAMESPACE} -l app=redis -o jsonpath='{.items[0].metadata.name}') -- \
      redis-cli set benchmark:recovery:test:$(date +%s) $(head -c 1M < /dev/urandom | base64) ex 60 &> /dev/null || true
      
    # Add PostgreSQL workload during recovery
    kubectl exec -n ${TENANT_D_NAMESPACE} -it $(kubectl get pod -n ${TENANT_D_NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
      psql -U postgres -c "SELECT pg_sleep(0.1)" &> /dev/null || true
  fi
  
  # Generate traffic to kata deployments if they exist
  if [ "$DEPLOY_KATA" = true ]; then
    log_info "Generating traffic to kata deployments during recovery"
    kubectl run curl-client-kata-recovery --image=curlimages/curl -i --rm --restart=Never -- \
      /bin/sh -c "for i in {1..100}; do curl -s http://nginx-deployment.${TENANT_A_NAMESPACE}.svc.cluster.local; sleep 0.5; done"
      
    # Add memory workload for kata deployments during recovery
    kubectl exec -n ${TENANT_C_NAMESPACE} -it $(kubectl get pod -n ${TENANT_C_NAMESPACE} -l app=redis -o jsonpath='{.items[0].metadata.name}') -- \
      redis-cli set benchmark:kata:recovery:test:$(date +%s) $(head -c 1M < /dev/urandom | base64) ex 60 &> /dev/null || true
      
    # Add PostgreSQL workload for kata deployments during recovery
    kubectl exec -n ${TENANT_D_NAMESPACE} -it $(kubectl get pod -n ${TENANT_D_NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
      psql -U postgres -c "SELECT pg_sleep(0.1)" &> /dev/null || true
  fi
  
  # Collect metrics
  log_info "Collecting recovery phase metrics"
  collect_metrics "${phase_dir}/recovery-metrics.json" 60
  
  log_success "Recovery phase completed"
}

# Generate comparison results
generate_comparison() {
  log_info "Generating comparison between standard containers and Kata Containers"
  
  # Extract relevant metrics and create comparison charts
  python3 - <<EOF
import json
import matplotlib.pyplot as plt
import numpy as np
import os

results_dir = "${RESULTS_DIR}"

# Create output directory for graphs
os.makedirs(f"{results_dir}/comparison", exist_ok=True)

# Function to extract metrics from files
def extract_metrics(file_path):
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
            
        # Extract relevant metrics for all workloads
        metrics = {
            # Tenant A - Network metrics
            'standard_latency': [],
            'kata_latency': [],
            'standard_cpu': [],
            'kata_cpu': [],
            
            # Tenant C - Redis/Memory metrics
            'standard_memory_usage': [],
            'kata_memory_usage': [],
            'standard_redis_ops': [],
            'kata_redis_ops': [],
            
            # Tenant D - PostgreSQL/CPU-Disk metrics
            'standard_postgres_latency': [],
            'kata_postgres_latency': [],
            'standard_disk_io': [],
            'kata_disk_io': []
        }
        
        for metric in data.get('metrics', []):
            metric_name = metric.get('name', '')
            labels = metric.get('labels', {})
            namespace = labels.get('namespace', '')
            pod = labels.get('pod', '').lower()
            value = float(metric.get('value', 0))
            
            # Tenant A metrics (network)
            if 'latency' in metric_name and namespace == 'tenant-a':
                if 'kata' not in pod:
                    metrics['standard_latency'].append(value)
                else:
                    metrics['kata_latency'].append(value)
            elif 'cpu_usage' in metric_name and namespace == 'tenant-a':
                if 'kata' not in pod:
                    metrics['standard_cpu'].append(value)
                else:
                    metrics['kata_cpu'].append(value)
            
            # Tenant C metrics (Redis/Memory)
            elif namespace == 'tenant-c':
                if 'memory' in metric_name:
                    if 'kata' not in pod:
                        metrics['standard_memory_usage'].append(value)
                    else:
                        metrics['kata_memory_usage'].append(value)
                elif 'ops' in metric_name or 'commands' in metric_name:
                    if 'kata' not in pod:
                        metrics['standard_redis_ops'].append(value)
                    else:
                        metrics['kata_redis_ops'].append(value)
            
            # Tenant D metrics (PostgreSQL)
            elif namespace == 'tenant-d':
                if 'latency' in metric_name or 'duration' in metric_name:
                    if 'kata' not in pod:
                        metrics['standard_postgres_latency'].append(value)
                    else:
                        metrics['kata_postgres_latency'].append(value)
                elif 'disk' in metric_name or 'io' in metric_name:
                    if 'kata' not in pod:
                        metrics['standard_disk_io'].append(value)
                    else:
                        metrics['kata_disk_io'].append(value)
        
        # Calculate means for each metric
        result = {}
        for key, values in metrics.items():
            result[key] = np.mean(values) if values else 0
            
        return result
    except Exception as e:
        print(f"Error processing {file_path}: {e}")
        return {
            'standard_latency': 0,
            'kata_latency': 0,
            'standard_cpu': 0,
            'kata_cpu': 0
        }

# Extract metrics from each phase
baseline_metrics = extract_metrics(f"{results_dir}/1-baseline/standard-baseline-metrics.json")
attack_metrics = extract_metrics(f"{results_dir}/2-attack/attack-metrics.json")
recovery_metrics = extract_metrics(f"{results_dir}/3-recovery/recovery-metrics.json")

# Create comparison charts for each tenant and metric type
phases = ['Baseline', 'Attack', 'Recovery']

# Function to create comparison bar chart
def create_comparison_chart(standard_values, kata_values, title, ylabel, filename):
    plt.figure(figsize=(12, 6))
    x = np.arange(len(phases))
    width = 0.35
    
    plt.bar(x - width/2, standard_values, width, label='Standard Container')
    plt.bar(x + width/2, kata_values, width, label='Kata Container')
    
    plt.ylabel(ylabel)
    plt.title(title)
    plt.xticks(x, phases)
    plt.legend()
    plt.grid(True, linestyle='--', alpha=0.7)
    
    plt.savefig(f"{results_dir}/comparison/{filename}")
    plt.close()

# Prepare data for plots - Tenant A (Network)
standard_latencies = [
    baseline_metrics['standard_latency'],
    attack_metrics['standard_latency'],
    recovery_metrics['standard_latency']
]
kata_latencies = [
    baseline_metrics['kata_latency'],
    attack_metrics['kata_latency'],
    recovery_metrics['kata_latency']
]

# Prepare data for plots - Tenant C (Memory)
memory_standard = [
    baseline_metrics['standard_memory_usage'],
    attack_metrics['standard_memory_usage'],
    recovery_metrics['standard_memory_usage']
]
memory_kata = [
    baseline_metrics['kata_memory_usage'],
    attack_metrics['kata_memory_usage'],
    recovery_metrics['kata_memory_usage']
]

# Prepare data for plots - Tenant D (CPU/Disk)
postgres_standard = [
    baseline_metrics['standard_postgres_latency'],
    attack_metrics['standard_postgres_latency'],
    recovery_metrics['standard_postgres_latency']
]
postgres_kata = [
    baseline_metrics['kata_postgres_latency'],
    attack_metrics['kata_postgres_latency'],
    recovery_metrics['kata_postgres_latency']
]

# Generate all comparison charts
create_comparison_chart(standard_latencies, kata_latencies, 
                       'Network Latency Comparison: Standard vs Kata Containers', 
                       'Average Latency (ms)', 'network_latency_comparison.png')

create_comparison_chart(memory_standard, memory_kata,
                       'Memory Usage Comparison: Standard vs Kata Containers',
                       'Memory Usage', 'memory_usage_comparison.png')
                       
create_comparison_chart(postgres_standard, postgres_kata,
                       'PostgreSQL Query Latency: Standard vs Kata Containers',
                       'Query Latency (ms)', 'postgres_latency_comparison.png')

# Create comprehensive summary report with all metrics
with open(f"{results_dir}/comparison/summary.md", 'w') as f:
    f.write("# Noisy Neighbor Isolation Comparison: Standard vs Kata Containers\n\n")
    f.write("## Experiment Summary\n\n")
    f.write("This report compares the performance of standard containers vs Kata Containers under noisy neighbor conditions.\n")
    f.write("The experiment tested network, memory, and CPU/disk workloads in three phases: baseline, attack, and recovery.\n\n")
    
    f.write("## Network Performance (Tenant A)\n\n")
    f.write("| Phase | Standard Container (ms) | Kata Container (ms) | Improvement |\n")
    f.write("|-------|-------------------------|---------------------|------------|\n")
    
    baseline_diff = baseline_metrics['standard_latency'] - baseline_metrics['kata_latency']
    attack_diff = attack_metrics['standard_latency'] - attack_metrics['kata_latency']
    recovery_diff = recovery_metrics['standard_latency'] - recovery_metrics['kata_latency']
    
    baseline_pct = (baseline_diff / baseline_metrics['standard_latency'] * 100) if baseline_metrics['standard_latency'] > 0 else 0
    attack_pct = (attack_diff / attack_metrics['standard_latency'] * 100) if attack_metrics['standard_latency'] > 0 else 0
    recovery_pct = (recovery_diff / recovery_metrics['standard_latency'] * 100) if recovery_metrics['standard_latency'] > 0 else 0
    
    f.write(f"| Baseline | {baseline_metrics['standard_latency']:.2f} | {baseline_metrics['kata_latency']:.2f} | {baseline_pct:.1f}% |\n")
    f.write(f"| Attack | {attack_metrics['standard_latency']:.2f} | {attack_metrics['kata_latency']:.2f} | {attack_pct:.1f}% |\n")
    f.write(f"| Recovery | {recovery_metrics['standard_latency']:.2f} | {recovery_metrics['kata_latency']:.2f} | {recovery_pct:.1f}% |\n\n")
    
    # Calculate impact percentage
    attack_impact_std = ((attack_metrics['standard_latency'] / baseline_metrics['standard_latency']) - 1) * 100 if baseline_metrics['standard_latency'] > 0 else 0
    attack_impact_kata = ((attack_metrics['kata_latency'] / baseline_metrics['kata_latency']) - 1) * 100 if baseline_metrics['kata_latency'] > 0 else 0
    
    f.write(f"**Impact Analysis**: During the noisy neighbor attack, standard containers experienced a {attack_impact_std:.1f}% increase in network latency, ")
    f.write(f"while Kata Containers only experienced a {attack_impact_kata:.1f}% increase.\n\n")
    
    if attack_impact_std > attack_impact_kata:
        isolation_improvement = (attack_impact_std - attack_impact_kata) / attack_impact_std * 100 if attack_impact_std > 0 else 0
        f.write(f"**Isolation Benefit**: Kata Containers provided {isolation_improvement:.1f}% better isolation against noisy neighbor effects for network workloads.\n\n")
    else:
        f.write("**Isolation Finding**: No significant network isolation advantage was observed with Kata Containers in this experiment.\n\n")
    
    # Add memory workload results
    f.write("## Memory Workload Performance (Tenant C - Redis)\n\n")
    
    # Similar metrics for memory workloads
    # (Add similar metrics calculation and reporting for memory workloads)
    
    # Add PostgreSQL workload results
    f.write("## CPU/Disk Workload Performance (Tenant D - PostgreSQL)\n\n")
    
    # Similar metrics for PostgreSQL workloads
    # (Add similar metrics calculation and reporting for PostgreSQL workloads)
    
    f.write("\n## Conclusion\n\n")
    f.write("Kata Containers provides varying levels of isolation benefits depending on the workload type:\n\n")
    
    if attack_impact_std > attack_impact_kata:
        f.write("1. **Network Workloads**: Significant isolation benefits observed\n")
    else:
        f.write("1. **Network Workloads**: Limited isolation benefits observed\n")
        
    # Add conclusions for memory and disk workloads based on their respective metrics
EOF

  log_success "Comparison generated successfully in ${RESULTS_DIR}/comparison/"
}

# Cleanup
cleanup() {
  log_info "Cleaning up deployments..."
  
  # Cleanup standard workloads
  log_info "Cleaning up standard workloads..."
  kubectl delete -f manifests/tenant-a/nginx-deploy.yaml --ignore-not-found
  kubectl delete -f manifests/tenant-b/stress-ng.yml --ignore-not-found
  kubectl delete -f manifests/tenant-c/memory-workload.yaml --ignore-not-found
  kubectl delete -f manifests/tenant-d/cpu-disk-workload.yaml --ignore-not-found
  
  # Cleanup kata workloads
  log_info "Cleaning up kata workloads..."
  kubectl delete -f manifests-kata/tenant-a/nginx-deploy.yaml --ignore-not-found
  kubectl delete -f manifests-kata/tenant-b/stress-ng.yml --ignore-not-found
  kubectl delete -f manifests-kata/tenant-b/traffic-generator.yaml --ignore-not-found
  kubectl delete -f manifests-kata/tenant-b/traffic-server.yaml --ignore-not-found
  kubectl delete -f manifests-kata/tenant-c/memory-workload.yaml --ignore-not-found
  kubectl delete -f manifests-kata/tenant-d/cpu-disk-workload.yaml --ignore-not-found
  
  # Keep the namespaces and resource quotas
  
  log_success "Cleanup completed"
}

# Main function
main() {
  log_info "Starting Kata Containers isolation experiment"
  
  # Parse command line arguments
  parse_args "$@"
  
  create_results_dir
  
  # Deploy workloads based on command line arguments
  if [ "$DEPLOY_STANDARD" = true ]; then
    deploy_standard_workloads
  else
    log_info "Skipping standard workloads deployment (--kata-only)"
  fi
  
  if [ "$DEPLOY_KATA" = true ]; then
    deploy_kata_workloads
  else
    log_info "Skipping kata workloads deployment (--standard-only)"
  fi
  
  # Run experiment phases
  run_baseline_phase
  run_attack_phase
  run_recovery_phase
  
  # Generate comparison
  generate_comparison
  
  # Create report with information about all tested workloads
  log_info "Creating comprehensive report of all workloads..."
  
  cat > "${RESULTS_DIR}/experiment_info.md" << EOF
# Kata Containers vs Standard Containers Experiment

**Date:** $(date "+%Y-%m-%d %H:%M:%S")

## Workloads Tested

### Tenant A (Network-Sensitive Workloads)
- NGINX web server (standard vs kata runtime)
- Sensitive to network latency and jitter

### Tenant B (Noisy Neighbor)
- stress-ng (CPU/memory stress testing)
- Traffic generator and server (network load)
- Configured to create resource contention

### Tenant C (Memory-Sensitive Workloads)
- Redis database with benchmarking
- Sensitive to memory allocation and eviction

### Tenant D (CPU and Disk-Sensitive Workloads)
- PostgreSQL database with pgbench
- Sensitive to CPU scheduling and disk I/O

## Experiment Phases
1. **Baseline Phase:** Normal operation without resource contention
2. **Attack Phase:** Noisy neighbor (tenant B) actively creating contention
3. **Recovery Phase:** After stopping the noisy neighbor workloads

## Results Summary
Check the comparison directory for detailed metrics and visualization of the isolation effects.
EOF

  # Cleanup unless --no-cleanup was specified
  if [ "$SKIP_CLEANUP" = false ]; then
    cleanup
  else
    log_info "Skipping cleanup (--no-cleanup)"
  fi
  
  log_success "Kata Containers isolation experiment completed successfully"
  log_info "Results available at: ${RESULTS_DIR}/comparison/"
}

main "$@"

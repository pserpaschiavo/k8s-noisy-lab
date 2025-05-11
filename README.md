# Kubernetes Noisy Neighbours Lab

## Introduction
The Kubernetes Noisy Neighbours Lab is a controlled experimental environment designed to study the "noisy neighbour" problem in multi-tenant Kubernetes clusters. This phenomenon occurs when one tenant's resource usage negatively impacts the performance of other tenants sharing the same infrastructure. The lab simulates real-world scenarios to analyze resource contention and its effects on latency-sensitive and resource-intensive workloads.

This repository is part of the research for submission to SBSEG2025 and aims to provide insights into resource isolation, performance degradation, and mitigation strategies in Kubernetes environments.

---

## Goals
The primary goals of this experiment are:
1. **Simulate the noisy neighbour effect**: Create resource contention scenarios using workloads that stress CPU, memory, and network resources.
2. **Analyze tenant performance**: Measure the impact of resource contention on latency-sensitive and resource-intensive workloads.
3. **Collect and visualize metrics**: Use Prometheus and Grafana to collect and analyze metrics such as CPU usage, memory usage, network latency, jitter, and disk I/O.
4. **Evaluate mitigation strategies**: Provide insights into resource isolation mechanisms and their effectiveness in mitigating the noisy neighbour problem.

---

## System Requirements

### Recommended Configuration (Ideal)
- **CPU**: 8 vCPUs (cores)
- **Memory**: 16 GB RAM
- **Disk Space**: 60 GB SSD (preferably)
- **Operating System**: Ubuntu 22.04 LTS or similar Linux distribution

This configuration provides an optimal environment to clearly demonstrate the "noisy neighbor" effect between tenants, as configured in the manifests.

### Minimum Configuration (With Limitations)
- **CPU**: 4 vCPUs
- **Memory**: 8 GB RAM
- **Disk Space**: 40 GB SSD/HDD
- **Operating System**: Ubuntu 22.04 LTS or similar Linux distribution

While the experiment will run with this minimum configuration, the "noisy neighbor" effect may be less pronounced and there might be some performance limitations.

### Cloud Provider Equivalents

If you're using a cloud provider, these would be suitable instances:

#### For Recommended Configuration:
- **AWS**: t3.2xlarge (8 vCPU, 32 GB RAM) or c5.2xlarge (8 vCPU, 16 GB RAM)
- **GCP**: n2-standard-8 (8 vCPU, 32 GB RAM) or c2-standard-8 (8 vCPU, 16 GB RAM)
- **Azure**: Standard_D8s_v3 (8 vCPU, 32 GB RAM)

#### For Minimum Configuration:
- **AWS**: t3.xlarge (4 vCPU, 16 GB RAM)
- **GCP**: n2-standard-4 (4 vCPU, 16 GB RAM)
- **Azure**: Standard_D4s_v3 (4 vCPU, 16 GB RAM)

### Kubernetes Version Compatibility

O laboratório usa por padrão a versão **v1.28.10** do Kubernetes, escolhida por:
- Compatibilidade com versões recentes do kubectl (até v1.33.x)
- Estabilidade para os recursos utilizados no experimento
- Suporte para todas as funcionalidades necessárias para demonstrar o efeito "noisy neighbor"

Você pode especificar uma versão diferente do Kubernetes usando o parâmetro `--k8s-version`:
```bash
./setup-minikube.sh --k8s-version v1.29.2
```

**Nota sobre compatibilidade**: O script `setup-minikube.sh` faz verificações automáticas de compatibilidade entre sua versão do kubectl e a versão do Kubernetes selecionada, alertando sobre possíveis problemas.

---

## Tools and Resources

### Kubernetes Cluster
- **Minikube**: A local Kubernetes cluster is set up using Minikube with configurable resources:
  - Recommended: 8 CPUs, 16GB RAM, and 40GB disk space
  - Minimum: 4 CPUs, 8GB RAM, and 30GB disk space
  - Static CPU manager policy and eviction thresholds
  - Addons: `metrics-server`, `dashboard`, `ingress`, `storage-provisioner`

### Monitoring Stack
- **Prometheus**: Collects metrics from workloads and the Kubernetes cluster.
- **Grafana**: Visualizes metrics through custom dashboards.
- **ServiceMonitors**: Configured for each tenant to scrape metrics.
- **PrometheusRules**: Detects noisy neighbour effects and triggers alerts.

### NGINX Ingress Controller
- **Purpose**: Manages HTTP traffic for tenant workloads.
- **Installation**: Installed using the `install-nginx-controller.sh` script.
- **Metrics**: Exposes metrics for response time and jitter, which are collected by Prometheus.
- **Access**: Configured to route traffic to tenant workloads.

### Tenant Workloads

#### Tenant A (Network-Sensitive)
- **Components**: NGINX web server and iperf server.
- **Characteristics**: Sensitive to network latency and jitter.
- **Metrics Focus**: HTTP response time, network throughput, connection handling.

#### Tenant B (Noisy Neighbor)
- **Components**: stress-ng (CPU/memory stress), traffic generator, and traffic server.
- **Characteristics**: Deliberately consumes excessive resources to create contention.
- **Behavior**: Generates CPU, memory, I/O, and network load during attack phases.

#### Tenant C (Memory-Sensitive)
- **Components**: Redis database with benchmarking.
- **Characteristics**: Sensitive to memory availability and allocation.
- **Metrics Focus**: Memory usage, eviction rate, query performance.

#### Tenant D (CPU and Disk-Sensitive)
- **Components**: PostgreSQL database with pgbench workloads.
- **Characteristics**: Sensitive to CPU throttling and disk I/O performance.
- **Metrics Focus**: Query execution time, transaction throughput, I/O latency.

---

## Repository Structure
```
.
├── check-cluster.sh                # Verifies cluster readiness
├── install-nginx-controller.sh     # Installs NGINX Ingress Controller
├── install-prom-operator.sh        # Installs Prometheus and Grafana
├── run-experiment.sh               # Main script to orchestrate the experiment
├── setup-minikube.sh               # Sets up the Minikube cluster
├── lib/                            # Helper libraries for the experiment
│   ├── experiment.sh               # Experiment orchestration functions
│   ├── kubernetes.sh               # Kubernetes interaction functions
│   ├── logger.sh                   # Logging utilities
│   ├── metrics.sh                  # Metrics collection functions
│   └── tenant_metrics.sh           # Tenant-specific metrics definitions
├── manifests/                      # Kubernetes manifests for workloads and namespaces
│   ├── ingress-controller/         # Ingress controller configuration
│   ├── namespace/                  # Namespace and resource quota definitions
│   │   ├── limited-resource-quotas.yaml  # Resource quotas for limited resources mode
│   │   └── resource-quotas.yaml    # Standard resource quotas
│   ├── tenant-a/                   # Network-sensitive workloads
│   ├── tenant-b/                   # Noisy neighbor workloads
│   ├── tenant-c/                   # Memory-sensitive workloads
│   └── tenant-d/                   # CPU and disk-sensitive workloads
├── observability/                  # Prometheus and Grafana configurations
│   ├── grafana-dashboards/         # Grafana dashboards
│   ├── prometheus-rules/           # Prometheus alerting rules
│   ├── servicemonitors/            # ServiceMonitors for tenants
│   └── tenant-metrics.yaml         # Tenant-specific metric definitions
└── results/                        # Directory for experiment results
```

---

## How to Run the Experiment

Follow these steps to set up and run the noisy neighbor experiment:

### 1. Set Up Minikube

Run the setup script to create the Kubernetes cluster:

#### For recommended resources (8 CPUs, 16GB RAM):
```bash
./setup-minikube.sh
```

#### For limited resources (4 CPUs, 8GB RAM):
```bash
./setup-minikube.sh --limited
```

You can also specify custom resource values:
```bash
./setup-minikube.sh --cpus 6 --memory 12g --disk 50g
```

The script:
- Creates a Minikube cluster with the specified resources.
- Enables necessary addons (metrics-server, dashboard, ingress).
- Creates the tenant namespaces with appropriate labels.
- Verifies the cluster status.

### 2. Install Monitoring Stack

Install Prometheus and Grafana:
```bash
./install-prom-operator.sh
```

This installs:
- Prometheus Operator.
- Prometheus and Grafana instances.
- ServiceMonitors for tenant workloads.
- Custom dashboards for visualizing the noisy neighbor effect.

### 3. Install NGINX Ingress Controller

Deploy the NGINX Ingress Controller:
```bash
./install-nginx-controller.sh
```

This:
- Installs the NGINX Ingress Controller.
- Configures it to expose metrics for Prometheus.
- Sets up routes to tenant services.

### 4. Run the Experiment

Execute the main experiment script:

#### For recommended resources:
```bash
./run-experiment.sh
```

#### For limited resources:
```bash
./run-experiment.sh --limited-resources
```

#### Advanced options:
```bash
./run-experiment.sh -n custom-experiment -r 2 -b 300 -a 600 -c 300 -i 5
```
Where:
- `-n, --name`: Custom experiment name.
- `-r, --rounds`: Number of experiment rounds (default: 3).
- `-b, --baseline`: Baseline duration in seconds (default: 240).
- `-a, --attack`: Attack phase duration in seconds (default: 360).
- `-c, --recovery`: Recovery phase duration in seconds (default: 240).
- `-i, --interval`: Metrics collection interval in seconds (default: 5).

The experiment proceeds through three phases for each round:
1. **Baseline**: All tenants running normally.
2. **Attack**: Tenant B activates its noisy workloads.
3. **Recovery**: Tenant B returns to normal operation.

### 5. View Results

#### Access Grafana dashboards:
```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
```
Open your browser at [http://localhost:3000](http://localhost:3000) (username: `admin`, password: `admin`).

#### Access Prometheus directly:
```bash
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090
```
Open your browser at [http://localhost:9090](http://localhost:9090).

---

## Metrics Collected

The experiment collects various metrics to analyze the noisy neighbor effect:

### Tenant A (Network-Sensitive)
- Network latency and jitter.
- HTTP response times.
- Connection throughput and errors.
- TCP retransmission rates.

### Tenant B (Noisy Neighbor)
- CPU and memory consumption.
- Network bandwidth utilization.
- I/O operations and throughput.

### Tenant C (Memory-Sensitive)
- Memory usage and allocation.
- Redis operation latency.
- Cache hit/miss rates.
- Memory pressure indicators.

### Tenant D (CPU and Disk-Sensitive)
- Query execution times.
- Transaction throughput.
- I/O wait times.
- CPU throttling events.

### System-wide Metrics
- Node CPU, memory, and I/O utilization.
- Network saturation.
- Kubernetes scheduler decisions.
- Resource contention indicators.

Metrics are collected at configurable intervals (default: 5 seconds) and stored in CSV format for analysis.

---

## Results

Experiment results are saved in the `results/` directory with the following structure:
```
results/
└── [experiment-name]/
    ├── [yyyy-mm-dd_HH-MM-SS]/
    │   ├── info.txt                  # Experiment configuration summary
    │   ├── logs/                     # Detailed experiment logs
    │   └── metrics/                  # Raw and processed metrics
    │       ├── round-1/              # First experiment round
    │       │   ├── baseline/         # Baseline phase metrics
    │       │   ├── attack/           # Attack phase metrics
    │       │   └── recovery/         # Recovery phase metrics
    │       ├── round-2/              # Second experiment round
    │       └── round-3/              # Third experiment round
    └── ...                           # Additional experiment runs
```

---

## Debugging

For troubleshooting specific tenants:
```bash
./debug-tenant.sh [tenant-name]
```

To check the cluster's overall status:
```bash
./check-cluster.sh
```

---

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any suggestions or improvements.

---

## License
This project is licensed under the MIT License.

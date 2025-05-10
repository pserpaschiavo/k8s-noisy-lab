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

## Tools and Resources

### Kubernetes Cluster
- **Minikube**: A local Kubernetes cluster is set up using Minikube with the following configurations:
  - 4 CPUs, 6GB RAM, and 20GB disk space.
  - Static CPU manager policy and eviction thresholds.
  - Addons: `metrics-server`, `dashboard`, `ingress`.

### Monitoring Stack
- **Prometheus**: Collects metrics from workloads and the Kubernetes cluster.
- **Grafana**: Visualizes metrics through custom dashboards.
- **ServiceMonitors**: Configured for each tenant to scrape metrics.
- **PrometheusRules**: Detects noisy neighbour effects and triggers alerts.

### NGINX Ingress Controller
- **Purpose**: Manages HTTP traffic for tenant workloads.
- **Installation**: Installed using the `install-nginx-controller.sh` script.
- **Metrics**: Exposes metrics for response time and jitter, which are collected by Prometheus.
- **Access**: Configured to route traffic to tenant-a's NGINX service.

### Workloads
- **Tenant-a**:
  - Runs an NGINX web server with a benchmarking job (`wrk`) to simulate HTTP traffic.
  - Sensitive to network metrics, latency, and jitter.
- **Tenant-b**:
  - Runs a multi-resource stress workload using `stress-ng` (CPU and memory) and `iperf` (network).
  - Acts as the noisy neighbour, creating contention for shared resources.
- **Tenant-c**:
  - Runs a Redis database with a benchmarking job (`redis-benchmark`) to simulate memory-intensive operations.
  - Sensitive to CPU and memory metrics.

---

## Repository Structure
```
.
├── check-cluster.sh                # Verifies cluster readiness
├── install-nginx-controller.sh     # Installs NGINX Ingress Controller
├── install-prom-operator.sh        # Installs Prometheus and Grafana
├── run-experiment.sh               # Main script to orchestrate the experiment
├── setup-minikube.sh               # Sets up the Minikube cluster
├── manifests/                      # Kubernetes manifests for workloads and namespaces
│   ├── ingress-controller/         # Ingress controller configuration
│   ├── namespace/                  # Namespace and resource quota definitions
│   ├── tenant-a/                   # Workloads for tenant-a
│   ├── tenant-b/                   # Workloads for tenant-b
│   └── tenant-c/                   # Workloads for tenant-c
├── metrics/                        # Python modules for advanced metric collection
│   ├── exporters/                  # Exporters for CSV and JSON formats
│   ├── processors/                 # Data processing modules
├── observability/                  # Prometheus and Grafana configurations
│   ├── grafana-dashboards/         # Grafana dashboards
│   ├── prometheus-rules/           # Prometheus alerting rules
│   └── servicemonitors/            # ServiceMonitors for tenants
└── results/                        # Directory for experiment results
```

---

## How to Run the Experiment

Follow these steps to set up and run the noisy neighbor experiment:

1. **Set Up Minikube**:
   Run the following script to set up the Minikube cluster:
   ```bash
   ./setup-minikube.sh
   ```
   - This script configures Minikube with 4 CPUs, 6GB RAM, and 20GB disk space.
   - It creates the necessary namespaces: `tenant-a`, `tenant-b`, `tenant-c`, and `monitoring`.

2. **Install Prometheus and Grafana**:
   Install the monitoring stack using:
   ```bash
   ./install-prom-operator.sh
   ```
   - This script installs Prometheus and Grafana, applies ServiceMonitors, and sets up dashboards and PrometheusRules.

3. **Install NGINX Ingress Controller**:
   Deploy the NGINX Ingress Controller using:
   ```bash
   ./install-nginx-controller.sh
   ```
   - This script installs the NGINX Ingress Controller and enables metrics for response time and jitter.

4. **Port-Forward Prometheus and Grafana**:
   - For Prometheus:
     ```bash
     kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090
     ```
     Open your browser at [http://localhost:9090](http://localhost:9090).
   - For Grafana:
     ```bash
     kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
     ```
     Open your browser at [http://localhost:3000](http://localhost:3000) (username: `admin`, password: `admin`).

5. **Run the Experiment**:
   Execute the main experiment script:
   ```bash
   ./run-experiment.sh
   ```
   - This script orchestrates the experiment, collects metrics, and saves results in the `results/` directory.

---

## Metrics Collected
The following metrics are collected during the experiment:
- **CPU Usage**: `container_cpu_usage_seconds_total`
- **Memory Usage**: `container_memory_working_set_bytes`
- **Network Traffic**: `container_network_transmit_bytes_total`, `container_network_receive_bytes_total`
- **Disk I/O**: `node_disk_io_time_seconds_total`
- **Response Time and Jitter**: `nginx_ingress_controller_request_duration_seconds_bucket`
- **Redis Metrics**: `redis_memory_used_bytes`, `redis_commands_processed_total`

---

## Results
Experiment results are saved in the `results/` directory, organized by date and time. Metrics are exported in CSV format for further analysis.

---

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any suggestions or improvements.

---

## License
This project is licensed under the MIT License.

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

The lab uses **v1.32.0** of Kubernetes by default, chosen for:
- Compatibility with recent kubectl versions (up to v1.33.x)
- Stability for the resources used in the experiment
- Support for all the necessary features to demonstrate the "noisy neighbor" effect

You can specify a different Kubernetes version using the `--k8s-version` parameter:
```bash
./setup-minikube.sh --k8s-version v1.29.2
```

**Compatibility note**: The `setup-minikube.sh` script automatically checks compatibility between your kubectl version and the selected Kubernetes version, alerting you to potential issues.

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

### Data Analysis (Pipeline)
- **Automatic Processing**: Python pipeline for recursive analysis of experiment metrics.
- **Statistical Analysis**: Calculations of descriptive statistics, correlations, and stationarity tests.
- **Visualizations**: Automatic generation of time series graphs, distributions, and correlations.
- **Phase Comparison**: Comparative analysis between baseline, attack, and recovery phases.
- **Categorization**: Organization of metrics by categories (tenants, components, etc.).
- **Advanced Time Series Analysis**: 
  - **Cross-Correlation**: Cross-correlation analysis to identify relationships between time series with different lags.
  - **Lag Analysis**: Identification of the optimal time delay between events in different metrics.
  - **Granger Causality**: Statistical tests to determine causal relationships between metric series.
  - **Entropy Analysis**: Calculation of approximate entropy (ApEn) and sample entropy (SampEn) to quantify complexity and regularity of time series.

---

## Repository Structure
```
.
├── check-cluster.sh                          # Verifies cluster readiness
├── install-nginx-controller.sh               # Installs NGINX Ingress Controller
├── install-prom-operator.sh                  # Installs Prometheus and Grafana
├── run-experiment.sh                         # Main script to orchestrate the experiment
├── setup-minikube.sh                         # Sets up the Minikube cluster
├── analysis_pipeline/                        # Data analysis pipeline
│   ├── correlation_analysis.py               # Correlation analysis between metrics
│   ├── data_loader.py                        # Recursive metric loading
│   ├── main.py                               # Main pipeline entry point
│   ├── stats_summary.py                      # Statistical analysis of metrics
│   ├── time_series_analysis.py               # Advanced time series analysis
│   ├── visualizations.py                     # Visualization generation
│   └── README.md                             # Documentação específica do pipeline
├── lib/                                      # Helper libraries for the experiment
│   ├── experiment.sh                         # Experiment orchestration functions
│   ├── kubernetes.sh                         # Kubernetes interaction functions
│   ├── logger.sh                             # Logging utilities
│   ├── metrics.sh                            # Metrics collection functions
│   └── tenant_metrics.sh                     # Tenant-specific metrics definitions
├── manifests/                                # Kubernetes manifests for workloads and namespaces
│   ├── ingress-controller/                   # Ingress controller configuration
│   ├── namespace/                            # Namespace and resource quota definitions
│   │   ├── limited-resource-quotas.yaml      # Resource quotas for limited resources mode
│   │   └── resource-quotas.yaml              # Standard resource quotas
│   ├── tenant-a/                             # Network-sensitive workloads
│   ├── tenant-b/                             # Noisy neighbor workloads
│   ├── tenant-c/                             # Memory-sensitive workloads
│   └── tenant-d/                             # CPU and disk-sensitive workloads
├── observability/                            # Prometheus and Grafana configurations
│   ├── grafana-dashboards/                   # Grafana dashboards
│   ├── prometheus-rules/                     # Prometheus alerting rules
│   ├── servicemonitors/                      # ServiceMonitors for tenants
│   └── tenant-metrics.yaml                   # Tenant-specific metric definitions
└── results/                                  # Directory for experiment results
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

### 6. Data Analysis

After collecting the experiment results, you can analyze them using the analysis pipeline:

1. **Configure the experiment variables**:
   
   Edit the `analysis_pipeline/main.py` file to point to your experiment:
   ```python
   EXPERIMENT_NAME = "YYYY-MM-DD/HH-MM-SS/default-experiment-1"
   ROUND = "round-1"
   PHASES = ["1 - Baseline", "2 - Attack", "3 - Recovery"]
   ```

2. **Run the analysis pipeline**:
   ```bash
   cd analysis_pipeline
   python main.py
   ```

3. **View the results**:
   
   The results will be organized in the following folders:
   ```
   plots/                           # Basic visualizations
   ├── 1_-_Baseline/                # Charts from the baseline phase
   ├── 2_-_Attack/                  # Charts from the attack phase
   ├── 3_-_Recovery/                # Charts from the recovery phase
   └── comparacao_fases/            # Comparisons between phases
   
   plots/time_series_analysis/      # Advanced time series analyses
   ├── cross_corr_*.png             # Cross-correlation graphs
   ├── lag_analysis_*.png           # Lag analyses
   └── entropy_*.png                # Entropy analyses
   
   stats_results/                   # Statistical results in CSV and LaTeX
   ├── granger_*.csv                # Granger causality results
   └── entropy_*.csv                # Entropy analysis results
   ```

The pipeline provides:
- Complete statistical analysis of metrics by tenant and component
- Correlations between different metrics (identifying cause-effect relationships)
- Advanced time series analyses to detect complex patterns:
  - **Cross-correlation**: Identifies correlations considering different time lags
  - **Lag analysis**: Determines the optimal delay between related events
  - **Granger causality**: Statistically evaluates if one time series causes another
  - **Entropy analysis**: Quantifies the complexity and regularity of the series
- Comparative graphs between experiment phases
- Automatic identification of metrics with significant variation during attacks

For more details about data analysis, see the [analysis pipeline documentation](analysis_pipeline/README.md).

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

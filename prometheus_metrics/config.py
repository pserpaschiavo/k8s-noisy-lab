"""
Configurações para conexão com o Prometheus e definições das métricas.
"""
import os
import pathlib

# Define a raiz do repositório (2 níveis acima deste arquivo)
REPO_ROOT = pathlib.Path(__file__).parent.parent.absolute()

# Configurações de conexão
PROMETHEUS_URL = "http://localhost:9090"
REQUEST_TIMEOUT = 30  # segundos

# Período padrão para consultas - alterado para maior sensibilidade
DEFAULT_PERIOD = "1m"  # Últimos 1 minuto - para maior sensibilidade
DEFAULT_STEP = "5s"    # Intervalos de 5 segundos - para maior granularidade

# Métricas simples - focadas em workloads por namespace e pod
BASIC_METRICS = {
    "container_cpu": "container_cpu_usage_seconds_total",
    "container_memory": "container_memory_working_set_bytes",
    "container_network_rx": "container_network_receive_bytes_total",
    "container_network_tx": "container_network_transmit_bytes_total",
    "container_cpu_throttled_periods": "container_cpu_cfs_throttled_periods_total",
    "container_cpu_periods": "container_cpu_cfs_periods_total",
    "container_fs_writes": "container_fs_writes_bytes_total",
    "container_fs_reads": "container_fs_reads_bytes_total",
    "node_pressure_cpu": "node_pressure_cpu_waiting_seconds_total",
    "node_pressure_memory": "node_pressure_memory_waiting_seconds_total",
    "node_pressure_io": "node_pressure_io_waiting_seconds_total",
    "kube_pod_container_status_restarts_total": "kube_pod_container_status_restarts_total"
}

# Métricas calculadas para visualização de noisy neighbours
CALCULATED_METRICS = {
    # Métricas por namespace e pod - simplificadas conforme solicitado
    "cpu_usage_by_namespace": 'sum(rate(container_cpu_usage_seconds_total[1m])) by (namespace)',
    "cpu_usage_by_pod": 'sum(rate(container_cpu_usage_seconds_total[1m])) by (namespace, pod)',
    "memory_usage_by_namespace": 'sum(container_memory_working_set_bytes) by (namespace)',
    "memory_usage_by_pod": 'sum(container_memory_working_set_bytes) by (namespace, pod)',
    "network_tx_by_namespace": 'sum(rate(container_network_transmit_bytes_total[1m])) by (namespace)',
    "network_rx_by_namespace": 'sum(rate(container_network_receive_bytes_total[1m])) by (namespace)',
    
    # Métricas específicas para noisy neighbours
    "cpu_throttling_by_pod": 'sum(rate(container_cpu_cfs_throttled_periods_total[1m])) by (namespace, pod) / sum(rate(container_cpu_cfs_periods_total[1m])) by (namespace, pod)',
    "cpu_usage_percent_limit": 'sum(rate(container_cpu_usage_seconds_total[1m])) by (pod, namespace) * 100 / sum(kube_pod_container_resource_limits{resource="cpu"}) by (pod, namespace)',
    "memory_usage_percent_limit": 'sum(container_memory_working_set_bytes) by (pod, namespace) * 100 / sum(kube_pod_container_resource_limits_bytes{resource="memory"}) by (pod, namespace)',
    
    # Métricas de interferência - novas e relevantes
    "cpu_saturation": 'node:node_cpu_saturation_load1:',
    "memory_saturation": 'node:node_memory_swap_io_bytes:sum_rate',
    "disk_io_utilization": 'sum(rate(node_disk_io_time_seconds_total[1m])) by (instance) / scalar(count(node_disk_io_time_seconds_total)) * 100',
    "node_cpu_utilization": 'sum(rate(node_cpu_seconds_total{mode!="idle"}[1m])) by (instance) / scalar(count(node_cpu_seconds_total{mode="idle"})) * 100',
    
    # Métricas de correlação entre tenants
    "tenant_a_to_tenant_c_cpu_ratio": 'sum(rate(container_cpu_usage_seconds_total{namespace="tenant-a"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace="tenant-c"}[1m]))',
    "tenant_b_to_tenant_c_cpu_ratio": 'sum(rate(container_cpu_usage_seconds_total{namespace="tenant-b"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace="tenant-c"}[1m]))',
    "pod_restart_rate": 'sum(rate(kube_pod_container_status_restarts_total[5m])) by (namespace, pod)',
}

# Configurações de saída - caminho relativo à raiz do repositório
OUTPUT_DIR = os.path.join(REPO_ROOT, "data")

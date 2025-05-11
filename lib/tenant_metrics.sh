#!/bin/bash

# Importar logger
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/lib/logger.sh"

# Queries PromQL para métricas específicas do tenant-a (sensível à rede)
declare -A TENANT_A_METRICS=(
    ["network_receive"]="sum(rate(container_network_receive_bytes_total{namespace=\"tenant-a\"}[1m]))"
    ["network_transmit"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-a\"}[1m]))"
    ["network_dropped"]="sum(rate(container_network_receive_packets_dropped_total{namespace=\"tenant-a\"}[1m]))"
    ["network_packet_rate"]="sum(rate(container_network_receive_packets_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_transmit_packets_total{namespace=\"tenant-a\"}[1m]))"
    ["network_error_rate"]="sum(rate(container_network_receive_errors_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_transmit_errors_total{namespace=\"tenant-a\"}[1m]))"
    ["network_efficiency"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-a\"}[1m])) / sum(rate(container_network_transmit_packets_total{namespace=\"tenant-a\"}[1m]))"
)

# Queries PromQL para métricas específicas do tenant-b (barulhento - atacante)
declare -A TENANT_B_METRICS=(
    ["cpu_usage"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m]))"
    ["memory_usage"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"})"
    ["network_transmit"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-b\"}[1m]))"
    ["network_receive"]="sum(rate(container_network_receive_bytes_total{namespace=\"tenant-b\"}[1m]))"
    ["resource_dominance_index"]="(sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))) * (sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}))"
    ["cpu_throttled_ratio"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_cfs_periods_total{namespace=\"tenant-b\"}[1m]))"
)

# Queries PromQL para métricas específicas do tenant-c (sensível à memória)
declare -A TENANT_C_METRICS=(
    ["memory_usage"]="sum(container_memory_working_set_bytes{namespace=\"tenant-c\"})"
    ["memory_pressure"]="sum(container_memory_working_set_bytes{namespace=\"tenant-c\"}) / sum(container_spec_memory_limit_bytes{namespace=\"tenant-c\"})"
    ["memory_growth_rate"]="deriv(sum(container_memory_working_set_bytes{namespace=\"tenant-c\"})[10m:])"
    ["memory_oomkill_events"]="sum(kube_pod_container_status_last_terminated_reason{namespace=\"tenant-c\", reason=\"OOMKilled\"})"
    ["pod_restarts"]="sum(kube_pod_container_status_restarts_total{namespace=\"tenant-c\"})"
)

# Queries PromQL para métricas específicas do tenant-d (sensível a CPU e disco)
declare -A TENANT_D_METRICS=(
    ["cpu_usage"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-d\"}[1m]))"
    ["cpu_throttled_time"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=\"tenant-d\"}[1m]))"
    ["disk_io_total"]="sum(rate(container_fs_reads_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_total{namespace=\"tenant-d\"}[1m]))"
    ["disk_throughput_total"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m]))"
    ["disk_io_tenant_d"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m])) by (container)"
    ["postgres_disk_io"]="sum(rate(pg_stat_database_blks_read{namespace=\"tenant-d\"}[1m]) + rate(pg_stat_database_blks_written{namespace=\"tenant-d\"}[1m])) by (datname)"
    ["postgres_connections"]="sum(pg_stat_database_numbackends{namespace=\"tenant-d\"}) by (datname)"
    ["postgres_transactions"]="sum(rate(pg_stat_database_xact_commit{namespace=\"tenant-d\"}[1m]) + rate(pg_stat_database_xact_rollback{namespace=\"tenant-d\"}[1m])) by (datname)"
)

# Métricas de relação entre o tenant-b (barulhento) e o tenant-a (sensível à rede)
declare -A TENANT_B_VS_A_METRICS=(
    ["cpu_usage_noisy_network_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-a\"}[1m]))"
    ["memory_usage_noisy_network_ratio"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=\"tenant-a\"})"
    ["network_usage_noisy_network_ratio"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-a\"}[1m]))"
    ["network_packets_noisy_network_ratio"]="sum(rate(container_network_transmit_packets_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_packets_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_packets_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_receive_packets_total{namespace=\"tenant-a\"}[1m]))"
    ["network_dropped_noisy_network_ratio"]="sum(rate(container_network_receive_packets_dropped_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_transmit_packets_dropped_total{namespace=\"tenant-b\"}[1m])) / (sum(rate(container_network_receive_packets_dropped_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_transmit_packets_dropped_total{namespace=\"tenant-a\"}[1m])) + 1)"
)

# Métricas de relação entre o tenant-b (barulhento) e o tenant-c (sensível à memória)
declare -A TENANT_B_VS_C_METRICS=(
    ["cpu_usage_noisy_victim_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-c\"}[1m]))"
    ["memory_usage_noisy_victim_ratio"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=\"tenant-c\"})"
    ["network_usage_noisy_victim_ratio"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-c\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-c\"}[1m]))"
)

# Métricas de relação entre o tenant-b (barulhento) e o tenant-d (sensível a CPU e disco)
declare -A TENANT_B_VS_D_METRICS=(
    ["cpu_tenant_d_vs_other_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-d\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]))"
    ["disk_tenant_d_vs_other_ratio"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m])) / sum(rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]))"
)

# Função para obter métrica específica do tenant
get_tenant_metric() {
    local tenant="$1"
    local metric_name="$2"
    
    case "$tenant" in
        "tenant-a")
            echo "${TENANT_A_METRICS[$metric_name]}"
            ;;
        "tenant-b")
            echo "${TENANT_B_METRICS[$metric_name]}"
            ;;
        "tenant-c")
            echo "${TENANT_C_METRICS[$metric_name]}"
            ;;
        "tenant-d")
            echo "${TENANT_D_METRICS[$metric_name]}"
            ;;
        "tenant-b-vs-a")
            echo "${TENANT_B_VS_A_METRICS[$metric_name]}"
            ;;
        "tenant-b-vs-c")
            echo "${TENANT_B_VS_C_METRICS[$metric_name]}"
            ;;
        "tenant-b-vs-d")
            echo "${TENANT_B_VS_D_METRICS[$metric_name]}"
            ;;
        *)
            log "$RED" "Tenant desconhecido: $tenant"
            return 1
            ;;
    esac
}

# Função para listar todas as métricas disponíveis para um tenant
list_tenant_metrics() {
    local tenant="$1"
    
    case "$tenant" in
        "tenant-a")
            for metric in "${!TENANT_A_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        "tenant-b")
            for metric in "${!TENANT_B_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        "tenant-c")
            for metric in "${!TENANT_C_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        "tenant-d")
            for metric in "${!TENANT_D_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        "tenant-b-vs-a")
            for metric in "${!TENANT_B_VS_A_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        "tenant-b-vs-c")
            for metric in "${!TENANT_B_VS_C_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        "tenant-b-vs-d")
            for metric in "${!TENANT_B_VS_D_METRICS[@]}"; do
                echo "$metric"
            done
            ;;
        *)
            log "$RED" "Tenant desconhecido: $tenant"
            return 1
            ;;
    esac
}
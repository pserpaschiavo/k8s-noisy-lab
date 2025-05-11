#!/bin/bash

# Importar logger e métricas de tenant
source "$(dirname "$0")/logger.sh"
source "$(dirname "$0")/tenant_metrics.sh"

# Variável para armazenar o PID do processo de coleta de métricas
METRICS_PID=""

# Função para combinar todas as métricas dos tenants em um único array
combine_all_metrics() {
    # Inicializar um array associativo vazio para todas as métricas
    declare -A ALL_METRICS
    
    # Adicionar métricas do tenant-a
    for metric_name in $(list_tenant_metrics "tenant-a"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-a" "$metric_name")
    done
    
    # Adicionar métricas do tenant-b
    for metric_name in $(list_tenant_metrics "tenant-b"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-b" "$metric_name")
    done
    
    # Adicionar métricas do tenant-c
    for metric_name in $(list_tenant_metrics "tenant-c"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-c" "$metric_name")
    done
    
    # Adicionar métricas do tenant-d
    for metric_name in $(list_tenant_metrics "tenant-d"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-d" "$metric_name")
    done
    
    # Adicionar métricas de relação tenant-b vs tenant-a
    for metric_name in $(list_tenant_metrics "tenant-b-vs-a"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-b-vs-a" "$metric_name")
    done
    
    # Adicionar métricas de relação tenant-b vs tenant-c
    for metric_name in $(list_tenant_metrics "tenant-b-vs-c"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-b-vs-c" "$metric_name")
    done
    
    # Adicionar métricas de relação tenant-b vs tenant-d
    for metric_name in $(list_tenant_metrics "tenant-b-vs-d"); do
        ALL_METRICS["$metric_name"]=$(get_tenant_metric "tenant-b-vs-d" "$metric_name")
    done
    
    # Adicionar métricas adicionais do NGINX ingress controller
    ALL_METRICS["nginx_connections"]="sum(nginx_ingress_controller_nginx_process_connections{namespace=~\"ingress-nginx\",state=~\"active|reading|writing|waiting\"}) by (state)"
    ALL_METRICS["nginx_connections_total"]="sum(rate(nginx_ingress_controller_nginx_process_connections_total{namespace=~\"ingress-nginx\"}[1m])) by (state)"
    ALL_METRICS["nginx_cpu_usage"]="rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=~\"ingress-nginx\"}[1m])"
    ALL_METRICS["nginx_memory_usage"]="nginx_ingress_controller_nginx_process_resident_memory_bytes{namespace=~\"ingress-nginx\"}"
    ALL_METRICS["nginx_requests_total"]="rate(nginx_ingress_controller_nginx_process_requests_total{namespace=~\"ingress-nginx\"}[1m])"
    ALL_METRICS["nginx_bytes_read"]="rate(nginx_ingress_controller_nginx_process_read_bytes_total{namespace=~\"ingress-nginx\"}[1m])"
    ALL_METRICS["nginx_bytes_written"]="rate(nginx_ingress_controller_nginx_process_write_bytes_total{namespace=~\"ingress-nginx\"}[1m])"
    
    # Métricas de latência e jitter
    ALL_METRICS["latency_process_time"]="rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=~\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_connections_total{namespace=~\"ingress-nginx\",state=\"handled\"}[1m])"
    ALL_METRICS["latency_bytes_per_request"]="rate(nginx_ingress_controller_nginx_process_read_bytes_total{namespace=~\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_requests_total{namespace=~\"ingress-nginx\"}[1m])"
    ALL_METRICS["jitter_admission_process"]="stddev_over_time(nginx_ingress_controller_admission_roundtrip_duration{namespace=\"ingress-nginx\"}[5m])"
    ALL_METRICS["jitter_processing_rate"]="stddev_over_time(rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=\"ingress-nginx\"}[1m])[5m:1m])"
    
    echo "$(declare -p ALL_METRICS)"
}

# Criar o array PROM_QUERIES com todas as métricas combinadas
eval "$(combine_all_metrics)"

# Função de coleta contínua com logs de erro e fallback de label
collect_metrics_continuously() {
    local phase_id="$1" round_num="$2" metrics_dir="$3"
    # Usar o intervalo de coleta de métricas definido no script principal ou o valor padrão
    local interval="${METRICS_INTERVAL:-5}"
    
    log "$BLUE" "Coletando métricas a cada ${interval} segundos..."
    
    while true; do
        local ts=$(date +%Y%m%d_%H%M%S)
        for name in "${!PROM_QUERIES[@]}"; do
            local query="${PROM_QUERIES[$name]}"
            # Chama API Prometheus
            local resp
            if ! resp=$(curl -s --connect-timeout 5 "http://localhost:9090/api/v1/query?query=$(printf '%s' "$query" | jq -sRr @uri)"); then
                echo "[$ts] ERROR: curl failed for $name" >> "$LOG_FILE"
                continue
            fi
            # Extrai namespace e valor, cada linha CSV: ns,val
            local csv_lines
            csv_lines=$(echo "$resp" | jq -r '.data.result[]? | [(.metric.namespace // .metric.pod // .metric.instance // "unknown"), (.value[1] // "")] | @csv')
            if [ -z "$csv_lines" ]; then
                echo "[$ts] WARN: no data for $name" >> "$LOG_FILE"
                continue
            fi
            # Grava cada linha em CSV por namespace
            while IFS=',' read -r ns val; do
                ns=${ns//\"/}
                val=${val//\"/}
                local out_dir="$metrics_dir/round-${round_num}/${phase_id}/${ns}"
                mkdir -p "$out_dir"
                local file="$out_dir/${name}.csv"
                if [ ! -f "$file" ]; then
                    echo "timestamp,value" > "$file"
                fi
                echo "\"${ts}\",\"${val}\"" >> "$file"
            done <<< "$csv_lines"
        done
        sleep $interval
    done
}

# Função para iniciar a coleta contínua
start_collecting_metrics() {
    local phase="$1"
    local round="$2"
    local metrics_dir="$3"
    local collect_metrics="$4"
    
    if [ "$collect_metrics" = true ]; then
        collect_metrics_continuously "$phase" "$round" "$metrics_dir" &
        METRICS_PID=$!
        log "$BLUE" "Coleta de métricas iniciada com PID: $METRICS_PID"
    else
        log "$YELLOW" "Coleta de métricas desativada"
    fi
}

# Função para interromper a coleta
stop_collecting_metrics() {
    if [ -n "$METRICS_PID" ] && kill -0 $METRICS_PID 2>/dev/null; then
        log "$BLUE" "Interrompendo coleta de métricas (PID: $METRICS_PID)..."
        kill $METRICS_PID
        wait $METRICS_PID 2>/dev/null || true
        log "$BLUE" "Coleta de métricas finalizada."
    fi
    unset METRICS_PID
}
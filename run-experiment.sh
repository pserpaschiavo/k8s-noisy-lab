#!/bin/bash

set -eo pipefail

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NO_COLOR='\033[0m'

# Diretório base
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Configurações padrão
EXPERIMENT_NAME="noisy-neighbours"
NUM_ROUNDS=3
BASELINE_DURATION=180   # segundos (3 minutos)
ATTACK_DURATION=300     # segundos (5 minutos)
RECOVERY_DURATION=180   # segundos (3 minutos)
COLLECT_METRICS=true
CUSTOM_SCENARIO=""

# Diretório para resultados (criado após parsing de args)
METRICS_DIR=""
LOG_FILE=""

# Função de ajuda
show_help() {
    echo "Uso: $0 [opções]"
    echo
    echo "Opções:"
    echo "  -h, --help                 Mostra esta ajuda"
    echo "  -n, --name NOME            Define o nome do experimento"
    echo "  -r, --rounds NUM           Define o número de rounds"
    echo "  -b, --baseline SEGUNDOS    Define a duração da baseline"
    echo "  -a, --attack SEGUNDOS      Define a duração do ataque"
    echo "  -c, --recovery SEGUNDOS    Define a duração da recuperação"
    echo "  --no-metrics               Desativa a coleta de métricas"
}

# Processamento de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;      
        -n|--name) EXPERIMENT_NAME="$2"; shift 2 ;;  
        -r|--rounds) NUM_ROUNDS="$2"; shift 2 ;;      
        -b|--baseline) BASELINE_DURATION="$2"; shift 2 ;; 
        -a|--attack) ATTACK_DURATION="$2"; shift 2 ;;   
        -c|--recovery) RECOVERY_DURATION="$2"; shift 2 ;; 
        --no-metrics) COLLECT_METRICS=false; shift ;;  
        *) echo "Opção desconhecida: $1"; show_help; exit 1 ;; 
    esac
done

# Preparar diretórios de métricas e logs
START_DATE=$(date +%Y-%m-%d)
START_TIME=$(date +%H-%M-%S)
METRICS_DIR="${BASE_DIR}/results/${START_DATE}/${START_TIME}/${EXPERIMENT_NAME}"
mkdir -p "$METRICS_DIR"
LOG_FILE="${METRICS_DIR}/experiment.log"

# Função de log
log() {
    local color="$1" message="$2"
    printf "%b%s%b\n" "$color" "$message" "$NO_COLOR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

# Queries PromQL para coleta de métricas (séries temporais)
declare -A PROM_QUERIES=(
    # Métricas existentes de recursos
    ["cpu_usage"]="sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) by (namespace)"
    ["cpu_throttled_time"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) by (namespace)"
    ["cpu_throttled_ratio"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) / sum(rate(container_cpu_cfs_periods_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["memory_usage"]="sum(container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}) by (namespace)"
    ["oom_kills"]="sum(increase(container_oom_events_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[5m])) by (namespace)"
    ["network_transmit"]="sum(rate(container_network_transmit_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) by (namespace)"
    ["network_receive"]="sum(rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) by (namespace)"
    ["network_dropped"]="sum(rate(container_network_receive_packets_dropped_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) by (namespace)"
    
    # Métricas básicas do NGINX Ingress Controller
    ["nginx_connections"]="sum(nginx_ingress_controller_nginx_process_connections{namespace=~\"ingress-nginx\",state=~\"active|reading|writing|waiting\"}) by (state)"
    ["nginx_connections_total"]="sum(rate(nginx_ingress_controller_nginx_process_connections_total{namespace=~\"ingress-nginx\"}[1m])) by (state)"
    ["nginx_cpu_usage"]="rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=~\"ingress-nginx\"}[1m])"
    ["nginx_memory_usage"]="nginx_ingress_controller_nginx_process_resident_memory_bytes{namespace=~\"ingress-nginx\"}"
    ["nginx_requests_total"]="rate(nginx_ingress_controller_nginx_process_requests_total{namespace=~\"ingress-nginx\"}[1m])"
    ["nginx_bytes_read"]="rate(nginx_ingress_controller_nginx_process_read_bytes_total{namespace=~\"ingress-nginx\"}[1m])"
    ["nginx_bytes_written"]="rate(nginx_ingress_controller_nginx_process_write_bytes_total{namespace=~\"ingress-nginx\"}[1m])"
    
    # Outras métricas de cluster
    ["pod_restarts"]="increase(kube_pod_container_status_restarts_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[5m])"
    ["pod_ready_age"]="time() - kube_pod_status_ready{condition=\"true\",namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}"
    
    # Métricas de latência (baseadas na análise do tempo de processamento)
    ["latency_process_time"]="rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=~\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_connections_total{namespace=~\"ingress-nginx\",state=\"handled\"}[1m])"
    ["latency_bytes_per_request"]="rate(nginx_ingress_controller_nginx_process_read_bytes_total{namespace=~\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_requests_total{namespace=~\"ingress-nginx\"}[1m])"
    
    # Métricas de jitter (variação nas métricas de processamento)
    ["jitter_admission_process"]="stddev_over_time(nginx_ingress_controller_admission_roundtrip_duration{namespace=\"ingress-nginx\"}[5m])"
    ["jitter_processing_rate"]="stddev_over_time(rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=\"ingress-nginx\"}[1m])[5m:1m])"
    
    # Métricas de correlação para análise de noisy neighbor
    ["correlation_cpu_latency"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / on() group_left() (rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_requests_total{namespace=\"ingress-nginx\"}[1m]))"
    ["correlation_memory_latency"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / on() group_left() (rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_requests_total{namespace=\"ingress-nginx\"}[1m]))"
    
    # Métricas comparativas entre tenants (referência vs. vítima)
    ["tenant_latency_comparison"]="avg(rate(container_cpu_usage_seconds_total{namespace=\"tenant-a\"}[1m]) / rate(container_network_receive_packets_total{namespace=\"tenant-a\"}[1m])) / avg(rate(container_cpu_usage_seconds_total{namespace=\"tenant-c\"}[1m]) / rate(container_network_receive_packets_total{namespace=\"tenant-c\"}[1m]))"
    ["tenant_jitter"]="stddev_over_time((rate(container_network_receive_packets_total{namespace=~\"tenant-a|tenant-c|tenant-d\"}[1m]) / rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-c|tenant-d\"}[1m]))[5m:1m])"
    
    # MÉTRICAS AVANÇADAS DE CPU
    ["cpu_usage_variability"]="stddev_over_time(sum by (namespace) (rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))[5m:])"
    ["cpu_usage_pct_of_limit"]="sum by (namespace) (rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) * 100) / sum by (namespace) (kube_pod_container_resource_limits{resource=\"cpu\", namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"})"
    
    # MÉTRICAS AVANÇADAS DE MEMÓRIA
    ["memory_pressure"]="sum by (namespace) (container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}) / sum by (namespace) (container_spec_memory_limit_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"})"
    ["memory_growth_rate"]="deriv(sum by (namespace) (container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"})[10m:])"
    ["memory_oomkill_events"]="sum by (namespace) (kube_pod_container_status_last_terminated_reason{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\", reason=\"OOMKilled\"})"
    
    # MÉTRICAS AVANÇADAS DE REDE
    ["network_total_bandwidth"]="sum by (namespace) (rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_network_transmit_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["network_packet_rate"]="sum by (namespace) (rate(container_network_receive_packets_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_network_transmit_packets_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["network_error_rate"]="sum by (namespace) (rate(container_network_receive_errors_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_network_transmit_errors_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["network_efficiency"]="sum by (namespace) (rate(container_network_transmit_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) / sum by (namespace) (rate(container_network_transmit_packets_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    
    # MÉTRICAS AVANÇADAS DE DISCO
    ["disk_io_total"]="sum by (namespace) (rate(container_fs_reads_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_fs_writes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["disk_throughput_total"]="sum by (namespace) (rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["disk_avg_io_size"]="sum by (namespace) (rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])) / sum by (namespace) (rate(container_fs_reads_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_fs_writes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    
    # MÉTRICAS COMBINADAS E RELAÇÕES ENTRE TENANTS (TENANT-C - VÍTIMA RECURSOS GERAIS)
    ["cpu_usage_noisy_victim_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-c\"}[1m]))"
    ["memory_usage_noisy_victim_ratio"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=\"tenant-c\"})"
    ["network_usage_noisy_victim_ratio"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-c\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-c\"}[1m]))"
    ["resource_dominance_index"]="(sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))) * (sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}))"
    
    # NOVAS MÉTRICAS DE RELAÇÃO ENTRE TENANT-B (BARULHENTO) E TENANT-A (SENSÍVEL À REDE)
    ["cpu_usage_noisy_network_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-a\"}[1m]))"
    ["memory_usage_noisy_network_ratio"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=\"tenant-a\"})"
    ["network_usage_noisy_network_ratio"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-a\"}[1m]))"
    ["network_packets_noisy_network_ratio"]="sum(rate(container_network_transmit_packets_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_packets_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_packets_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_receive_packets_total{namespace=\"tenant-a\"}[1m]))"
    ["network_dropped_noisy_network_ratio"]="sum(rate(container_network_receive_packets_dropped_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_transmit_packets_dropped_total{namespace=\"tenant-b\"}[1m])) / (sum(rate(container_network_receive_packets_dropped_total{namespace=\"tenant-a\"}[1m]) + rate(container_network_transmit_packets_dropped_total{namespace=\"tenant-a\"}[1m])) + 1)"
    
    # MÉTRICAS DE SAÚDE DO CLUSTER
    ["pod_readiness_ratio"]="sum by (namespace) (kube_pod_status_ready{condition=\"true\",namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}) / count by (namespace) (kube_pod_info{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"})"
    ["pending_pods"]="sum by (namespace) (kube_pod_status_phase{phase=\"Pending\",namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"})"
    
    # MÉTRICAS ESPECÍFICAS PARA MONITORAR TENANT-D (CPU E DISCO)
    ["postgres_disk_io"]="sum(rate(pg_stat_database_blks_read{namespace=\"tenant-d\"}[1m]) + rate(pg_stat_database_blks_written{namespace=\"tenant-d\"}[1m])) by (datname)"
    ["postgres_connections"]="sum(pg_stat_database_numbackends{namespace=\"tenant-d\"}) by (datname)"
    ["postgres_transactions"]="sum(rate(pg_stat_database_xact_commit{namespace=\"tenant-d\"}[1m]) + rate(pg_stat_database_xact_rollback{namespace=\"tenant-d\"}[1m])) by (datname)"
    ["postgres_query_time"]="sum(pg_stat_statements_mean_exec_time{namespace=\"tenant-d\"}) by (query)"
    ["disk_io_tenant_d"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m])) by (container)"
    ["cpu_tenant_d_vs_other_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-d\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]))"
    ["disk_tenant_d_vs_other_ratio"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m])) / sum(rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]))"
)

# Função para garantir namespace existe
ensure_namespace() {
    local ns="$1"
    if ! kubectl get namespace "$ns" &> /dev/null; then
        log "$YELLOW" "Namespace '$ns' não existe. Criando..."
        kubectl create namespace "$ns"
    else
        log "$GREEN" "Namespace '$ns' já existe."
    fi
}

# Garantir namespaces antes de prosseguir
for ns in tenant-a tenant-b tenant-c tenant-d monitoring ingress-nginx; do
    ensure_namespace "$ns"
done

# Função para executar comando com timeout
execute_with_timeout() {
    local phase="$1" duration="$2" cmd="$3"
    log "$YELLOW" "Iniciando fase: $phase com duração máxima de ${duration}s"
    eval "$cmd" &
    local pid=$!
    sleep "$duration"
    if kill -0 "$pid" 2>/dev/null; then
        log "$RED" "Timeout de fase $phase atingido. Matando processo $pid"
        kill -9 "$pid" || true
    fi
    wait "$pid" 2>/dev/null || true
    log "$GREEN" "Fase $phase concluída"
}

# Função para garantir que todos os pods estão prontos em um namespace
wait_for_pods_ready() {
    local namespace="$1"
    local timeout="$2"
    local interval=5
    local elapsed=0
    local all_ready=false

    log "$YELLOW" "Aguardando pods no namespace $namespace ficarem prontos (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        # Verifica se existem pods no namespace
        local pod_count=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
        if [ "$pod_count" -eq 0 ]; then
            log "$YELLOW" "Nenhum pod encontrado no namespace $namespace. Verificando novamente..."
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi

        # Verifica se todos os pods estão em estado Running ou Completed
        local not_running=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
        
        # Verifica se todos os containers em todos os pods estão prontos
        local not_ready=$(kubectl get pods -n "$namespace" -o json | jq -r '.items[] | select(.status.containerStatuses != null) | select((.status.containerStatuses | map(.ready) | all) == false) | .metadata.name' | wc -l)
        
        # Verifica se há pods com restarts frequentes
        local restart_issues=$(kubectl get pods -n "$namespace" -o json | jq -r '.items[] | select(.status.containerStatuses != null) | select(any(.status.containerStatuses[]; .restartCount > 2)) | .metadata.name' | wc -l)
        
        if [ "$not_running" -eq 0 ] && [ "$not_ready" -eq 0 ] && [ "$restart_issues" -eq 0 ]; then
            all_ready=true
            break
        fi
        
        # Exibe informações detalhadas sobre os pods não prontos
        if [ $((elapsed % 15)) -eq 0 ]; then  # A cada 15 segundos exibe informações detalhadas
            log "$YELLOW" "Status dos pods em $namespace:"
            kubectl get pods -n "$namespace"
            if [ "$not_running" -ne 0 ] || [ "$not_ready" -ne 0 ]; then
                log "$YELLOW" "Detalhes dos pods com problemas:"
                kubectl describe pods -n "$namespace" | grep -A10 "State:" | grep -B2 -A8 -i "waiting\|error\|crash"
            fi
        else
            log "$YELLOW" "Aguardando pods no namespace $namespace... ($elapsed/${timeout}s) - $not_ready pods ainda não prontos, $not_running não em execução"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ "$all_ready" = true ]; then
        log "$GREEN" "Todos os pods no namespace $namespace estão prontos!"
        return 0
    else
        log "$RED" "Timeout aguardando pods no namespace $namespace"
        log "$RED" "Status atual dos pods:"
        kubectl get pods -n "$namespace"
        kubectl describe pods -n "$namespace" | grep -A10 "State:" | grep -B2 -A8 -i "waiting\|error\|crash"
        return 1
    fi
}

# Função para verificar se todos os pods em múltiplos namespaces estão prontos
wait_for_all_tenants_ready() {
    local timeout="$1"
    local success=true
    
    log "$YELLOW" "Verificando se todos os tenants estão prontos..."
    
    for ns in tenant-a tenant-b tenant-c tenant-d; do
        if kubectl get namespace "$ns" &> /dev/null; then
            if ! wait_for_pods_ready "$ns" "$timeout"; then
                success=false
                log "$RED" "Problemas detectados no namespace $ns"
            fi
        fi
    done
    
    # Também verificar o namespace do ingress-nginx se existir
    if kubectl get namespace ingress-nginx &> /dev/null; then
        if ! wait_for_pods_ready "ingress-nginx" "$timeout"; then
            success=false
            log "$RED" "Problemas detectados no namespace ingress-nginx"
        fi
    fi
    
    if [ "$success" = true ]; then
        log "$GREEN" "Todos os tenants estão prontos!"
        return 0
    else
        log "$YELLOW" "Nem todos os tenants estão completamente prontos, verificando se é possível continuar..."
        
        # Verifica se pelo menos os pods mais críticos estão funcionando
        local critical_ready=true
        
        # Verificar tenant-a (sensível à rede)
        if kubectl get namespace tenant-a &> /dev/null; then
            if [ "$(kubectl get pods -n tenant-a -l app=nginx --no-headers 2>/dev/null | grep -v "Running" | wc -l)" -ne 0 ]; then
                critical_ready=false
                log "$RED" "Os pods críticos do tenant-a não estão prontos."
            fi
        fi
        
        if [ "$critical_ready" = true ]; then
            log "$YELLOW" "Os pods críticos estão funcionando. Continuando, mas os resultados podem ser afetados."
            return 0
        else
            log "$RED" "Pods críticos não estão prontos. O experimento pode falhar."
            return 1
        fi
    fi
}

# Função de coleta contínua com logs de erro e fallback de label
collect_metrics_continuously() {
    local phase_id="$1" round_num="$2"
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
                local out_dir="$METRICS_DIR/round-${round_num}/${phase_id}/${ns}"
                mkdir -p "$out_dir"
                local file="$out_dir/${name}.csv"
                if [ ! -f "$file" ]; then
                    echo "timestamp,value" > "$file"
                fi
                echo "\"${ts}\",\"${val}\"" >> "$file"
            done <<< "$csv_lines"
        done
        sleep 5
    done
}

# Função para iniciar a coleta contínua
start_collecting_metrics() {
    local phase=$1
    local round=$2
    
    if [ "$COLLECT_METRICS" = true ]; then
        collect_metrics_continuously "$phase" "$round" &
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

# Função para limpar os tenants após o experimento
cleanup_tenants() {
    log "$BLUE" "Limpando todos os tenants após o experimento..."
    kubectl delete namespace tenant-a tenant-b tenant-c tenant-d --ignore-not-found=true >> "$LOG_FILE" 2>&1 || true
    log "$GREEN" "Tenants removidos com sucesso."
}

# Função para perguntar se deve continuar para o próximo round
continue_prompt() {
    local next_round=$1
    local total_rounds=$2
    
    if [ "$next_round" -le "$total_rounds" ]; then
        echo
        log "$YELLOW" "Round $((next_round-1))/$total_rounds concluído."
        read -p "Continuar para o round $next_round/$total_rounds? (s/n): " response
        case "$response" in
            [Ss]* ) 
                log "$GREEN" "Continuando para o próximo round..."
                return 0
                ;;
            * ) 
                log "$RED" "Experimento interrompido pelo usuário."
                cleanup_tenants
                log "$GREEN" "======= EXPERIMENTO INTERROMPIDO PELO USUÁRIO ======="
                log "$GREEN" "Métricas e logs parciais salvos em: ${METRICS_DIR}"
                exit 0
                ;;
        esac
    fi
}

# Função para perguntar se deve continuar para a próxima fase
continue_to_next_phase() {
    local current_phase=$1
    local next_phase=$2
    
    echo
    log "$YELLOW" "Fase '$current_phase' concluída."
    read -p "Continuar para a fase '$next_phase'? (s/n): " response
    case "$response" in
        [Ss]* ) 
            log "$GREEN" "Continuando para a próxima fase..."
            return 0
                ;;
            * ) 
                log "$RED" "Experimento interrompido pelo usuário durante a transição de fase."
                cleanup_tenants
                log "$GREEN" "======= EXPERIMENTO INTERROMPIDO PELO USUÁRIO ======="
                log "$GREEN" "Métricas e logs parciais salvos em: ${METRICS_DIR}"
                exit 0
                ;;
        esac
    fi
}

# Log inicial
log "$GREEN" "Iniciando experimento: $EXPERIMENT_NAME"
log "$GREEN" "Log sendo salvo em: $LOG_FILE"

# Verificar pré-requisitos
log "$GREEN" "Verificando pré-requisitos..."
command -v kubectl >/dev/null 2>&1 || { log "$RED" "kubectl não encontrado. Instale o kubectl primeiro."; exit 1; }
command -v helm >/dev/null 2>&1 || { log "$RED" "helm não encontrado. Instale o helm primeiro."; exit 1; }
command -v python3 >/dev/null 2>&1 || { log "$RED" "Python 3 não encontrado. Instale o Python 3 primeiro."; exit 1; }

# Informação sobre métricas
if [ "$COLLECT_METRICS" = true ]; then
    log "$GREEN" "Métricas serão salvas em: ${METRICS_DIR}"
else
    log "$YELLOW" "Coleta de métricas desativada"
fi

# Validar recursos
log "$GREEN" "Validando recursos do cluster..."
bash "$BASE_DIR/check-cluster.sh" >> "$LOG_FILE" 2>&1 || { log "$RED" "Falha na validação de recursos do cluster"; exit 1; }

# Criar namespaces
log "$GREEN" "Criando namespaces..."
kubectl get namespace >> "$LOG_FILE" 2>&1
sleep 5

# Aplicar quotas
log "$GREEN" "Aplicando resource quotas..."
kubectl apply -f "$BASE_DIR/manifests/namespace/resource-quotas.yaml" >> "$LOG_FILE" 2>&1
sleep 5
# Instalar monitoring stack se não estiver presente
if ! kubectl get namespace monitoring > /dev/null 2>&1; then
    log "$GREEN" "Instalando stack de observabilidade..."
    bash "$BASE_DIR/install-prom-operator.sh" >> "$LOG_FILE" 2>&1
else
    log "$GREEN" "Stack de observabilidade já instalada."
fi

# Esperar pela inicialização do Prometheus
log "$GREEN" "Aguardando inicialização do Prometheus..."
kubectl wait --for=condition=Ready -n monitoring pod -l app.kubernetes.io/name=prometheus --timeout=300s >> "$LOG_FILE" 2>&1 || {
    log "$YELLOW" "Não foi possível detectar o deployment do Prometheus. Continuando mesmo assim..."
}

# Adicionar o deployment do blackbox-exporter
log "$GREEN" "Adicionando deployment do blackbox-exporter..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blackbox-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blackbox-exporter
  template:
    metadata:
      labels:
        app: blackbox-exporter
    spec:
      containers:
      - name: blackbox-exporter
        image: prom/blackbox-exporter:latest
        ports:
        - containerPort: 9115
EOF

# Início do experimento
log "$GREEN" "======= INÍCIO DO EXPERIMENTO: ${EXPERIMENT_NAME} ======="
log "$GREEN" "Data: ${START_DATE//-//}, Hora: ${START_TIME//-/:}"
log "$GREEN" "Número de rounds: $NUM_ROUNDS"
log "$GREEN" "Duração das fases: Baseline=${BASELINE_DURATION}s, Ataque=${ATTACK_DURATION}s, Recuperação=${RECOVERY_DURATION}s"

# Registrar o início do experimento
START_TIMESTAMP=$(date +%s)
echo "Início do experimento: $(date)" > "${METRICS_DIR}/info.txt"
echo "Número de rounds: $NUM_ROUNDS" >> "${METRICS_DIR}/info.txt"
echo "Duração das fases: Baseline=$BASELINE_DURATION, Ataque=$ATTACK_DURATION, Recuperação=$RECOVERY_DURATION" >> "${METRICS_DIR}/info.txt"

# Definir nomes das fases com numeração
PHASE_1_NAME="1 - Baseline"
PHASE_2_NAME="2 - Attack"
PHASE_3_NAME="3 - Recovery"

# Executar cada round do experimento
for round in $(seq 1 $NUM_ROUNDS); do
    mkdir -p "${METRICS_DIR}/round-${round}"
    
    log "$YELLOW" "===== ROUND ${round}/${NUM_ROUNDS} ====="
    
    # FASE 1: BASELINE
    log "$BLUE" "=== Fase $PHASE_1_NAME ==="
    if [ "$COLLECT_METRICS" = true ]; then
      start_collecting_metrics "$PHASE_1_NAME" "$round"
    fi
    
    # Limpar quaisquer workloads anteriores se for o primeiro round
    if [ "$round" -eq 1 ]; then
        log "$GREEN" "Limpando workloads anteriores..."
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-a/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-b/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-c/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-d/" >> "$LOG_FILE" 2>&1 || true
        sleep 10  # Espera para garantir que tudo foi removido
    fi
    
    # Executar fase de baseline com timeout
    execute_with_timeout "$PHASE_1_NAME" "$BASELINE_DURATION" "
        log \"\$GREEN\" \"Implantando tenant-a (sensível à rede)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-a/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando inicialização dos serviços do tenant-a...\"
        kubectl -n tenant-a wait --for=condition=available --timeout=120s deployment/nginx-deployment >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Timeout aguardando pelo nginx no tenant-a\"
        
        log \"\$GREEN\" \"Implantando tenant-c (vítima)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-c/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Implantando tenant-d (CPU e Disco)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-d/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando inicialização de todos os tenants...\"
        wait_for_all_tenants_ready 120 || log \"\$YELLOW\" \"Nem todos os tenants ficaram prontos dentro do tempo esperado\"
        
        sleep \"\$BASELINE_DURATION\"
    "
    if [ "$COLLECT_METRICS" = true ]; then
      stop_collecting_metrics
    fi
    
    continue_to_next_phase "$PHASE_1_NAME" "$PHASE_2_NAME"
    
    # FASE 2: ATAQUE
    log "$BLUE" "=== Fase $PHASE_2_NAME ==="
    if [ "$COLLECT_METRICS" = true ]; then
      start_collecting_metrics "$PHASE_2_NAME" "$round"
    fi
    
    execute_with_timeout "$PHASE_2_NAME" "$ATTACK_DURATION" "
        log \"\$GREEN\" \"Implantando tenant-b (atacante noisy neighbor)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-b/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando inicialização dos serviços do tenant-b...\"
        kubectl -n tenant-b wait --for=condition=available deployment/traffic-generator --timeout=120s >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Timeout aguardando pelo traffic-generator no tenant-b\"
        kubectl -n tenant-b wait --for=condition=available deployment/traffic-server --timeout=120s >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Timeout aguardando pelo traffic-server no tenant-b\"
        kubectl -n tenant-b wait --for=condition=available deployment/stress-ng --timeout=120s >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Timeout aguardando pelo stress-ng no tenant-b\"
        kubectl -n tenant-b wait --for=condition=available deployment/iperf-server --timeout=120s >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Timeout aguardando pelo iperf-server no tenant-b\"
        
        log \"\$GREEN\" \"Verificando todos os tenants após a implantação do atacante...\"
        wait_for_all_tenants_ready 60 || log \"\$YELLOW\" \"Possível impacto do ataque - nem todos os tenants estão totalmente prontos\"
        
        sleep \"\$ATTACK_DURATION\"
    "

    if [ "$COLLECT_METRICS" = true ]; then
      stop_collecting_metrics
    fi
    
    continue_to_next_phase "$PHASE_2_NAME" "$PHASE_3_NAME"
    
    # FASE 3: RECUPERAÇÃO
    log "$BLUE" "=== Fase $PHASE_3_NAME ==="
    if [ "$COLLECT_METRICS" = true ]; then
      start_collecting_metrics "$PHASE_3_NAME" "$round"
    fi
    
    execute_with_timeout "$PHASE_3_NAME" "$RECOVERY_DURATION" "
        log \"\$GREEN\" \"Removendo tenant-b (atacante)...\"
        kubectl delete -f \"\$BASE_DIR/manifests/tenant-b/\" >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Erro ao remover tenant-b\"
        
        log \"\$GREEN\" \"Verificando recuperação do tenant-a, tenant-c e tenant-d...\"
        wait_for_all_tenants_ready 120 || log \"\$YELLOW\" \"Alguns tenants podem não ter se recuperado completamente\"
        
        sleep \"\$RECOVERY_DURATION\"
    "

    if [ "$COLLECT_METRICS" = true ]; then
      stop_collecting_metrics
    fi
    
    log "$GREEN" "Round ${round}/${NUM_ROUNDS} concluído com sucesso!"
    
    # Perguntar se deve continuar para o próximo round
    continue_prompt $((round + 1)) "$NUM_ROUNDS"
done

# Registrar o fim do experimento
END_TIMESTAMP=$(date +%s)
TOTAL_DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
echo "Fim do experimento: $(date)" >> "${METRICS_DIR}/info.txt"
echo "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)" >> "${METRICS_DIR}/info.txt"

# Limpar recursos no final
cleanup_tenants

# Instruções finais
log "$GREEN" "======= EXPERIMENTO CONCLUÍDO ======="
log "$GREEN" "Data/hora de início: ${START_DATE//-//} ${START_TIME//-/:}"
log "$GREEN" "Data/hora de término: $(date +"%Y/%m/%d %H:%M:%S")"
log "$GREEN" "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)"
log "$GREEN" "Métricas e logs salvos em: ${METRICS_DIR}"

log "$GREEN" "Para visualizar os resultados no Grafana:"
log "$GREEN" "kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80"
log "$GREEN" "Abra seu navegador em http://localhost:3000 (usuário: admin, senha: admin)"
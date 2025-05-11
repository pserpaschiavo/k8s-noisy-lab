#!/bin/bash

# Script para coletar métricas de forma sincronizada

# Cores para saídas
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Diretório base onde o script está localizado
BASE_DIR=$(dirname "$(realpath "$0")")
CURRENT_DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%H-%M-%S)

# Tenants para monitoramento
TENANTS=("tenant-a" "tenant-b" "tenant-c" "tenant-d")
PHASES=("Baseline" "Attack" "Recovery")

# Configurações
EXPERIMENT_NAME=${1:-"synchronized-metrics"}
PROMETHEUS_URL=${PROMETHEUS_URL:-"http://localhost:9090"}
OUTPUT_DIR="$BASE_DIR/results/$CURRENT_DATE/$TIMESTAMP/$EXPERIMENT_NAME"
LOG_FILE="$OUTPUT_DIR/metrics-collection.log"
ROUNDS=${ROUNDS:-1}
PHASE_DURATION=${PHASE_DURATION:-300} # 5 minutos por padrão
POLLING_INTERVAL=${POLLING_INTERVAL:-15} # 15 segundos por padrão

# Função para log
log() {
    local color=$1
    local message=$2
    echo -e "${color}$(date +"%Y-%m-%d %H:%M:%S") - $message${NC}" | tee -a "$LOG_FILE"
}

# Função para garantir que todos os diretórios necessários existam
setup_directories() {
    mkdir -p "$OUTPUT_DIR"
    touch "$LOG_FILE"
    
    # Arquivo com informações do experimento
    cat > "$OUTPUT_DIR/info.txt" << EOF
Experimento: $EXPERIMENT_NAME
Data: $CURRENT_DATE
Hora: $TIMESTAMP
Duração por fase: $PHASE_DURATION segundos
Intervalo de coleta: $POLLING_INTERVAL segundos
Rodadas: $ROUNDS
EOF
    
    log "$GREEN" "Diretórios de saída configurados em: $OUTPUT_DIR"
}

# Função para verificar se o cluster está pronto
check_cluster() {
    log "$BLUE" "Verificando estado do cluster Kubernetes..."
    
    if ! kubectl cluster-info &> /dev/null; then
        log "$RED" "Cluster Kubernetes não está disponível! Verifique a conexão."
        exit 1
    fi
    
    log "$GREEN" "Cluster Kubernetes está funcionando corretamente."
    
    # Verificar se todos os namespaces necessários existem
    for tenant in "${TENANTS[@]}"; do
        if ! kubectl get namespace "$tenant" &> /dev/null; then
            log "$RED" "Namespace $tenant não existe! Criando..."
            kubectl create namespace "$tenant"
        fi
    done
}

# Função para verificar se o prometheus está acessível
check_prometheus() {
    log "$BLUE" "Verificando acesso ao Prometheus em $PROMETHEUS_URL..."
    
    if ! curl -s "$PROMETHEUS_URL/-/healthy" | grep -q "Prometheus"; then
        log "$RED" "Prometheus não está acessível em $PROMETHEUS_URL"
        
        # Tentar fazer port-forward para o prometheus
        log "$YELLOW" "Tentando fazer port-forward para o serviço do Prometheus..."
        kubectl -n prometheus port-forward svc/prometheus-operated 9090:9090 &>/dev/null &
        PROMETHEUS_PF_PID=$!
        
        # Esperar um pouco para o port-forward estar pronto
        sleep 5
        
        if ! curl -s "http://localhost:9090/-/healthy" | grep -q "Prometheus"; then
            log "$RED" "Não foi possível acessar o Prometheus mesmo após port-forward."
            kill $PROMETHEUS_PF_PID &>/dev/null
            exit 1
        else
            PROMETHEUS_URL="http://localhost:9090"
            log "$GREEN" "Port-forward para o Prometheus configurado com sucesso."
        fi
    else
        log "$GREEN" "Prometheus está acessível."
    fi
}

# Função para verificar se os pods de um namespace estão prontos
check_pods_ready() {
    local namespace=$1
    local timeout=${2:-120}
    local start_time=$(date +%s)
    local all_ready=false
    
    while [[ $(($(date +%s) - $start_time)) -lt $timeout ]]; do
        if [[ $(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -v "Running" | grep -v "Succeeded" | wc -w) -eq 0 ]]; then
            # Verificar também se todos os deployments estão prontos
            if [[ $(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -v "True" | wc -w) -eq 0 ]]; then
                all_ready=true
                break
            fi
        fi
        sleep 2
    done
    
    if [[ "$all_ready" = true ]]; then
        return 0
    else
        return 1
    fi
}

# Função para esperar que todos os namespaces tenham seus pods prontos
wait_for_all_tenants() {
    local tenants_to_check=("$@")
    local timeout=180
    
    for tenant in "${tenants_to_check[@]}"; do
        log "$BLUE" "Verificando se pods no namespace $tenant estão prontos..."
        
        if check_pods_ready "$tenant" "$timeout"; then
            log "$GREEN" "Todos os pods no namespace $tenant estão prontos!"
        else
            log "$YELLOW" "Tempo limite excedido aguardando pods no namespace $tenant. Continuando mesmo assim..."
            # Mostrar quais pods não estão prontos
            kubectl get pods -n "$tenant" -o wide
        fi
    done
}

# Definição das métricas a serem coletadas
declare -A METRICS
setup_metrics() {
    # Métricas de CPU
    METRICS["cpu_usage"]="sum(rate(container_cpu_usage_seconds_total{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}[1m])) by (namespace)"
    METRICS["cpu_requests"]="sum(kube_pod_container_resource_requests{namespace=~\"${1}\",resource=\"cpu\"}) by (namespace)"
    METRICS["cpu_limits"]="sum(kube_pod_container_resource_limits{namespace=~\"${1}\",resource=\"cpu\"}) by (namespace)"
    METRICS["cpu_throttling"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}[1m])) by (namespace)"
    METRICS["cpu_system"]="sum(rate(container_cpu_system_seconds_total{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}[1m])) by (namespace)"
    METRICS["cpu_usage_variability"]="stddev_over_time(sum by (namespace) (rate(container_cpu_usage_seconds_total{namespace=~\"${1}\"}[1m]))[5m:])"
    
    # Métricas de memória
    METRICS["memory_usage"]="sum(container_memory_working_set_bytes{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}) by (namespace)"
    METRICS["memory_requests"]="sum(kube_pod_container_resource_requests{namespace=~\"${1}\",resource=\"memory\"}) by (namespace)"
    METRICS["memory_limits"]="sum(kube_pod_container_resource_limits{namespace=~\"${1}\",resource=\"memory\"}) by (namespace)"
    METRICS["memory_cache"]="sum(container_memory_cache{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}) by (namespace)"
    METRICS["memory_rss"]="sum(container_memory_rss{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}) by (namespace)"
    
    # Métricas de rede
    METRICS["network_receive_bytes"]="sum(rate(container_network_receive_bytes_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_transmit_bytes"]="sum(rate(container_network_transmit_bytes_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_receive_packets"]="sum(rate(container_network_receive_packets_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_transmit_packets"]="sum(rate(container_network_transmit_packets_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_receive_errors"]="sum(rate(container_network_receive_errors_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_transmit_errors"]="sum(rate(container_network_transmit_errors_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_receive_dropped"]="sum(rate(container_network_receive_packets_dropped_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    METRICS["network_transmit_dropped"]="sum(rate(container_network_transmit_packets_dropped_total{namespace=~\"${1}\"}[1m])) by (namespace)"
    
    # Métricas de disco
    METRICS["filesystem_usage"]="sum(container_fs_usage_bytes{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}) by (namespace)"
    METRICS["filesystem_reads"]="sum(rate(container_fs_reads_total{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}[1m])) by (namespace)"
    METRICS["filesystem_writes"]="sum(rate(container_fs_writes_total{namespace=~\"${1}\",container!=\"\",container!=\"POD\"}[1m])) by (namespace)"
    
    # Métricas específicas para tenant-d (PostgreSQL)
    if [[ "$1" == *"tenant-d"* ]]; then
        METRICS["postgres_connections"]="pg_stat_activity_count{datname=\"benchmark\",job=\"postgres-exporter\"}"
        METRICS["postgres_transactions"]="rate(pg_stat_database_xact_commit{datname=\"benchmark\",job=\"postgres-exporter\"}[1m]) + rate(pg_stat_database_xact_rollback{datname=\"benchmark\",job=\"postgres-exporter\"}[1m])"
        METRICS["postgres_query_time"]="pg_stat_database_blk_read_time{datname=\"benchmark\",job=\"postgres-exporter\"} + pg_stat_database_blk_write_time{datname=\"benchmark\",job=\"postgres-exporter\"}"
        METRICS["postgres_disk_io"]="rate(pg_stat_database_blk_read_bytes{datname=\"benchmark\",job=\"postgres-exporter\"}[1m]) + rate(pg_stat_database_blk_write_bytes{datname=\"benchmark\",job=\"postgres-exporter\"}[1m])"
        METRICS["disk_io_tenant_d"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m]))"
    fi
    
    # Métricas de relação entre tenants
    if [[ "$1" == *"tenant-a|tenant-b|tenant-c|tenant-d"* ]]; then
        METRICS["cpu_tenant_d_vs_other_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-d\"}[1m])) / (sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) > 0)"
        METRICS["disk_tenant_d_vs_other_ratio"]="(sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m]))) / (sum(rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) > 0)"
        METRICS["network_fairness_index"]="(sum(rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))^2) / (4 * sum(rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m])^2))"
        METRICS["resource_dominance_index"]="(sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))) * (sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}))"
        METRICS["tenant_latency_comparison"]="avg(rate(container_cpu_usage_seconds_total{namespace=\"tenant-a\"}[1m]) / rate(container_network_receive_packets_total{namespace=\"tenant-a\"}[1m])) / avg(rate(container_cpu_usage_seconds_total{namespace=\"tenant-c\"}[1m]) / rate(container_network_receive_packets_total{namespace=\"tenant-c\"}[1m]))"
        METRICS["tenant_jitter"]="stddev_over_time((rate(container_network_receive_packets_total{namespace=~\"tenant-a|tenant-c|tenant-d\"}[1m]) / rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-c|tenant-d\"}[1m]))[5m:1m])"
    fi
}

# Função para consultar uma métrica no prometheus
query_prometheus() {
    local query=$1
    local start_time=$2
    local end_time=$3
    local step=${4:-15s}
    
    local url="${PROMETHEUS_URL}/api/v1/query_range"
    local result
    
    result=$(curl -s -G "$url" \
        --data-urlencode "query=$query" \
        --data-urlencode "start=$start_time" \
        --data-urlencode "end=$end_time" \
        --data-urlencode "step=$step")
    
    # Remover timestamps duplicados - selecionando apenas o primeiro valor para cada timestamp
    echo "$result" | jq -r '
        if .data.result then
            .data.result[] | 
            (.metric | to_entries | map(.key + "=\"" + .value + "\"") | join(",")) as $labels |
            (.values | sort_by(.[0]) | unique_by(.[0]) | map([.[0], .[1]] | join(",")) | join("\n")) |
            if $labels == "" then . else $labels + "," + . end
        else
            "# Error: " + .error
        end'
}

# Função para coletar métricas para um tenant específico
collect_metrics_for_tenant() {
    local tenant=$1
    local phase=$2
    local round=$3
    local start_time=$4
    local end_time=$5
    
    local tenant_output_dir="$OUTPUT_DIR/round-$round/$phase/$tenant"
    mkdir -p "$tenant_output_dir"
    
    log "$BLUE" "Coletando métricas para $tenant na fase $phase (Round $round)..."
    
    setup_metrics "$tenant"
    
    # Iterar sobre cada métrica definida
    for metric_name in "${!METRICS[@]}"; do
        local query="${METRICS[$metric_name]}"
        local output_file="$tenant_output_dir/${metric_name}.csv"
        
        log "$CYAN" "  -> Consultando $metric_name..."
        query_prometheus "$query" "$start_time" "$end_time" "${POLLING_INTERVAL}s" > "$output_file"
        
        # Verificar se o arquivo tem conteúdo válido
        if [[ -s "$output_file" && ! $(head -1 "$output_file") == "# Error"* ]]; then
            log "$GREEN" "     Dados salvos em $output_file"
        else
            log "$YELLOW" "     Não foi possível obter dados para $metric_name"
            # Criar um arquivo de marcação para indicar que a métrica foi consultada mas não retornou dados
            echo "# Consulta realizada mas não retornou dados: $query" > "$output_file"
        fi
    done
    
    # Coletar métricas de relação entre todos os tenants
    if [[ "$tenant" == "${TENANTS[0]}" ]]; then
        local all_tenants_dir="$OUTPUT_DIR/round-$round/$phase/cluster-metrics"
        mkdir -p "$all_tenants_dir"
        
        # Configurar métricas para comparação entre todos os tenants
        setup_metrics "tenant-a|tenant-b|tenant-c|tenant-d"
        
        log "$BLUE" "Coletando métricas de relação entre tenants na fase $phase (Round $round)..."
        
        for metric_name in "cpu_tenant_d_vs_other_ratio" "disk_tenant_d_vs_other_ratio" "network_fairness_index" "resource_dominance_index" "tenant_latency_comparison" "tenant_jitter"; do
            local query="${METRICS[$metric_name]}"
            local output_file="$all_tenants_dir/${metric_name}.csv"
            
            log "$CYAN" "  -> Consultando $metric_name..."
            query_prometheus "$query" "$start_time" "$end_time" "${POLLING_INTERVAL}s" > "$output_file"
            
            if [[ -s "$output_file" && ! $(head -1 "$output_file") == "# Error"* ]]; then
                log "$GREEN" "     Dados salvos em $output_file"
            else
                log "$YELLOW" "     Não foi possível obter dados para $metric_name"
                echo "# Consulta realizada mas não retornou dados: $query" > "$output_file"
            fi
        done
    fi
}

# Função para executar uma fase do experimento
run_phase() {
    local phase=$1
    local round=$2
    local tenants_to_check=()
    
    log "$PURPLE" "===== INICIANDO FASE $phase (ROUND $round) ====="
    
    # Determinar quais tenants devem estar prontos nesta fase
    case "$phase" in
        "1 - Baseline")
            tenants_to_check=("tenant-a" "tenant-c" "tenant-d")
            ;;
        "2 - Attack")
            tenants_to_check=("tenant-a" "tenant-b" "tenant-c" "tenant-d")
            ;;
        "3 - Recovery")
            tenants_to_check=("tenant-a" "tenant-c" "tenant-d")
            ;;
        *)
            log "$RED" "Fase desconhecida: $phase"
            return 1
            ;;
    esac
    
    # Esperar que todos os pods necessários estejam prontos
    wait_for_all_tenants "${tenants_to_check[@]}"
    
    # Registrar o início da coleta
    local start_time=$(date +%s)
    local start_date=$(date -d "@$start_time" -Iseconds)
    
    log "$GREEN" "Iniciando coleta de métricas para a fase $phase às $start_date"
    
    # Aguardar a duração da fase
    log "$BLUE" "Aguardando $PHASE_DURATION segundos para coleta completa..."
    sleep "$PHASE_DURATION"
    
    # Registrar o fim da coleta
    local end_time=$(date +%s)
    local end_date=$(date -d "@$end_time" -Iseconds)
    log "$GREEN" "Finalizando coleta de métricas para a fase $phase às $end_date"
    
    # Converter para formato RFC3339
    start_date=$(date -d "@$start_time" -Iseconds)
    end_date=$(date -d "@$end_time" -Iseconds)
    
    # Coletar métricas para cada tenant relevante
    for tenant in "${tenants_to_check[@]}"; do
        collect_metrics_for_tenant "$tenant" "$phase" "$round" "$start_date" "$end_date"
    done
    
    # Coletar métricas do ingress-nginx se existir
    if kubectl get namespace ingress-nginx &>/dev/null; then
        collect_metrics_for_tenant "ingress-nginx" "$phase" "$round" "$start_date" "$end_date"
    fi
    
    log "$PURPLE" "===== FASE $phase (ROUND $round) COMPLETA ====="
}

# Função para mostrar como usar o script
show_usage() {
    echo "Uso: $0 [NOME_DO_EXPERIMENTO] [OPÇÕES]"
    echo
    echo "NOME_DO_EXPERIMENTO é o nome do diretório onde os resultados serão salvos"
    echo
    echo "Opções:"
    echo "  --rounds N         Número de rodadas do experimento (padrão: 1)"
    echo "  --duration N       Duração de cada fase em segundos (padrão: 300)"
    echo "  --interval N       Intervalo de coleta em segundos (padrão: 15)"
    echo "  --prometheus URL   URL do Prometheus (padrão: http://localhost:9090)"
    echo "  --help             Mostra esta ajuda"
    echo
    echo "Exemplo: $0 meu-experimento --rounds 3 --duration 600 --interval 10"
    exit 0
}

# Processar argumentos
process_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --rounds)
                ROUNDS="$2"
                shift 2
                ;;
            --duration)
                PHASE_DURATION="$2"
                shift 2
                ;;
            --interval)
                POLLING_INTERVAL="$2"
                shift 2
                ;;
            --prometheus)
                PROMETHEUS_URL="$2"
                shift 2
                ;;
            --help)
                show_usage
                ;;
            *)
                if [[ "$EXPERIMENT_NAME" == "synchronized-metrics" ]]; then
                    EXPERIMENT_NAME="$1"
                else
                    echo "Argumento desconhecido: $1"
                    show_usage
                fi
                shift
                ;;
        esac
    done
}

# Função principal
main() {
    process_args "$@"
    setup_directories
    check_cluster
    check_prometheus
    
    # Loop para executar o número especificado de rodadas
    for ((round=1; round<=ROUNDS; round++)); do
        log "$PURPLE" "======= INICIANDO RODADA $round/$ROUNDS ======="
        
        # Executar cada fase do experimento
        for phase in "${PHASES[@]}"; do
            run_phase "$phase" "$round"
        done
        
        log "$PURPLE" "======= RODADA $round/$ROUNDS COMPLETA ======="
    done
    
    log "$GREEN" "Experimento concluído com sucesso!"
    echo
    echo -e "${GREEN}Resultados salvos em: $OUTPUT_DIR${NC}"
    echo
    
    # Matar o processo de port-forward se estiver rodando
    if [[ -n "$PROMETHEUS_PF_PID" ]]; then
        kill $PROMETHEUS_PF_PID &>/dev/null
    fi
}

# Iniciar o script
main "$@"
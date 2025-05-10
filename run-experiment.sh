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
BASELINE_DURATION=180  # segundos (3 minutos)
ATTACK_DURATION=300    # segundos (5 minutos)
RECOVERY_DURATION=180  # segundos (3 minutos)
COLLECT_METRICS=true
CUSTOM_SCENARIO=""

# Função de ajuda
show_help() {
    echo "Uso: $0 [opções]"
    echo
    echo "Opções:"
    echo "  -h, --help                 Mostra esta ajuda"
    echo
    echo "Opções:"
    echo "  -h, --help                 Mostra esta ajuda"
    echo "  -n, --name NOME            Define o nome do experimento (padrão: noisy-neighbours)"
    echo "  -r, --rounds NUM           Define o número de rounds (padrão: 3)"
    echo "  -b, --baseline SEGUNDOS    Define a duração da fase de baseline (padrão: 180s)"
    echo "  -a, --attack SEGUNDOS      Define a duração da fase de ataque (padrão: 300s)"
    echo "  -c, --recovery SEGUNDOS    Define a duração da fase de recuperação (padrão: 180s)"
    echo "  -s, --scenario ARQUIVO     Usa um cenário personalizado de um arquivo YAML"
    echo "  --no-metrics               Desativa a coleta de métricas"
    echo
}

# Processamento de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--name)
            EXPERIMENT_NAME="$2"
            shift 2
            ;;
        -r|--rounds)
            NUM_ROUNDS="$2"
            shift 2
            ;;
        -b|--baseline)
            BASELINE_DURATION="$2"
            shift 2
            ;;
        -a|--attack)
            ATTACK_DURATION="$2"
            shift 2
            ;;
        -c|--recovery)
            RECOVERY_DURATION="$2"
            shift 2
            ;;
        -s|--scenario)
            CUSTOM_SCENARIO="$2"
            shift 2
            ;;
        --no-metrics)
            COLLECT_METRICS=false
            shift
            ;;
        *)
            echo "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validação dos parâmetros
if ! [[ "$NUM_ROUNDS" =~ ^[0-9]+$ ]] || [ "$NUM_ROUNDS" -lt 1 ]; then
    echo "Erro: Número de rounds deve ser um inteiro positivo"
    exit 1
fi

if ! [[ "$BASELINE_DURATION" =~ ^[0-9]+$ ]] || [ "$BASELINE_DURATION" -lt 30 ]; then
    echo "Erro: Duração da fase de baseline deve ser pelo menos 30 segundos"
    exit 1
fi

if ! [[ "$ATTACK_DURATION" =~ ^[0-9]+$ ]] || [ "$ATTACK_DURATION" -lt 30 ]; then
    echo "Erro: Duração da fase de ataque deve ser pelo menos 30 segundos"
    exit 1
fi

if ! [[ "$RECOVERY_DURATION" =~ ^[0-9]+$ ]] || [ "$RECOVERY_DURATION" -lt 30 ]; then
    echo "Erro: Duração da fase de recuperação deve ser pelo menos 30 segundos"
    exit 1
fi

if [ -n "$CUSTOM_SCENARIO" ] && [ ! -f "$CUSTOM_SCENARIO" ]; then
    echo "Erro: Arquivo de cenário não encontrado: $CUSTOM_SCENARIO"
    exit 1
fi

# Configuração de diretório para métricas
START_DATE=$(date +%Y-%m-%d)
START_TIME=$(date +%H-%M-%S)
METRICS_DIR="${BASE_DIR}/results/${START_DATE}/${START_TIME}/${EXPERIMENT_NAME}"

# Criar diretório para métricas e logs
mkdir -p "${METRICS_DIR}"
LOG_FILE="${METRICS_DIR}/experiment.log"

# Função de log que escreve para o console e para o arquivo de log
log() {
    local color=$1
    local message=$2
    
    # Formatar a mensagem com timestamp
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local formatted_message="[$timestamp] $message"
    
    # Escrever para o console com cor
    printf "${color}%s${NO_COLOR}\n" "$message"
    
    # Escrever para o arquivo de log sem cores
    echo "$formatted_message" >> "$LOG_FILE"
}

# Função para monitorar e proteger o tempo de cada fase
execute_with_timeout() {
    local phase=$1
    local duration=$2
    local command=$3
    
    log "$YELLOW" "Iniciando fase: $phase (duração máxima: ${duration}s)"
    
    # Executa o comando em background
    eval "$command" &
    local cmd_pid=$!
    
    # Monitora por tempo máximo
    local timeout=$((duration + 30))  # 30 segundos extras para segurança
    local count=0
    
    while kill -0 $cmd_pid 2>/dev/null; do
        sleep 1
        count=$((count+1))
        
        if [ $count -ge $timeout ]; then
            log "$RED" "⚠️ Timeout atingido para fase $phase. Forçando continuação..."
            kill -9 $cmd_pid 2>/dev/null || true
            break
        fi
    done
    
    log "$GREEN" "Fase $phase concluída"
}

# Queries PromQL para coleta de métricas - versão limpa e otimizada
declare -A PROM_QUERIES=(
    # CPU
    ["cpu_usage"]="sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (namespace)"
    ["cpu_throttled_time"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (namespace)"
    ["cpu_throttled_ratio"]="sum(rate(container_cpu_cfs_throttled_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) / sum(rate(container_cpu_cfs_periods_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (namespace)"
    
    # Memória
    ["memory_usage"]="sum(container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c\"}) by (namespace)"
    ["oom_kills"]="sum(container_oom_events_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}) by (namespace)"
    
    # Rede
    ["network_transmit"]="sum(rate(container_network_transmit_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (namespace)"
    ["network_receive"]="sum(rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (namespace)"
    ["network_dropped"]="sum(rate(container_network_receive_packets_dropped_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (namespace)"
    
    # Tempo de resposta e jitter
    ["response_time"]="histogram_quantile(0.95, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])) by (le, namespace))"
    ["jitter"]="rate(nginx_ingress_controller_request_duration_seconds_sum{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]) / rate(nginx_ingress_controller_request_duration_seconds_count{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m])"
    
    # Disk I/O
    ["disk_io"]="rate(node_disk_io_time_seconds_total[1m])"
)

# Função para coletar métricas continuamente a cada 5 segundos
collect_metrics_continuously() {
    local phase_identifier=$1 # e.g., "1-baseline"
    local round_number=$2
    
    log "$BLUE" "Iniciando coleta de métricas para fase: $phase_identifier (Round $round_number)"
    
    # Criar estrutura de diretórios para cada namespace
    for ns in "tenant-a" "tenant-b" "tenant-c"; do
        mkdir -p "${METRICS_DIR}/round-${round_number}/${phase_identifier}/${ns}"
    done
    
    # Também criar diretório para métricas sem namespace específico
    mkdir -p "${METRICS_DIR}/round-${round_number}/${phase_identifier}/cluster"

    while true; do
        local current_timestamp=$(date +%Y%m%d_%H%M%S)
        
        for query_name in "${!PROM_QUERIES[@]}"; do
            local query="${PROM_QUERIES[$query_name]}"
            
            # Execute a query do Prometheus
            curl -s --connect-timeout 5 "http://localhost:9090/api/v1/query" \
                --data-urlencode "query=$query" | \
                jq -r --arg time "$current_timestamp" '
                    # Criar um header para novo arquivo, se necessário
                    if ($time == "header") then
                        ["timestamp", "namespace", "value"] | @csv
                    else
                        .data.result[] | [
                            $time,
                            (.metric.namespace // "cluster"),
                            (.value[1] // "N/A")
                        ] | @csv
                    end
                ' | while IFS= read -r csv_line; do
                    # Pular linhas vazias
                    [ -z "$csv_line" ] && continue
                    
                    # Extrair namespace do CSV (segundo campo)
                    local ns=$(echo "$csv_line" | awk -F, '{gsub(/"/, "", $2); print $2}')
                    
                    # Determinar diretório de destino
                    local target_dir
                    if [ "$ns" = "cluster" ] || [ "$ns" = "N/A" ]; then
                        target_dir="${METRICS_DIR}/round-${round_number}/${phase_identifier}/cluster"
                    else
                        target_dir="${METRICS_DIR}/round-${round_number}/${phase_identifier}/${ns}"
                    fi
                    
                    # Verificar se o diretório existe, criar se necessário
                    mkdir -p "$target_dir"
                    
                    # Arquivo de destino para esta métrica
                    local output_file="${target_dir}/${query_name}.csv"
                    
                    # Adicionar cabeçalho se o arquivo não existir
                    if [ ! -f "$output_file" ]; then
                        echo "timestamp,value" > "$output_file"
                    fi
                    
                    # Extrair timestamp e valor (primeiro e terceiro campos)
                    local ts_val=$(echo "$csv_line" | awk -F, '{gsub(/"/, "", $1); gsub(/"/, "", $3); print $1 "," $3}')
                    echo "$ts_val" >> "$output_file"
                done
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
kubectl apply -f "$BASE_DIR/manifests/namespace/" >> "$LOG_FILE" 2>&1

# Aplicar quotas
log "$GREEN" "Aplicando resource quotas..."
kubectl apply -f "$BASE_DIR/manifests/namespace/resource-quotas.yaml" >> "$LOG_FILE" 2>&1

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
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-b/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-c/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-a/" >> "$LOG_FILE" 2>&1 || true
        sleep 10  # Espera para garantir que tudo foi removido
    fi
    
    # Executar fase de baseline com timeout
    execute_with_timeout "$PHASE_1_NAME" "$BASELINE_DURATION" "
        log \"\$GREEN\" \"Implantando tenant-a (referência)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-a/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando inicialização dos serviços do tenant-a...\"
        kubectl -n tenant-a wait --for=condition=available --timeout=120s deployment/iperf-server >> \"\$LOG_FILE\" 2>&1 || log \"\$YELLOW\" \"Timeout aguardando pelo iperf-server\"
        
        log \"\$GREEN\" \"Implantando tenant-c (vítima)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-c/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando inicialização dos workloads do tenant-c...\"
        sleep 15
        
        sleep \"\$BASELINE_DURATION\"
    "
    if [ "$COLLECT_METRICS" = true ]; then
      stop_collecting_metrics
    fi
    
    # FASE 2: ATAQUES
    log "$BLUE" "=== Fase $PHASE_2_NAME ==="
    if [ "$COLLECT_METRICS" = true ]; then
      start_collecting_metrics "$PHASE_2_NAME" "$round"
    fi
    
    # Executar fase de ataque com timeout
    execute_with_timeout "$PHASE_2_NAME" "$ATTACK_DURATION" "
        log \"\$GREEN\" \"Implantando tenant-b (noisy neighbour)...\"
        kubectl apply -f \"\$BASE_DIR/manifests/tenant-b/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando inicialização dos workloads do tenant-b...\"
        sleep 15
        
        sleep \"\$ATTACK_DURATION\"
    "
    if [ "$COLLECT_METRICS" = true ]; then
      stop_collecting_metrics
    fi
    
    # FASE 3: RECUPERAÇÃO
    log "$BLUE" "=== Fase $PHASE_3_NAME ==="
    if [ "$COLLECT_METRICS" = true ]; then
      start_collecting_metrics "$PHASE_3_NAME" "$round"
    fi
    
    # Executar fase de recuperação com timeout
    execute_with_timeout "$PHASE_3_NAME" "$RECOVERY_DURATION" "
        log \"\$GREEN\" \"Removendo tenant-b (noisy neighbour)...\"
        kubectl delete -f \"\$BASE_DIR/manifests/tenant-b/\" >> \"\$LOG_FILE\" 2>&1
        
        log \"\$GREEN\" \"Aguardando remoção completa do tenant-b...\"
        sleep 15 # Give time for resources to be deleted before metrics might disappear
        
        sleep \"\$RECOVERY_DURATION\"
    "
    if [ "$COLLECT_METRICS" = true ]; then
      stop_collecting_metrics
    fi
    
    log "$GREEN" "Round ${round}/${NUM_ROUNDS} concluído com sucesso!"
done

# Registrar o fim do experimento
END_TIMESTAMP=$(date +%s)
TOTAL_DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
echo "Fim do experimento: $(date)" >> "${METRICS_DIR}/info.txt"
echo "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)" >> "${METRICS_DIR}/info.txt"


# Limpar recursos no final (opcional, comentado por padrão)
# log "$GREEN" "Limpando recursos..."
# kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-b/" >> "$LOG_FILE" 2>&1 || true
# kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-c/" >> "$LOG_FILE" 2>&1 || true
# kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-a/" >> "$LOG_FILE" 2>&1 || true

# Instruções finais
log "$GREEN" "======= EXPERIMENTO CONCLUÍDO ======="
log "$GREEN" "Data/hora de início: ${START_DATE//-//} ${START_TIME//-/:}"
log "$GREEN" "Data/hora de término: $(date +"%Y/%m/%d %H:%M:%S")"
log "$GREEN" "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)"
log "$GREEN" "Métricas e logs salvos em: ${METRICS_DIR}"

log "$GREEN" "Para visualizar os resultados no Grafana:"
log "$GREEN" "kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80"
log "$GREEN" "Abra seu navegador em http://localhost:3000 (usuário: admin, senha: admin)"
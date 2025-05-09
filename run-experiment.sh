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

# Função para coletar métricas - modificada
collect_metrics() {
    local phase=$1
    local round=$2
    local output_dir="${METRICS_DIR}/round-${round}/${phase}"
    
    if [ "$COLLECT_METRICS" = true ]; then
        mkdir -p "$output_dir"
        log "$BLUE" "Coletando métricas para a fase: ${phase} (Round ${round})..."
        
        # Mude para o diretório do projeto antes de executar o Python
        cd "${BASE_DIR}" || { log "$RED" "Erro ao navegar para diretório base"; return 1; }
        
        # Executa o coletor de métricas com timeout e tratamento de erro
        ( timeout 60s python3 -c "
import sys
sys.path.insert(0, '${BASE_DIR}')
from prometheus_metrics import main
sys.argv = ['${BASE_DIR}/prometheus_metrics/main.py', 
            '--prometheus-url', 'http://localhost:9090',
            '--output-dir', '$output_dir',
            '--format', 'both',
            '--namespace', 'tenant-a tenant-b tenant-c',
            '--interval', '0']
main.main()
" >> "$LOG_FILE" 2>&1 ) || {
            log "$YELLOW" "⚠️ Aviso: Problema na coleta de métricas. Continuando o experimento..."
            echo "Falha na coleta de métricas: $(date)" >> "${output_dir}/failure.txt"
        }
        
        # Voltar para o diretório original
        cd "${BASE_DIR}" || true
        
        # Coleta básica em caso de falha do Python
        log "$BLUE" "Coletando informações do cluster..."
        kubectl get pods -A -o wide > "${output_dir}/pods.txt" 2>> "$LOG_FILE" || true
        kubectl top pods -A > "${output_dir}/top-pods.txt" 2>> "$LOG_FILE" || true
        kubectl top nodes > "${output_dir}/top-nodes.txt" 2>> "$LOG_FILE" || true
        
        # Captura métricas diretamente via curl 
        log "$BLUE" "Capturando métricas via API do Prometheus..."
        mkdir -p "${output_dir}/prometheus-api"
        
        # Lista de métricas principais para capturar
        metrics=(
          "container_cpu_usage_seconds_total"
          "container_memory_working_set_bytes"
          "container_network_receive_bytes_total"
          "container_network_transmit_bytes_total"
          "container_cpu_cfs_throttled_periods_total"
        )
        
        for metric in "${metrics[@]}"; do
          curl -s --connect-timeout 5 "http://localhost:9090/api/v1/query?query=${metric}{namespace=~\"tenant-a|tenant-b|tenant-c\"}" | \
            jq . > "${output_dir}/prometheus-api/${metric}.json" || true
        done
    fi
}

# Função para configurar port-forwarding do Prometheus
setup_prometheus_forward() {
    log "$BLUE" "Configurando port-forward para o Prometheus..."
    kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 > /dev/null 2>> "$LOG_FILE" &
    PROMETHEUS_PID=$!
    sleep 5  # Espera o port-forward estabelecer
    
    # Verificar se o port-forward está funcionando
    if ! curl -s http://localhost:9090/-/healthy > /dev/null; then
        log "$RED" "Falha ao conectar com o Prometheus. Verifique se o serviço está em execução."
        kill $PROMETHEUS_PID 2>/dev/null || true
        return 1
    fi
    
    log "$GREEN" "Port-forward para Prometheus configurado com sucesso"
    return 0
}

# Função para interromper port-forwarding
stop_prometheus_forward() {
    if [ -n "$PROMETHEUS_PID" ]; then
        log "$BLUE" "Interrompendo port-forward do Prometheus..."
        kill $PROMETHEUS_PID 2>/dev/null || true
        wait $PROMETHEUS_PID 2>/dev/null || true
        unset PROMETHEUS_PID
    fi
}

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
kubectl -n monitoring wait --for=condition=available --timeout=300s deployment/prometheus-kube-prometheus-prometheus >> "$LOG_FILE" 2>&1 || {
    log "$YELLOW" "Não foi possível detectar o deployment do Prometheus. Continuando mesmo assim..."
}

# Configurar port-forwarding para o Prometheus
if [ "$COLLECT_METRICS" = true ]; then
    setup_prometheus_forward || {
        log "$YELLOW" "Aviso: Não foi possível configurar o port-forward para o Prometheus. A coleta de métricas será desabilitada."
        COLLECT_METRICS=false
    }
fi

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

# Executar cada round do experimento
for round in $(seq 1 $NUM_ROUNDS); do
    mkdir -p "${METRICS_DIR}/round-${round}"
    
    log "$YELLOW" "===== ROUND ${round}/${NUM_ROUNDS} ====="
    
    # FASE 1: BASELINE
    log "$BLUE" "=== Fase 1: BASELINE ==="
    
    # Limpar quaisquer workloads anteriores se for o primeiro round
    if [ "$round" -eq 1 ]; then
        log "$GREEN" "Limpando workloads anteriores..."
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-b/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-c/" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-a/" >> "$LOG_FILE" 2>&1 || true
        sleep 10  # Espera para garantir que tudo foi removido
    fi
    
    # Implantar tenant-a (referência) e tenant-c (vítima)
    log "$GREEN" "Implantando tenant-a (referência)..."
    kubectl apply -f "$BASE_DIR/manifests/tenant-a/" >> "$LOG_FILE" 2>&1
    
    log "$GREEN" "Aguardando inicialização dos serviços do tenant-a..."
    kubectl -n tenant-a wait --for=condition=available --timeout=120s deployment/iperf-server >> "$LOG_FILE" 2>&1 || log "$YELLOW" "Timeout aguardando pelo iperf-server"
    
    log "$GREEN" "Implantando tenant-c (vítima)..."
    kubectl apply -f "$BASE_DIR/manifests/tenant-c/" >> "$LOG_FILE" 2>&1
    
    log "$GREEN" "Aguardando inicialização dos workloads do tenant-c..."
    sleep 15
    
    # Coletar métricas do baseline
    collect_metrics "baseline" "$round"
    
    # Aguardar duração da fase de baseline
    log "$YELLOW" "Aguardando fase de baseline (${BASELINE_DURATION} segundos)..."
    sleep "$BASELINE_DURATION"
    
    # FASE 2: ATAQUES
    log "$BLUE" "=== Fase 2: ATAQUES ==="
    
    # Implantar tenant-b (noisy neighbour)
    log "$GREEN" "Implantando tenant-b (noisy neighbour)..."
    kubectl apply -f "$BASE_DIR/manifests/tenant-b/" >> "$LOG_FILE" 2>&1
    
    # Aguardar inicialização do tenant-b
    log "$GREEN" "Aguardando inicialização dos workloads do tenant-b..."
    sleep 15
    
    # Coletar métricas durante o ataque
    collect_metrics "attack-start" "$round"
    
    # Aguardar duração da fase de ataque
    log "$YELLOW" "Aguardando fase de ataque (${ATTACK_DURATION} segundos)..."
    sleep "$ATTACK_DURATION"
    
    # Coletar métricas novamente após o período de ataque
    collect_metrics "attack-end" "$round"
    
    # FASE 3: RECUPERAÇÃO
    log "$BLUE" "=== Fase 3: RECUPERAÇÃO ==="
    
    # Remover tenant-b (noisy neighbour)
    log "$GREEN" "Removendo tenant-b (noisy neighbour)..."
    kubectl delete -f "$BASE_DIR/manifests/tenant-b/" >> "$LOG_FILE" 2>&1
    
    # Aguardar remoção completa do tenant-b
    log "$GREEN" "Aguardando remoção completa do tenant-b..."
    sleep 15
    
    # Coletar métricas no início da recuperação
    collect_metrics "recovery-start" "$round"
    
    # Aguardar duração da fase de recuperação
    log "$YELLOW" "Aguardando fase de recuperação (${RECOVERY_DURATION} segundos)..."
    sleep "$RECOVERY_DURATION"
    
    # Coletar métricas no final da recuperação
    collect_metrics "recovery-end" "$round"
    
    log "$GREEN" "Round ${round}/${NUM_ROUNDS} concluído com sucesso!"
done

# Coletar métricas finais do experimento
collect_metrics "final" "all"

# Registrar o fim do experimento
END_TIMESTAMP=$(date +%s)
TOTAL_DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
echo "Fim do experimento: $(date)" >> "${METRICS_DIR}/info.txt"
echo "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)" >> "${METRICS_DIR}/info.txt"

# Parar port-forwarding
stop_prometheus_forward

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
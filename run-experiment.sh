#!/bin/bash

set -eo pipefail

# Diretório base
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Importar módulos
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/kubernetes.sh"
source "$BASE_DIR/lib/metrics.sh"
source "$BASE_DIR/lib/tenant_metrics.sh"  # Módulo de métricas por tenant
source "$BASE_DIR/lib/experiment.sh"

# Configurações padrão ajustadas para melhor demonstrar o efeito "noisy neighbors"
EXPERIMENT_NAME="noisy-neighbours"
NUM_ROUNDS=3
BASELINE_DURATION=240   # segundos (4 minutos - aumentado para melhor estabilização)
ATTACK_DURATION=360     # segundos (6 minutos - aumentado para amplificar efeito do noisy neighbor)
RECOVERY_DURATION=240   # segundos (4 minutos - aumentado para visualizar recuperação completa)
COLLECT_METRICS=true
METRICS_INTERVAL=5      # segundos (intervalo entre coletas)
LIMITED_RESOURCES=false # flag para experimento com recursos limitados
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
    echo "  -i, --interval SEGUNDOS    Define o intervalo de coleta de métricas (padrão: 5s)"
    echo "  --limited-resources        Executa o experimento com configurações para recursos limitados"
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
        -i|--interval) METRICS_INTERVAL="$2"; shift 2 ;;
        --limited-resources) LIMITED_RESOURCES=true; shift ;;
        --no-metrics) COLLECT_METRICS=false; shift ;;  
        *) echo "Opção desconhecida: $1"; show_help; exit 1 ;; 
    esac
done

# Se estiver usando recursos limitados, ajustar configurações
if [ "$LIMITED_RESOURCES" = true ]; then
    log "$YELLOW" "Modo de recursos limitados ativado - ajustando parâmetros para ambiente com restrição de recursos"
    # Reduzir tempos de duração para economizar recursos
    BASELINE_DURATION=180   # 3 minutos
    ATTACK_DURATION=240     # 4 minutos
    RECOVERY_DURATION=180   # 3 minutos
    METRICS_INTERVAL=10     # Capturar métricas a cada 10 segundos para reduzir a pressão no sistema
    
    # Aplicar manifestos com recursos reduzidos se existirem
    if [ -d "$BASE_DIR/manifests/limited-resources" ]; then
        log "$YELLOW" "Aplicando manifestos adaptados para recursos limitados"
        # Aqui você pode adicionar a lógica para aplicar manifestos alternativos
    else
        log "$YELLOW" "AVISO: Não existem manifestos específicos para recursos limitados."
        log "$YELLOW" "Você deve reduzir manualmente os recursos nos manifestos dos tenants se necessário."
    fi
fi

# Exportar o intervalo de métricas para ser usado no lib/metrics.sh
export METRICS_INTERVAL
export LIMITED_RESOURCES

# Preparar diretórios e inicializar experimento
START_DATE=$(date +%Y-%m-%d)
START_TIME=$(date +%H-%M-%S)
EXPERIMENT_DIRS=$(init_experiment "$EXPERIMENT_NAME" "$BASE_DIR" "$START_DATE" "$START_TIME")
METRICS_DIR=$(echo "$EXPERIMENT_DIRS" | head -n 1)
LOG_FILE=$(echo "$EXPERIMENT_DIRS" | tail -n 1)

# Log inicial
log "$GREEN" "Iniciando experimento: $EXPERIMENT_NAME"
log "$GREEN" "Log sendo salvo em: $LOG_FILE"

# Verificar pré-requisitos
check_prerequisites || exit 1

# Informação sobre métricas
if [ "$COLLECT_METRICS" = true ]; then
    log "$GREEN" "Métricas serão salvas em: ${METRICS_DIR}"
    log "$GREEN" "Intervalo de coleta: ${METRICS_INTERVAL} segundos"
else
    log "$YELLOW" "Coleta de métricas desativada"
fi

# Validar recursos
validate_cluster_resources "$BASE_DIR" "$LOG_FILE" || exit 1

# Criar namespaces
log "$GREEN" "Criando namespaces..."
for ns in tenant-a tenant-b tenant-c tenant-d monitoring ingress-nginx; do
    ensure_namespace "$ns"
done
kubectl get namespace >> "$LOG_FILE" 2>&1
sleep 5

# Aplicar quotas
log "$GREEN" "Aplicando resource quotas..."
# Se estiver usando recursos limitados, ajustar as quotas
if [ "$LIMITED_RESOURCES" = true ] && [ -f "$BASE_DIR/manifests/namespace/limited-resource-quotas.yaml" ]; then
    kubectl apply -f "$BASE_DIR/manifests/namespace/limited-resource-quotas.yaml" >> "$LOG_FILE" 2>&1
else
    kubectl apply -f "$BASE_DIR/manifests/namespace/resource-quotas.yaml" >> "$LOG_FILE" 2>&1
fi
sleep 5

# Verificar que os novos limites de recursos são adequados
log "$GREEN" "Verificando quotas de recursos..."
kubectl get resourcequotas -A >> "$LOG_FILE" 2>&1

# Inicializar stack de monitoramento
init_monitoring_stack "$BASE_DIR" "$LOG_FILE"

# Início do experimento
log "$GREEN" "======= INÍCIO DO EXPERIMENTO: ${EXPERIMENT_NAME} ======="
log "$GREEN" "Data: ${START_DATE//-//}, Hora: ${START_TIME//-/:}"
log "$GREEN" "Número de rounds: $NUM_ROUNDS"
log "$GREEN" "Duração das fases: Baseline=${BASELINE_DURATION}s, Ataque=${ATTACK_DURATION}s, Recuperação=${RECOVERY_DURATION}s"
log "$GREEN" "Intervalo de coleta de métricas: ${METRICS_INTERVAL}s"
if [ "$LIMITED_RESOURCES" = true ]; then
    log "$YELLOW" "*** EXPERIMENTO SENDO EXECUTADO COM RECURSOS LIMITADOS ***"
fi

# Registrar o início do experimento
START_TIMESTAMP=$(date +%s)
echo "Início do experimento: $(date)" > "${METRICS_DIR}/info.txt"
echo "Número de rounds: $NUM_ROUNDS" >> "${METRICS_DIR}/info.txt"
echo "Duração das fases: Baseline=$BASELINE_DURATION, Ataque=$ATTACK_DURATION, Recuperação=$RECOVERY_DURATION" >> "${METRICS_DIR}/info.txt"
echo "Intervalo de coleta de métricas: $METRICS_INTERVAL segundos" >> "${METRICS_DIR}/info.txt"
if [ "$LIMITED_RESOURCES" = true ]; then
    echo "Executado com recursos limitados: Sim" >> "${METRICS_DIR}/info.txt"
fi

# Executar cada round do experimento
for round in $(seq 1 $NUM_ROUNDS); do
    run_experiment_round "$round" "$NUM_ROUNDS" "$BASE_DIR" "$METRICS_DIR" "$LOG_FILE" \
                        "$BASELINE_DURATION" "$ATTACK_DURATION" "$RECOVERY_DURATION" "$COLLECT_METRICS"
    
    # Perguntar se deve continuar para o próximo round
    if [ "$round" -lt "$NUM_ROUNDS" ]; then
        continue_prompt $((round + 1)) "$NUM_ROUNDS"
    fi
done

# Registrar o fim do experimento
END_TIMESTAMP=$(date +%s)
TOTAL_DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
echo "Fim do experimento: $(date)" >> "${METRICS_DIR}/info.txt"
echo "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)" >> "${METRICS_DIR}/info.txt"

# Limpar recursos no final
log "$GREEN" "Deseja limpar os recursos dos tenants? [s/N]"
read -r clean_response
if [[ "$clean_response" =~ ^[Ss]$ ]]; then
    cleanup_tenants
    log "$GREEN" "Recursos dos tenants removidos."
else
    log "$YELLOW" "Os recursos dos tenants foram mantidos para análise posterior."
fi

# Instruções finais
log "$GREEN" "======= EXPERIMENTO CONCLUÍDO ======="
log "$GREEN" "Data/hora de início: ${START_DATE//-//} ${START_TIME//-/:}"
log "$GREEN" "Data/hora de término: $(date +"%Y/%m/%d %H:%M:%S")"
log "$GREEN" "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)"
log "$GREEN" "Métricas e logs salvos em: ${METRICS_DIR}"

log "$GREEN" "Para visualizar os resultados no Grafana:"
log "$GREEN" "kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80"
log "$GREEN" "Abra seu navegador em http://localhost:3000 (usuário: admin, senha: admin)"

exit 0
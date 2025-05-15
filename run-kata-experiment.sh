#!/bin/bash

set -eo pipefail

# Diretório base
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Importar módulos
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/kubernetes.sh"
source "$BASE_DIR/lib/metrics.sh"
source "$BASE_DIR/lib/tenant_metrics.sh"
source "$BASE_DIR/lib/experiment.sh"

# Configurações padrão ajustadas para experimentos com Kata Containers
EXPERIMENT_NAME="kata-containers-isolation"
NUM_ROUNDS=3
BASELINE_DURATION=240   # segundos (4 minutos)
ATTACK_DURATION=360     # segundos (6 minutos)
RECOVERY_DURATION=240   # segundos (4 minutos)
COLLECT_METRICS=true
METRICS_INTERVAL=5      # segundos (intervalo entre coletas)
LIMITED_RESOURCES=false # flag para experimento com recursos limitados
NON_INTERACTIVE=false   # flag para executar sem interações
CUSTOM_SCENARIO=""

# Calcular duração total de um round e duração mínima para os workloads
ROUND_DURATION=$((BASELINE_DURATION + ATTACK_DURATION + RECOVERY_DURATION))
WORKLOAD_MIN_DURATION=$((ROUND_DURATION * 2))  # Pelo menos o dobro da duração total do round
export WORKLOAD_MIN_DURATION  # Exporta a variável para subprocessos

# Diretório para resultados (criado após parsing de args)
METRICS_DIR=""
LOG_FILE=""
METRICS_PID=""  # Variável para armazenar o PID da coleta de métricas em background
START_TIMESTAMP=$(date +%s)

# Função para limpeza de emergência
emergency_cleanup() {
    local exit_code=$?
    local killed_by_signal=$1
    
    echo  # Adiciona uma linha em branco após o ^C
    log "$YELLOW" "===== INTERRUPÇÃO DETECTADA ====="
    
    if [ "$killed_by_signal" = "true" ]; then
        log "$YELLOW" "Experimento interrompido pelo usuário (CTRL+C)"
    else
        log "$RED" "Experimento terminado com erro (código: $exit_code)"
    fi
    
    # Registrar o fim prematuro do experimento
    END_TIMESTAMP=$(date +%s)
    TOTAL_DURATION=$((END_TIMESTAMP - START_TIMESTAMP))
    echo "Fim prematuro do experimento: $(date)" >> "${METRICS_DIR}/info.txt"
    echo "Duração até a interrupção: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)" >> "${METRICS_DIR}/info.txt"
    echo "Interrompido pelo usuário: $killed_by_signal" >> "${METRICS_DIR}/info.txt"
    
    log "$YELLOW" "Realizando limpeza de recursos..."
    
    # Interromper coleta de métricas em background, se estiver ativa
    if [ -n "$METRICS_PID" ] && kill -0 $METRICS_PID 2>/dev/null; then
        log "$YELLOW" "Interrompendo processo de coleta de métricas (PID: $METRICS_PID)"
        kill $METRICS_PID 2>/dev/null || true
    fi
    
    # Interromper port-forwards em execução
    log "$YELLOW" "Interrompendo port-forwards em execução..."
    pkill -f "kubectl.*port-forward" || true
    
    # Remover recursos do tenant-b (atacante)
    log "$YELLOW" "Removendo recursos do tenant-b (atacante)..."
    kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests-kata/tenant-b" >> "$LOG_FILE" 2>&1 || true
    
    # Perguntar se deseja limpar todos os recursos dos tenants
    if [ "$NON_INTERACTIVE" = true ]; then
        log "$YELLOW" "Modo não interativo: limpando automaticamente todos os recursos dos tenants..."
        cleanup_kata_tenants
        log "$GREEN" "Recursos dos tenants removidos."
    else
        log "$YELLOW" "Deseja limpar todos os recursos dos tenants? [s/N]"
        read -t 10 -r clean_response || clean_response="n"  # Timeout de 10 segundos, padrão é não limpar
        if [[ "$clean_response" =~ ^[Ss]$ ]]; then
            cleanup_kata_tenants
            log "$GREEN" "Recursos dos tenants removidos."
        else
            log "$YELLOW" "Os recursos dos tenants foram mantidos para análise posterior."
        fi
    fi
    
    log "$YELLOW" "Limpeza de emergência concluída."
    log "$YELLOW" "Métricas e logs parciais salvos em: ${METRICS_DIR}"
    log "$YELLOW" "===== FIM DO EXPERIMENTO (INTERROMPIDO) ====="
    
    # Certifica-se de que o script termine
    exit $exit_code
}

# Configurar trap para capturar CTRL+C e outras interrupções
setup_signal_handlers() {
    # SIGINT (CTRL+C)
    trap 'emergency_cleanup true' INT
    # SIGTERM
    trap 'emergency_cleanup true' TERM
    # Erros não tratados
    trap 'emergency_cleanup false' ERR
}

# Função para limpar recursos dos tenants (usando manifests-kata)
cleanup_kata_tenants() {
    log "$YELLOW" "Removendo recursos dos tenants (kata)..."
    kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests-kata/tenant-a" -f "$BASE_DIR/manifests-kata/tenant-b" -f "$BASE_DIR/manifests-kata/tenant-c" -f "$BASE_DIR/manifests-kata/tenant-d" >> "$LOG_FILE" 2>&1 || true
}

# Função para verificar os pré-requisitos
check_prerequisites() {
    log "$GREEN" "Verificando pré-requisitos..."
    
    # Verificar cluster
    log "$GREEN" "Verificando conectividade com o cluster Kubernetes..."
    if ! kubectl get nodes &>/dev/null; then
        log "$RED" "ERRO: Não foi possível conectar ao cluster Kubernetes."
        log "$RED" "Verifique se o cluster está em execução e acessível."
        return 1
    fi
    log "$GREEN" "Cluster Kubernetes está acessível."
    
    # Verificar RuntimeClass kata
    log "$GREEN" "Verificando RuntimeClass kata..."
    if ! kubectl get runtimeclass kata &>/dev/null; then
        log "$RED" "ERRO: RuntimeClass 'kata' não encontrada."
        log "$RED" "Execute o script setup-kata-containers.sh primeiro."
        return 1
    fi
    log "$GREEN" "RuntimeClass 'kata' está configurada."
    
    # Verificar namespace de métricas
    log "$GREEN" "Verificando se o namespace de monitoramento existe..."
    if ! kubectl get namespace monitoring &>/dev/null; then
        log "$YELLOW" "AVISO: namespace 'monitoring' não encontrado."
        log "$YELLOW" "A coleta de métricas pode não funcionar corretamente."
        log "$YELLOW" "Considere executar install-prom-operator.sh primeiro."
    else
        log "$GREEN" "Namespace 'monitoring' encontrado."
    fi
    
    # Verificar diretório manifests-kata
    log "$GREEN" "Verificando diretório de manifestos Kata Containers..."
    if [ ! -d "$BASE_DIR/manifests-kata" ]; then
        log "$RED" "ERRO: Diretório manifests-kata não encontrado."
        log "$RED" "Execute o script para criar os manifestos kata primeiro."
        return 1
    fi
    
    # Verificar e ajustar duração dos workloads nos manifestos
    adjust_kata_manifest_durations "$ATTACK_DURATION" "$WORKLOAD_MIN_DURATION"
    
    log "$GREEN" "Todos os pré-requisitos verificados."
    return 0
}

# Função para ajustar duração nos manifestos kata
adjust_kata_manifest_durations() {
    local attack_duration=$1
    local workload_duration=$2
    
    log "$GREEN" "Ajustando duração dos workloads nos manifestos Kata..."
    
    # Ajustar tenant-d (pgbench workloads)
    if [ -f "$BASE_DIR/manifests-kata/tenant-d/cpu-disk-workload.yaml" ]; then
        # Modificar as variáveis de ambiente WORKLOAD_DURATION para todos os jobs contínuos
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests-kata/tenant-d/cpu-disk-workload.yaml" | \
        sed "s/name: WORKLOAD_DURATION.*value: \"[0-9]*\"/name: WORKLOAD_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/name: CPU_WORKLOAD_DURATION.*value: \"[0-9]*\"/name: CPU_WORKLOAD_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/name: DISK_WORKLOAD_DURATION.*value: \"[0-9]*\"/name: DISK_WORKLOAD_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/value: \"\${BASELINE_DURATION}\"/value: \"$WORKLOAD_MIN_DURATION\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests-kata/tenant-d/cpu-disk-workload.yaml"
        rm "$temp_file"
        log "$GREEN" "  - Ajustada duração dos workloads contínuos do tenant-d para ${WORKLOAD_MIN_DURATION}s"
    fi
    
    # Ajustar tenant-b (stress-ng)
    if [ -f "$BASE_DIR/manifests-kata/tenant-b/stress-ng.yml" ]; then
        # O tenant-b só deve durar durante a fase de ataque, não o round inteiro
        # Entretanto, podemos aumentá-lo um pouco para garantir que não termina cedo demais
        local extended_attack_duration=$((attack_duration + 60))  # Adiciona 1 minuto extra
        
        # Modificar a variável de ambiente ATTACK_DURATION
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests-kata/tenant-b/stress-ng.yml" | \
        sed "s/name: ATTACK_DURATION.*value: \"[0-9]*\"/name: ATTACK_DURATION\n          value: \"$extended_attack_duration\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests-kata/tenant-b/stress-ng.yml"
        rm "$temp_file"
        log "$GREEN" "  - Ajustado timeout do stress-ng para ${extended_attack_duration}s"
    fi
    
    log "$GREEN" "Manifestos kata ajustados com sucesso!"
}

# Função para inicializar namespaces se não existirem
init_kata_namespaces() {
    log "$GREEN" "Inicializando namespaces para tenants com Kata Containers..."
    
    # Aplicar namespaces e cotas de recursos
    kubectl apply -f "$BASE_DIR/manifests-kata/namespace/" >> "$LOG_FILE" 2>&1
    log "$GREEN" "Namespaces para Kata Containers configurados."
}

# Função para implantar workloads
deploy_kata_workloads() {
    log "$GREEN" "Implantando workloads com Kata Containers..."
    
    # Primeiro inicializar namespaces
    init_kata_namespaces
    
    # Depois aplicar manifestos por tenant
    log "$GREEN" "Aplicando manifestos para tenant-a (workloads sensíveis à rede)..."
    kubectl apply -f "$BASE_DIR/manifests-kata/tenant-a/" >> "$LOG_FILE" 2>&1
    
    log "$GREEN" "Aplicando manifestos para tenant-c (workloads sensíveis à memória)..."
    kubectl apply -f "$BASE_DIR/manifests-kata/tenant-c/" >> "$LOG_FILE" 2>&1
    
    log "$GREEN" "Aplicando manifestos para tenant-d (workloads sensíveis a CPU/Disco)..."
    kubectl apply -f "$BASE_DIR/manifests-kata/tenant-d/" >> "$LOG_FILE" 2>&1
    
    # Não aplicamos o tenant-b (atacante) aqui, ele será aplicado na fase de ataque
    
    # Esperar todos os pods estarem prontos
    local timeout=300  # 5 minutos
    log "$GREEN" "Aguardando pods ficarem prontos (timeout: ${timeout}s)..."
    wait_for_pods_ready "tenant-a" "$timeout"
    wait_for_pods_ready "tenant-c" "$timeout"
    wait_for_pods_ready "tenant-d" "$timeout"
    
    log "$GREEN" "Todos os workloads com Kata Containers implantados e prontos."
}

# Fase de linha de base: normal sem ataque
run_kata_baseline_phase() {
    local round_dir="$1"
    local duration="$2"
    local collect_metrics="$3"
    local metrics_file="${round_dir}/baseline-metrics.json"
    
    log "$GREEN" "FASE 1: LINHA DE BASE - Operação normal (${duration}s)"
    log "$GREEN" "Esta fase mede o desempenho normal dos workloads sem vizinhos barulhentos"
    
    # Se coletar métricas estiver habilitado
    if [ "$collect_metrics" = true ]; then
        log "$GREEN" "Iniciando coleta de métricas para linha de base..."
        collect_metrics "$metrics_file" "$duration" &
        METRICS_PID=$!
    fi
    
    # Gerar carga de teste em cada tenant
    log "$GREEN" "Gerando carga de teste para workloads em execução..."
    
    # Rodar alguns comandos para criar alguma carga nos serviços
    local tenant_a_curl_cmd="kubectl run -n tenant-a curl-client-baseline --rm --restart=Never -i --tty --image=curlimages/curl -- /bin/sh -c 'for i in {1..100}; do curl -s http://nginx-deployment.tenant-a.svc.cluster.local; sleep 1; done'"
    local tenant_c_redis_cmd="kubectl exec -n tenant-c \$(kubectl get pod -n tenant-c -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-benchmark -q -n 10000 -c 50 -P 16 -t set,get,lpush,lpop"
    local tenant_d_pgsql_cmd="kubectl exec -n tenant-d \$(kubectl get pod -n tenant-d -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pgbench -U postgres -c 10 -T 60 -n benchmark"
    
    # Executar em paralelo
    eval "$tenant_a_curl_cmd &> /dev/null &"
    eval "$tenant_c_redis_cmd &> /dev/null &"
    eval "$tenant_d_pgsql_cmd &> /dev/null &"
    
    # Aguardar o tempo da fase
    sleep "$duration"
    
    # Aguardar Jobs de coleta de métricas terminarem
    if [ -n "$METRICS_PID" ] && kill -0 $METRICS_PID 2>/dev/null; then
        log "$GREEN" "Aguardando processo de coleta de métricas terminar..."
        wait $METRICS_PID 2>/dev/null || true
        METRICS_PID=""
    fi
    
    log "$GREEN" "Fase de linha de base concluída."
}

# Fase de ataque: noisy neighbors
run_kata_attack_phase() {
    local round_dir="$1"
    local duration="$2"
    local collect_metrics="$3"
    local metrics_file="${round_dir}/attack-metrics.json"
    
    log "$GREEN" "FASE 2: ATAQUE - Implantando vizinhos barulhentos (${duration}s)"
    log "$GREEN" "Esta fase mede o impacto dos vizinhos barulhentos nos workloads"
    
    # Implantar workloads do tenant-b (atacante)
    log "$YELLOW" "Implantando workloads 'noisy neighbors' do tenant-b..."
    kubectl apply -f "$BASE_DIR/manifests-kata/tenant-b/" >> "$LOG_FILE" 2>&1
    
    # Esperar pods do atacante estarem prontos
    local timeout=120  # 2 minutos
    wait_for_pods_ready "tenant-b" "$timeout"
    log "$YELLOW" "Workloads atacantes estão prontos e gerando contenção de recursos."
    
    # Se coletar métricas estiver habilitado
    if [ "$collect_metrics" = true ]; then
        log "$GREEN" "Iniciando coleta de métricas durante ataque..."
        collect_metrics "$metrics_file" "$duration" &
        METRICS_PID=$!
    fi
    
    # Gerar carga de teste em cada tenant durante o ataque
    log "$GREEN" "Gerando carga de teste para workloads sob ataque..."
    
    # Rodar alguns comandos para criar alguma carga nos serviços
    local tenant_a_curl_cmd="kubectl run -n tenant-a curl-client-attack --rm --restart=Never -i --tty --image=curlimages/curl -- /bin/sh -c 'for i in {1..200}; do curl -s http://nginx-deployment.tenant-a.svc.cluster.local; sleep 0.5; done'"
    local tenant_c_redis_cmd="kubectl exec -n tenant-c \$(kubectl get pod -n tenant-c -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-benchmark -q -n 20000 -c 50 -P 16 -t set,get,lpush,lpop"
    local tenant_d_pgsql_cmd="kubectl exec -n tenant-d \$(kubectl get pod -n tenant-d -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pgbench -U postgres -c 10 -T 60 -n benchmark"
    
    # Executar em paralelo
    eval "$tenant_a_curl_cmd &> /dev/null &"
    eval "$tenant_c_redis_cmd &> /dev/null &"
    eval "$tenant_d_pgsql_cmd &> /dev/null &"
    
    # Aguardar o tempo da fase
    sleep "$duration"
    
    # Aguardar Jobs de coleta de métricas terminarem
    if [ -n "$METRICS_PID" ] && kill -0 $METRICS_PID 2>/dev/null; then
        log "$GREEN" "Aguardando processo de coleta de métricas terminar..."
        wait $METRICS_PID 2>/dev/null || true
        METRICS_PID=""
    fi
    
    log "$GREEN" "Fase de ataque concluída."
}

# Fase de recuperação: remoção dos noisy neighbors
run_kata_recovery_phase() {
    local round_dir="$1"
    local duration="$2"
    local collect_metrics="$3"
    local metrics_file="${round_dir}/recovery-metrics.json"
    
    log "$GREEN" "FASE 3: RECUPERAÇÃO - Removendo vizinhos barulhentos (${duration}s)"
    log "$GREEN" "Esta fase mede quanto tempo os workloads levam para se recuperar após a remoção dos vizinhos barulhentos"
    
    # Remover workloads do tenant-b (atacante)
    log "$YELLOW" "Removendo workloads 'noisy neighbors' do tenant-b..."
    kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests-kata/tenant-b/" >> "$LOG_FILE" 2>&1
    
    # Esperar até que todos os pods do tenant-b sejam removidos
    local timeout=120  # 2 minutos
    log "$YELLOW" "Aguardando remoção completa dos workloads atacantes..."
    wait_for_pods_gone "tenant-b" "$timeout"
    
    # Se coletar métricas estiver habilitado
    if [ "$collect_metrics" = true ]; then
        log "$GREEN" "Iniciando coleta de métricas para fase de recuperação..."
        collect_metrics "$metrics_file" "$duration" &
        METRICS_PID=$!
    fi
    
    # Gerar carga de teste em cada tenant durante recuperação
    log "$GREEN" "Gerando carga de teste para workloads durante recuperação..."
    
    # Rodar alguns comandos para criar alguma carga nos serviços
    local tenant_a_curl_cmd="kubectl run -n tenant-a curl-client-recovery --rm --restart=Never -i --tty --image=curlimages/curl -- /bin/sh -c 'for i in {1..100}; do curl -s http://nginx-deployment.tenant-a.svc.cluster.local; sleep 1; done'"
    local tenant_c_redis_cmd="kubectl exec -n tenant-c \$(kubectl get pod -n tenant-c -l app=redis -o jsonpath='{.items[0].metadata.name}') -- redis-benchmark -q -n 10000 -c 50 -P 16 -t set,get,lpush,lpop"
    local tenant_d_pgsql_cmd="kubectl exec -n tenant-d \$(kubectl get pod -n tenant-d -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pgbench -U postgres -c 10 -T 60 -n benchmark"
    
    # Executar em paralelo
    eval "$tenant_a_curl_cmd &> /dev/null &"
    eval "$tenant_c_redis_cmd &> /dev/null &"
    eval "$tenant_d_pgsql_cmd &> /dev/null &"
    
    # Aguardar o tempo da fase
    sleep "$duration"
    
    # Aguardar Jobs de coleta de métricas terminarem
    if [ -n "$METRICS_PID" ] && kill -0 $METRICS_PID 2>/dev/null; then
        log "$GREEN" "Aguardando processo de coleta de métricas terminar..."
        wait $METRICS_PID 2>/dev/null || true
        METRICS_PID=""
    fi
    
    log "$GREEN" "Fase de recuperação concluída."
}

# Executar um round completo do experimento
run_kata_experiment_round() {
    local round="$1"
    local total_rounds="$2"
    local base_dir="$3"
    local metrics_dir="$4"
    local log_file="$5"
    local baseline_duration="$6"
    local attack_duration="$7"
    local recovery_duration="$8"
    local collect_metrics="$9"
    
    # Criar diretório para o round
    local round_dir="${metrics_dir}/round-${round}"
    mkdir -p "${round_dir}"
    
    # Criar subdiretórios para cada fase
    local baseline_dir="${round_dir}/1 - Baseline"
    local attack_dir="${round_dir}/2 - Attack"
    local recovery_dir="${round_dir}/3 - Recovery"
    mkdir -p "$baseline_dir" "$attack_dir" "$recovery_dir"
    
    log "$BLUE" "=============================="
    log "$BLUE" "INICIANDO ROUND $round/$total_rounds"
    log "$BLUE" "=============================="
    
    # Executar as três fases
    run_kata_baseline_phase "$baseline_dir" "$baseline_duration" "$collect_metrics"
    run_kata_attack_phase "$attack_dir" "$attack_duration" "$collect_metrics"
    run_kata_recovery_phase "$recovery_dir" "$recovery_duration" "$collect_metrics"
    
    log "$BLUE" "=============================="
    log "$BLUE" "FIM DO ROUND $round/$total_rounds"
    log "$BLUE" "=============================="
}

# Função para mostrar ajuda
show_help() {
    echo "Uso: $0 [opções]"
    echo
    echo "Este script executa um experimento de isolamento com Kata Containers."
    echo
    echo "Opções:"
    echo "  -h, --help                    Mostra esta ajuda"
    echo "  -n, --name NOME               Nome do experimento (default: $EXPERIMENT_NAME)"
    echo "  -r, --rounds NUM              Número de rounds a executar (default: $NUM_ROUNDS)"
    echo "  --baseline-duration SEGUNDOS  Duração da fase de linha de base em segundos (default: $BASELINE_DURATION)"
    echo "  --attack-duration SEGUNDOS    Duração da fase de ataque em segundos (default: $ATTACK_DURATION)"
    echo "  --recovery-duration SEGUNDOS  Duração da fase de recuperação em segundos (default: $RECOVERY_DURATION)"
    echo "  --no-metrics                  Desativa coleta de métricas"
    echo "  --metrics-interval SEGUNDOS   Intervalo em segundos para coleta de métricas (default: $METRICS_INTERVAL)"
    echo "  --limited-resources           Modo para ambientes com recursos limitados"
    echo "  --non-interactive             Executa o experimento sem interações (útil para CI/CD)"
    echo
    echo "Exemplos:"
    echo "  $0 --name meu-experimento-kata --rounds 2"
    echo "  $0 --attack-duration 600 --no-metrics"
    echo "  $0 --limited-resources --non-interactive"
}

# Processar argumentos da linha de comando
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -n|--name) EXPERIMENT_NAME="$2"; shift 2 ;;
        -r|--rounds) NUM_ROUNDS="$2"; shift 2 ;;
        --baseline-duration) BASELINE_DURATION="$2"; shift 2 ;;
        --attack-duration) ATTACK_DURATION="$2"; shift 2 ;;
        --recovery-duration) RECOVERY_DURATION="$2"; shift 2 ;;
        --no-metrics) COLLECT_METRICS=false; shift ;;
        --metrics-interval) METRICS_INTERVAL="$2"; shift 2 ;;
        --limited-resources) LIMITED_RESOURCES=true; shift ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
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

# Configurar handlers de sinal
setup_signal_handlers

# Log inicial
log "$GREEN" "Iniciando experimento com Kata Containers: $EXPERIMENT_NAME"
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

# Armazenar informações do experimento
echo "Experimento: $EXPERIMENT_NAME" > "${METRICS_DIR}/info.txt"
echo "Data/hora de início: $(date)" >> "${METRICS_DIR}/info.txt"
echo "Número de rounds: $NUM_ROUNDS" >> "${METRICS_DIR}/info.txt"
echo "Duração da fase de linha de base: ${BASELINE_DURATION}s" >> "${METRICS_DIR}/info.txt"
echo "Duração da fase de ataque: ${ATTACK_DURATION}s" >> "${METRICS_DIR}/info.txt"
echo "Duração da fase de recuperação: ${RECOVERY_DURATION}s" >> "${METRICS_DIR}/info.txt"
echo "Coleta de métricas: $COLLECT_METRICS" >> "${METRICS_DIR}/info.txt"
echo "Intervalo de métricas: ${METRICS_INTERVAL}s" >> "${METRICS_DIR}/info.txt"
if [ "$LIMITED_RESOURCES" = true ]; then
    echo "Executado com recursos limitados: Sim" >> "${METRICS_DIR}/info.txt"
fi

# Implantar workloads com Kata Containers
deploy_kata_workloads

# Executar cada round do experimento
for round in $(seq 1 $NUM_ROUNDS); do
    run_kata_experiment_round "$round" "$NUM_ROUNDS" "$BASE_DIR" "$METRICS_DIR" "$LOG_FILE" \
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

# Gerar relatório comparativo se o script existir
if [ -f "$BASE_DIR/compare-isolations.sh" ]; then
    log "$GREEN" "Gerando relatório comparativo entre contêineres padrão e Kata Containers..."
    "$BASE_DIR/compare-isolations.sh" --kata-only --no-cleanup
fi

# Limpar recursos no final
if [ "$NON_INTERACTIVE" = true ]; then
    log "$GREEN" "Modo não interativo: limpando automaticamente os recursos dos tenants..."
    cleanup_kata_tenants
    log "$GREEN" "Recursos dos tenants removidos."
else
    log "$GREEN" "Deseja limpar os recursos dos tenants? [s/N]"
    read -r clean_response
    if [[ "$clean_response" =~ ^[Ss]$ ]]; then
        cleanup_kata_tenants
        log "$GREEN" "Recursos dos tenants removidos."
    else
        log "$YELLOW" "Os recursos dos tenants foram mantidos para análise posterior."
    fi
fi

# Instruções finais
log "$GREEN" "======= EXPERIMENTO COM KATA CONTAINERS CONCLUÍDO ======="
log "$GREEN" "Data/hora de início: ${START_DATE//-//} ${START_TIME//-/:}"
log "$GREEN" "Data/hora de término: $(date +"%Y/%m/%d %H:%M:%S")"
log "$GREEN" "Duração total: $TOTAL_DURATION segundos ($(($TOTAL_DURATION / 60)) minutos)"
log "$GREEN" "Métricas e logs salvos em: ${METRICS_DIR}"

log "$GREEN" "Para visualizar os resultados no Grafana:"
log "$GREEN" "kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80"
log "$GREEN" "Abra seu navegador em http://localhost:3000 (usuário: admin, senha: admin)"
log "$GREEN" "Acesse o dashboard KataContainersDashboard para ver métricas específicas do Kata Containers"

exit 0

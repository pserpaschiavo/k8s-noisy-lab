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
NON_INTERACTIVE=false   # flag para executar sem interações (sem prompts de confirmação)
CUSTOM_SCENARIO=""

# Calcular duração total de um round e duração mínima para os workloads
ROUND_DURATION=$((BASELINE_DURATION + ATTACK_DURATION + RECOVERY_DURATION))
WORKLOAD_MIN_DURATION=$((ROUND_DURATION * 2))  # Pelo menos o dobro da duração total do round
export WORKLOAD_MIN_DURATION  # Exporta a variável para subprocessos

# Diretório para resultados (criado após parsing de args)
METRICS_DIR=""
LOG_FILE=""
METRICS_PID=""  # Variável para armazenar o PID da coleta de métricas em background

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
    kubectl delete --ignore-not-found=true -f "$BASE_DIR/manifests/tenant-b" >> "$LOG_FILE" 2>&1 || true
    
    # Perguntar se deseja limpar todos os recursos dos tenants
    if [ "$NON_INTERACTIVE" = true ]; then
        log "$YELLOW" "Modo não interativo: limpando automaticamente todos os recursos dos tenants..."
        cleanup_tenants
        log "$GREEN" "Recursos dos tenants removidos."
    else
        log "$YELLOW" "Deseja limpar todos os recursos dos tenants? [s/N]"
        read -t 10 -r clean_response || clean_response="n"  # Timeout de 10 segundos, padrão é não limpar
        if [[ "$clean_response" =~ ^[Ss]$ ]]; then
            cleanup_tenants
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
    
    # SIGTERM (kill)
    trap 'emergency_cleanup true' TERM
    
    # SIGHUP (terminal fechado)
    trap 'emergency_cleanup true' HUP
    
    # EXIT (qualquer saída do script, mas só será executado se os outros traps não forem)
    trap 'emergency_cleanup false' EXIT
    
    log "$GREEN" "Handlers de sinal configurados. Use CTRL+C para interromper o experimento com limpeza segura."
}

# Função para ajustar durações em manifestos
adjust_manifests_duration() {
    local baseline_duration=$1
    local attack_duration=$2
    local recovery_duration=$3
    local round_duration=$((baseline_duration + attack_duration + recovery_duration))
    
    # Calcular a duração total considerando todos os rounds
    # Multiplica pelo número de rounds e adiciona alguma margem de segurança (30%)
    local total_experiment_duration=$((round_duration * NUM_ROUNDS))
    local min_workload_duration=$((total_experiment_duration * 130 / 100))
    
    log "$GREEN" "Ajustando durações nos manifestos de acordo com as durações das fases..."
    log "$GREEN" "Duração total do experimento (estimada): ${total_experiment_duration}s para $NUM_ROUNDS rounds"
    log "$GREEN" "Duração mínima dos workloads: ${min_workload_duration}s (inclui margem de segurança de 30%)"
    
    # Ajustar tenant-a (nginx benchmark)
    if [ -f "$BASE_DIR/manifests/tenant-a/nginx-deploy.yaml" ]; then
        # Criar uma versão temporária com durações ajustadas
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests/tenant-a/nginx-deploy.yaml" | \
        sed "s/name: BASELINE_DURATION.*value: \"[0-9]*\"/name: BASELINE_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests/tenant-a/nginx-deploy.yaml"
        rm "$temp_file"
        log "$GREEN" "  - Ajustada duração do nginx-benchmark para ${WORKLOAD_MIN_DURATION}s"
    fi
    
    # Ajustar tenant-c (continuous-memory-stress)
    if [ -f "$BASE_DIR/manifests/tenant-c/memory-workload.yaml" ]; then
        # Modificar a variável de ambiente PHASE_DURATION
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests/tenant-c/memory-workload.yaml" | \
        sed "s/name: PHASE_DURATION.*value: \"[0-9]*\"/name: PHASE_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests/tenant-c/memory-workload.yaml"
        rm "$temp_file"
        log "$GREEN" "  - Ajustada duração do continuous-memory-stress para ${WORKLOAD_MIN_DURATION}s"
    fi
    
    # Ajustar tenant-d (pgbench workloads)
    if [ -f "$BASE_DIR/manifests/tenant-d/cpu-disk-workload.yaml" ]; then
        # Modificar as variáveis de ambiente WORKLOAD_DURATION para todos os jobs contínuos
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests/tenant-d/cpu-disk-workload.yaml" | \
        sed "s/name: WORKLOAD_DURATION.*value: \"[0-9]*\"/name: WORKLOAD_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/name: CPU_WORKLOAD_DURATION.*value: \"[0-9]*\"/name: CPU_WORKLOAD_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/name: DISK_WORKLOAD_DURATION.*value: \"[0-9]*\"/name: DISK_WORKLOAD_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/value: \"\${BASELINE_DURATION}\"/value: \"$WORKLOAD_MIN_DURATION\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests/tenant-d/cpu-disk-workload.yaml"
        rm "$temp_file"
        log "$GREEN" "  - Ajustada duração dos workloads contínuos do tenant-d para ${WORKLOAD_MIN_DURATION}s"
    fi
    
    # Ajustar tenant-b (stress-ng)
    if [ -f "$BASE_DIR/manifests/tenant-b/stress-ng.yml" ]; then
        # O tenant-b só deve durar durante a fase de ataque, não o round inteiro
        # Entretanto, podemos aumentá-lo um pouco para garantir que não termina cedo demais
        local extended_attack_duration=$((attack_duration + 60))  # Adiciona 1 minuto extra
        
        # Modificar a variável de ambiente ATTACK_DURATION
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests/tenant-b/stress-ng.yml" | \
        sed "s/name: ATTACK_DURATION.*value: \"[0-9]*\"/name: ATTACK_DURATION\n          value: \"$extended_attack_duration\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests/tenant-b/stress-ng.yml"
        rm "$temp_file"
        log "$GREEN" "  - Ajustado timeout do stress-ng para ${extended_attack_duration}s"
    fi
    
    log "$GREEN" "Manifestos ajustados com sucesso!"
    
    # Verificar e ajustar qualquer outra variável de ambiente relacionada à duração no tenant-a
    if [ -f "$BASE_DIR/manifests/tenant-a/nginx-deploy.yaml" ]; then
        local temp_file=$(mktemp)
        cat "$BASE_DIR/manifests/tenant-a/nginx-deploy.yaml" | \
        sed "s/name: DURATION.*value: \"[0-9]*\"/name: DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" | \
        sed "s/name: BENCHMARK_DURATION.*value: \"[0-9]*\"/name: BENCHMARK_DURATION\n          value: \"$WORKLOAD_MIN_DURATION\"/" > "$temp_file"
        cp "$temp_file" "$BASE_DIR/manifests/tenant-a/nginx-deploy.yaml"
        rm "$temp_file"
        log "$GREEN" "  - Verificadas configurações adicionais de duração no tenant-a"
    fi
}

# Função para verificar e garantir que o Prometheus esteja funcionando
ensure_prometheus_works() {
    log "$GREEN" "Verificando o estado do Prometheus..."
    
    # Verificar se o namespace de monitoramento existe
    if ! kubectl get namespace monitoring > /dev/null 2>&1; then
        log "$YELLOW" "Namespace 'monitoring' não encontrado. Instalando o Prometheus Operator..."
        bash "$BASE_DIR/install-prom-operator.sh"
        sleep 10
    fi
    
    # Verificar se os pods do Prometheus estão em execução
    log "$GREEN" "Verificando pods do Prometheus..."
    kubectl get pods -n monitoring -l app=prometheus
    kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
    
    # Encontrar o serviço do Prometheus
    log "$GREEN" "Verificando serviços do Prometheus..."
    kubectl get services -n monitoring | grep -i prom
    
    local found_service=0
    for svc in "prometheus-operated" "prometheus-k8s" "prometheus" "prometheus-server"; do
        if kubectl get svc -n monitoring $svc > /dev/null 2>&1; then
            log "$GREEN" "Encontrado serviço do Prometheus: $svc"
            
            # Interromper qualquer port-forward existente
            pkill -f "kubectl.*port-forward.*9090:9090" || true
            sleep 2
            
            # Iniciar port-forward em segundo plano
            log "$GREEN" "Configurando port-forward para o Prometheus..."
            kubectl port-forward --namespace monitoring svc/$svc 9090:9090 >> "$LOG_FILE" 2>&1 &
            local portforward_pid=$!
            
            # Verificar se o port-forward está funcionando
            sleep 5
            if curl -s --connect-timeout 2 "http://localhost:9090/api/v1/status/config" > /dev/null; then
                log "$GREEN" "Prometheus está acessível via localhost:9090"
                found_service=1
                
                # Verificar se existem targets configurados
                local targets_resp=$(curl -s "http://localhost:9090/api/v1/targets")
                local active_targets=$(echo "$targets_resp" | jq -r '.data.activeTargets | length')
                log "$GREEN" "Prometheus tem $active_targets targets ativos"
                
                # Se não houver alvos, verificar os service monitors
                if [ "$active_targets" = "0" ]; then
                    log "$YELLOW" "Nenhum alvo ativo no Prometheus. Verificando Service Monitors..."
                    kubectl get servicemonitors -A
                    
                    # Aplicar service monitors se necessário
                    log "$YELLOW" "Aplicando Service Monitors do projeto..."
                    kubectl apply -f "$BASE_DIR/observability/servicemonitors/" >> "$LOG_FILE" 2>&1
                fi
                
                break
            else
                log "$RED" "Não foi possível acessar o Prometheus via port-forward"
                kill $portforward_pid 2>/dev/null || true
            fi
        fi
    done
    
    if [ $found_service -eq 0 ]; then
        log "$RED" "Nenhum serviço do Prometheus encontrado. Reiniciando a instalação do Prometheus Operator..."
        kubectl delete --ignore-not-found=true -f "$BASE_DIR/observability/prometheus-values.yaml" >> "$LOG_FILE" 2>&1 || true
        kubectl delete --ignore-not-found=true namespace monitoring >> "$LOG_FILE" 2>&1 || true
        sleep 10
        
        # Recriar namespace e reinstalar o Prometheus
        kubectl create namespace monitoring >> "$LOG_FILE" 2>&1
        bash "$BASE_DIR/install-prom-operator.sh" >> "$LOG_FILE" 2>&1
        sleep 30
        
        # Tentar novamente a verificação
        ensure_prometheus_works
    fi
    
    log "$GREEN" "Verificação do Prometheus concluída"
}

# Inicializar stack de monitoramento com verificações robustas
init_monitoring_stack() {
    local base_dir="$1"
    local log_file="$2"
    
    # Verificar se o namespace de monitoramento já existe
    if ! kubectl get namespace monitoring > /dev/null 2>&1; then
        log "$GREEN" "Instalando stack de observabilidade..."
        bash "$base_dir/install-prom-operator.sh" >> "$log_file" 2>&1
        sleep 30
    else
        log "$GREEN" "Namespace 'monitoring' já existe."
    fi
    
    # Verificar e garantir que o Prometheus esteja funcionando
    ensure_prometheus_works
    
    # Adicionar o deployment do blackbox-exporter se não existir
    if ! kubectl get deployment -n monitoring blackbox-exporter > /dev/null 2>&1; then
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
    fi
}

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
    echo "  --non-interactive          Executa o experimento sem pedir confirmações entre fases e rounds"
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

# Configurar handlers de sinal
setup_signal_handlers

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

# Ajustar durações nos manifestos
adjust_manifests_duration "$BASELINE_DURATION" "$ATTACK_DURATION" "$RECOVERY_DURATION"

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
if [ "$NON_INTERACTIVE" = true ]; then
    log "$GREEN" "Modo não interativo: limpando automaticamente os recursos dos tenants..."
    cleanup_tenants
    log "$GREEN" "Recursos dos tenants removidos."
else
    log "$GREEN" "Deseja limpar os recursos dos tenants? [s/N]"
    read -r clean_response
    if [[ "$clean_response" =~ ^[Ss]$ ]]; then
        cleanup_tenants
        log "$GREEN" "Recursos dos tenants removidos."
    else
        log "$YELLOW" "Os recursos dos tenants foram mantidos para análise posterior."
    fi
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
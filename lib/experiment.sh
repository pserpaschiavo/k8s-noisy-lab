#!/bin/bash

# Importar módulos necessários
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/kubernetes.sh"
source "$SCRIPT_DIR/metrics.sh"

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

# Função para executar a fase de baseline
run_baseline_phase() {
    local phase_name="$1"
    local baseline_duration="$2"
    local base_dir="$3"
    local log_file="$4"
    
    log "$GREEN" "Implantando tenant-a (sensível à rede)..."
    kubectl apply -f "$base_dir/manifests/tenant-a/" >> "$log_file" 2>&1
    
    log "$GREEN" "Aguardando inicialização dos serviços do tenant-a..."
    kubectl -n tenant-a wait --for=condition=available --timeout=120s deployment/nginx-deployment >> "$log_file" 2>&1 || log "$YELLOW" "Timeout aguardando pelo nginx no tenant-a"
    
    log "$GREEN" "Implantando tenant-c (vítima)..."
    kubectl apply -f "$base_dir/manifests/tenant-c/" >> "$log_file" 2>&1
    
    log "$GREEN" "Implantando tenant-d (CPU e Disco)..."
    kubectl apply -f "$base_dir/manifests/tenant-d/" >> "$log_file" 2>&1
    
    log "$GREEN" "Aguardando inicialização de todos os tenants..."
    wait_for_all_tenants_ready 120 || log "$YELLOW" "Nem todos os tenants ficaram prontos dentro do tempo esperado"
    
    sleep "$baseline_duration"
}

# Função para executar a fase de ataque
run_attack_phase() {
    local phase_name="$1"
    local attack_duration="$2"
    local base_dir="$3"
    local log_file="$4"
    
    log "$GREEN" "Implantando tenant-b (atacante noisy neighbor)..."
    kubectl apply -f "$base_dir/manifests/tenant-b/" >> "$log_file" 2>&1
    
    log "$GREEN" "Aguardando inicialização dos serviços do tenant-b..."
    kubectl -n tenant-b wait --for=condition=available deployment/traffic-generator --timeout=120s >> "$log_file" 2>&1 || log "$YELLOW" "Timeout aguardando pelo traffic-generator no tenant-b"
    kubectl -n tenant-b wait --for=condition=available deployment/traffic-server --timeout=120s >> "$log_file" 2>&1 || log "$YELLOW" "Timeout aguardando pelo traffic-server no tenant-b"
    kubectl -n tenant-b wait --for=condition=available deployment/stress-ng --timeout=120s >> "$log_file" 2>&1 || log "$YELLOW" "Timeout aguardando pelo stress-ng no tenant-b"
    kubectl -n tenant-b wait --for=condition=available deployment/iperf-server --timeout=120s >> "$log_file" 2>&1 || log "$YELLOW" "Timeout aguardando pelo iperf-server no tenant-b"
    
    log "$GREEN" "Verificando todos os tenants após a implantação do atacante..."
    wait_for_all_tenants_ready 60 || log "$YELLOW" "Possível impacto do ataque - nem todos os tenants estão totalmente prontos"
    
    sleep "$attack_duration"
}

# Função para executar a fase de recuperação
run_recovery_phase() {
    local phase_name="$1"
    local recovery_duration="$2"
    local base_dir="$3"
    local log_file="$4"
    
    log "$GREEN" "Removendo tenant-b (atacante)..."
    kubectl delete -f "$base_dir/manifests/tenant-b/" >> "$log_file" 2>&1 || log "$YELLOW" "Erro ao remover tenant-b"
    
    log "$GREEN" "Verificando recuperação do tenant-a, tenant-c e tenant-d..."
    wait_for_all_tenants_ready 120 || log "$YELLOW" "Alguns tenants podem não ter se recuperado completamente"
    
    sleep "$recovery_duration"
}

# Função para executar um round completo do experimento
run_experiment_round() {
    local round="$1"
    local num_rounds="$2"
    local base_dir="$3"
    local metrics_dir="$4"
    local log_file="$5"
    local baseline_duration="$6"
    local attack_duration="$7"
    local recovery_duration="$8"
    local collect_metrics="$9"
    
    # Definir nomes das fases com numeração
    local phase_1_name="1 - Baseline"
    local phase_2_name="2 - Attack"
    local phase_3_name="3 - Recovery"
    
    mkdir -p "${metrics_dir}/round-${round}"
    
    log "$YELLOW" "===== ROUND ${round}/${num_rounds} ====="
    
    # FASE 1: BASELINE
    log "$BLUE" "=== Fase $phase_1_name ==="
    if [ "$collect_metrics" = true ]; then
        start_collecting_metrics "$phase_1_name" "$round" "$metrics_dir" "$collect_metrics"
    fi
    
    # Limpar quaisquer workloads anteriores se for o primeiro round
    if [ "$round" -eq 1 ]; then
        log "$GREEN" "Limpando workloads anteriores..."
        kubectl delete --ignore-not-found=true -f "$base_dir/manifests/tenant-a/" >> "$log_file" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$base_dir/manifests/tenant-b/" >> "$log_file" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$base_dir/manifests/tenant-c/" >> "$log_file" 2>&1 || true
        kubectl delete --ignore-not-found=true -f "$base_dir/manifests/tenant-d/" >> "$log_file" 2>&1 || true
        sleep 10  # Espera para garantir que tudo foi removido
    fi
    
    # Executar fase de baseline com timeout
    execute_with_timeout "$phase_1_name" "$baseline_duration" "run_baseline_phase \"$phase_1_name\" \"$baseline_duration\" \"$base_dir\" \"$log_file\""
    
    if [ "$collect_metrics" = true ]; then
        stop_collecting_metrics
    fi
    
    continue_to_next_phase "$phase_1_name" "$phase_2_name"
    
    # FASE 2: ATAQUE
    log "$BLUE" "=== Fase $phase_2_name ==="
    if [ "$collect_metrics" = true ]; then
        start_collecting_metrics "$phase_2_name" "$round" "$metrics_dir" "$collect_metrics"
    fi
    
    execute_with_timeout "$phase_2_name" "$attack_duration" "run_attack_phase \"$phase_2_name\" \"$attack_duration\" \"$base_dir\" \"$log_file\""

    if [ "$collect_metrics" = true ]; then
        stop_collecting_metrics
    fi
    
    continue_to_next_phase "$phase_2_name" "$phase_3_name"
    
    # FASE 3: RECUPERAÇÃO
    log "$BLUE" "=== Fase $phase_3_name ==="
    if [ "$collect_metrics" = true ]; then
        start_collecting_metrics "$phase_3_name" "$round" "$metrics_dir" "$collect_metrics"
    fi
    
    execute_with_timeout "$phase_3_name" "$recovery_duration" "run_recovery_phase \"$phase_3_name\" \"$recovery_duration\" \"$base_dir\" \"$log_file\""

    if [ "$collect_metrics" = true ]; then
        stop_collecting_metrics
    fi
    
    log "$GREEN" "Round ${round}/${num_rounds} concluído com sucesso!"
}

# Função para inicializar o experimento
init_experiment() {
    local experiment_name="$1"
    local base_dir="$2"
    local start_date="$3"
    local start_time="$4"
    
    # Preparar diretórios de métricas e logs
    local metrics_dir="${base_dir}/results/${start_date}/${start_time}/${experiment_name}"
    mkdir -p "$metrics_dir"
    local log_file="${metrics_dir}/experiment.log"
    
    # Inicializar o logger
    init_logger "$log_file"
    
    # Retornar o diretório de métricas e o arquivo de log
    echo "$metrics_dir"
    echo "$log_file"
}

# Função para validar recursos do cluster
validate_cluster_resources() {
    local base_dir="$1"
    local log_file="$2"
    
    log "$GREEN" "Validando recursos do cluster..."
    bash "$base_dir/check-cluster.sh" >> "$log_file" 2>&1 || { log "$RED" "Falha na validação de recursos do cluster"; return 1; }
    
    return 0
}

# Função para verificar pré-requisitos
check_prerequisites() {
    log "$GREEN" "Verificando pré-requisitos..."
    command -v kubectl >/dev/null 2>&1 || { log "$RED" "kubectl não encontrado. Instale o kubectl primeiro."; return 1; }
    command -v helm >/dev/null 2>&1 || { log "$RED" "helm não encontrado. Instale o helm primeiro."; return 1; }
    command -v python3 >/dev/null 2>&1 || { log "$RED" "Python 3 não encontrado. Instale o Python 3 primeiro."; return 1; }
    
    return 0
}

# Função para inicializar a stack de monitoramento
init_monitoring_stack() {
    local base_dir="$1"
    local log_file="$2"
    
    # Instalar monitoring stack se não estiver presente
    if ! kubectl get namespace monitoring > /dev/null 2>&1; then
        log "$GREEN" "Instalando stack de observabilidade..."
        bash "$base_dir/install-prom-operator.sh" >> "$log_file" 2>&1
    else
        log "$GREEN" "Stack de observabilidade já instalada."
    fi
    
    # Esperar pela inicialização do Prometheus
    log "$GREEN" "Aguardando inicialização do Prometheus..."
    kubectl wait --for=condition=Ready -n monitoring pod -l app.kubernetes.io/name=prometheus --timeout=300s >> "$log_file" 2>&1 || {
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
}
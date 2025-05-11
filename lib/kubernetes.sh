#!/bin/bash

# Importar logger usando caminho absoluto
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/lib/logger.sh"

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
    local phase="${2:-all}"  # Parâmetro opcional para especificar a fase do experimento (baseline, attack, recovery, all)
    local success=true
    
    log "$YELLOW" "Verificando se todos os tenants relevantes para a fase '$phase' estão prontos..."
    
    # Definir quais namespaces verificar com base na fase
    local namespaces_to_check=()
    
    case "$phase" in
        baseline)
            namespaces_to_check=("tenant-a" "tenant-c" "tenant-d")
            ;;
        attack)
            namespaces_to_check=("tenant-a" "tenant-b" "tenant-c" "tenant-d")
            ;;
        recovery)
            namespaces_to_check=("tenant-a" "tenant-c" "tenant-d")
            ;;
        *)
            # Valor padrão: verificar todos os namespaces que existem
            namespaces_to_check=("tenant-a" "tenant-b" "tenant-c" "tenant-d")
            ;;
    esac
    
    for ns in "${namespaces_to_check[@]}"; do
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
        log "$GREEN" "Todos os tenants relevantes para a fase '$phase' estão prontos!"
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

# Função para limpar os tenants após o experimento
cleanup_tenants() {
    log "$BLUE" "Limpando todos os tenants após o experimento..."
    kubectl delete namespace tenant-a tenant-b tenant-c tenant-d --ignore-not-found=true >> "$LOG_FILE" 2>&1 || true
    log "$GREEN" "Tenants removidos com sucesso."
}
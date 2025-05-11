#!/bin/bash

# Importar logger e métricas de tenant
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/lib/logger.sh"
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/lib/tenant_metrics.sh"

# Variável para armazenar o PID do processo de coleta de métricas
METRICS_PID=""
METRICS_LOG_FILE=""

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

# Função para acessar o Prometheus via kubectl port-forward
setup_prometheus_access() {
    local log_file="$1"
    
    # Verificar se o Prometheus está acessível
    echo "[$(date +%Y%m%d_%H%M%S)] Verificando acesso ao Prometheus..." >> "$log_file"
    
    # Testar conexão direta ao Prometheus
    if ! curl -s --connect-timeout 2 "http://localhost:9090/api/v1/status/config" > /dev/null; then
        log "$YELLOW" "Prometheus não está acessível via localhost:9090, tentando configurar port-forward..."
        echo "[$(date +%Y%m%d_%H%M%S)] Prometheus não está acessível via localhost:9090" >> "$log_file"
        
        # Interromper qualquer port-forward existente para o Prometheus
        pkill -f "kubectl.*port-forward.*9090:9090" || true
        sleep 1
        
        # Verificar se o namespace de monitoramento existe
        if ! kubectl get namespace monitoring > /dev/null 2>&1; then
            log "$RED" "Namespace 'monitoring' não encontrado. O Prometheus pode não estar instalado."
            echo "[$(date +%Y%m%d_%H%M%S)] ERROR: Namespace 'monitoring' não encontrado" >> "$log_file"
            return 1
        fi
        
        # Listar pods do Prometheus para diagnóstico
        echo "[$(date +%Y%m%d_%H%M%S)] Listando pods do Prometheus:" >> "$log_file"
        kubectl get pods -n monitoring -l app=prometheus >> "$log_file" 2>&1
        kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus >> "$log_file" 2>&1
        
        # Listar serviços do Prometheus para diagnóstico
        echo "[$(date +%Y%m%d_%H%M%S)] Listando serviços do Prometheus:" >> "$log_file"
        kubectl get services -n monitoring | grep -i prom >> "$log_file" 2>&1
        
        # Encontrar o serviço Prometheus
        local prom_service=""
        
        # Tentar várias opções de nomes de serviço
        for svc in "prometheus-operated" "prometheus-k8s" "prometheus" "prometheus-server"; do
            if kubectl get svc -n monitoring $svc > /dev/null 2>&1; then
                prom_service="svc/$svc"
                echo "[$(date +%Y%m%d_%H%M%S)] Encontrado serviço do Prometheus: $svc" >> "$log_file"
                break
            fi
        done
        
        if [ -z "$prom_service" ]; then
            # Tentar encontrar automaticamente qualquer serviço do Prometheus
            local auto_svc=$(kubectl get svc -n monitoring -l app=prometheus -o name 2>/dev/null | head -n 1)
            if [ -n "$auto_svc" ]; then
                prom_service="$auto_svc"
                echo "[$(date +%Y%m%d_%H%M%S)] Encontrado serviço automaticamente: $prom_service" >> "$log_file"
            else
                log "$RED" "Serviço do Prometheus não encontrado. Verifique se ele está instalado corretamente."
                echo "[$(date +%Y%m%d_%H%M%S)] ERROR: Nenhum serviço do Prometheus encontrado" >> "$log_file"
                return 1
            fi
        fi
        
        # Iniciar port-forward em segundo plano
        log "$GREEN" "Configurando port-forward para o Prometheus..."
        echo "[$(date +%Y%m%d_%H%M%S)] Iniciando port-forward: kubectl port-forward --namespace monitoring $prom_service 9090:9090" >> "$log_file"
        
        kubectl port-forward --namespace monitoring $prom_service 9090:9090 >> "$log_file" 2>&1 &
        local portforward_pid=$!
        
        echo "[$(date +%Y%m%d_%H%M%S)] Port-forward iniciado com PID: $portforward_pid" >> "$log_file"
        
        # Esperar o port-forward estar pronto
        local max_attempts=15
        local attempt=0
        while ! curl -s --connect-timeout 1 "http://localhost:9090/api/v1/status/config" > /dev/null; do
            attempt=$((attempt + 1))
            if [ $attempt -ge $max_attempts ]; then
                log "$RED" "Não foi possível acessar o Prometheus após $max_attempts tentativas."
                echo "[$(date +%Y%m%d_%H%M%S)] ERROR: Falha no acesso ao Prometheus após $max_attempts tentativas" >> "$log_file"
                kill $portforward_pid 2>/dev/null || true
                return 1
            fi
            log "$YELLOW" "Aguardando port-forward para o Prometheus (tentativa $attempt/$max_attempts)..."
            echo "[$(date +%Y%m%d_%H%M%S)] Aguardando port-forward, tentativa $attempt/$max_attempts" >> "$log_file"
            sleep 2
        done
        
        log "$GREEN" "Port-forward para o Prometheus configurado com sucesso (PID: $portforward_pid)"
        echo "[$(date +%Y%m%d_%H%M%S)] Port-forward para o Prometheus configurado com sucesso" >> "$log_file"
    else
        log "$GREEN" "Prometheus já está acessível via localhost:9090"
        echo "[$(date +%Y%m%d_%H%M%S)] Prometheus já está acessível via localhost:9090" >> "$log_file"
    fi
    
    # Verificar se o Prometheus está funcionando corretamente
    echo "[$(date +%Y%m%d_%H%M%S)] Testando consulta ao Prometheus..." >> "$log_file"
    local test_resp=$(curl -s --connect-timeout 5 "http://localhost:9090/api/v1/query?query=up")
    local test_status=$(echo "$test_resp" | jq -r '.status // "error"')
    
    if [ "$test_status" != "success" ]; then
        log "$RED" "Prometheus está acessível, mas não está respondendo corretamente às consultas."
        echo "[$(date +%Y%m%d_%H%M%S)] ERROR: Prometheus não está respondendo corretamente às consultas: $test_resp" >> "$log_file"
        return 1
    fi
    
    # Verificar se há alvos no Prometheus
    local targets_resp=$(curl -s --connect-timeout 5 "http://localhost:9090/api/v1/targets")
    echo "[$(date +%Y%m%d_%H%M%S)] Alvos do Prometheus: $(echo "$targets_resp" | jq -r '.data.activeTargets | length') ativos, $(echo "$targets_resp" | jq -r '.data.droppedTargets | length') descartados" >> "$log_file"
    
    return 0
}

# Função de coleta contínua com logs de erro e fallback de label
collect_metrics_continuously() {
    local phase_id="$1" round_num="$2" metrics_dir="$3" log_file="$4"
    # Usar o intervalo de coleta de métricas definido no script principal ou o valor padrão
    local interval="${METRICS_INTERVAL:-5}"
    
    # Salvar o caminho do log em uma variável global para acesso em outras funções
    METRICS_LOG_FILE="$log_file"
    
    log "$BLUE" "Coletando métricas a cada ${interval} segundos..."
    echo "[$(date +%Y%m%d_%H%M%S)] Iniciando coleta de métricas a cada ${interval} segundos" >> "$log_file"
    
    # Listar todas as métricas que serão coletadas
    echo "[$(date +%Y%m%d_%H%M%S)] Métricas configuradas para coleta:" >> "$log_file"
    for name in "${!PROM_QUERIES[@]}"; do
        echo "  - $name: ${PROM_QUERIES[$name]}" >> "$log_file"
    done
    
    # Configurar acesso ao Prometheus
    if ! setup_prometheus_access "$log_file"; then
        log "$RED" "Falha ao configurar acesso ao Prometheus. A coleta de métricas pode não funcionar corretamente."
        echo "[$(date +%Y%m%d_%H%M%S)] AVISO: Configuração do Prometheus falhou, as métricas podem não ser coletadas" >> "$log_file"
    fi
    
    # Contadores de métricas para diagnóstico
    local total_collections=0
    local successful_collections=0
    local failed_collections=0
    
    while true; do
        local collection_start=$(date +%s)
        local ts=$(date +%Y%m%d_%H%M%S)
        local metrics_collected=0
        local failed_queries=0
        total_collections=$((total_collections + 1))
        
        # Listar pods para verificar o estado do cluster a cada 10 coletas
        if [ $((total_collections % 10)) -eq 1 ]; then
            echo "[$ts] Verificando pods em todos os namespaces:" >> "$log_file"
            kubectl get pods -A >> "$log_file" 2>&1 || echo "[$ts] Erro ao listar pods" >> "$log_file"
        fi
        
        for name in "${!PROM_QUERIES[@]}"; do
            local query="${PROM_QUERIES[$name]}"
            local encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
            
            # Log da consulta completa para diagnóstico
            echo "[$ts] Executando consulta: $name -> http://localhost:9090/api/v1/query?query=$encoded_query" >> "$log_file"
            
            # Chamar API Prometheus com mais tempo de timeout
            local resp
            if ! resp=$(curl -s --connect-timeout 10 --max-time 20 "http://localhost:9090/api/v1/query?query=$encoded_query"); then
                echo "[$ts] ERROR: curl falhou para $name" >> "$log_file"
                failed_queries=$((failed_queries + 1))
                continue
            fi
            
            # Verificar status da resposta
            local status
            status=$(echo "$resp" | jq -r '.status // "error"')
            if [ "$status" != "success" ]; then
                echo "[$ts] ERROR: consulta falhou para $name: $(echo "$resp" | jq -r '.error // "erro desconhecido"')" >> "$log_file"
                echo "[$ts] Resposta completa: $resp" >> "$log_file"
                failed_queries=$((failed_queries + 1))
                continue
            fi
            
            # Extrai namespace e valor, cada linha CSV: ns,val
            local csv_lines
            csv_lines=$(echo "$resp" | jq -r '.data.result[]? | [(.metric.namespace // .metric.pod // .metric.instance // .metric.job // .metric.state // "unknown"), (.value[1] // "")] | @csv')
            
            if [ -z "$csv_lines" ]; then
                echo "[$ts] WARN: sem dados para $name" >> "$log_file"
                continue
            fi
            
            # Grava cada linha em CSV por namespace
            while IFS=',' read -r ns val; do
                ns=${ns//\"/}
                val=${val//\"/}
                
                # Limpar o nome do namespace para uso como nome de diretório
                local clean_ns=$(echo "$ns" | tr -cd '[:alnum:]-_.')
                if [ -z "$clean_ns" ]; then
                    clean_ns="unknown"
                fi
                
                local out_dir="$metrics_dir/round-${round_num}/${phase_id}/${clean_ns}"
                mkdir -p "$out_dir"
                local file="$out_dir/${name}.csv"
                
                if [ ! -f "$file" ]; then
                    echo "timestamp,value" > "$file"
                fi
                
                # Verificar se o valor é numérico, se não for, usar 0
                if ! [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    echo "[$ts] WARN: valor não numérico para $name: $val, usando 0" >> "$log_file"
                    val="0"
                fi
                
                echo "$ts,$val" >> "$file"
                metrics_collected=$((metrics_collected + 1))
            done <<< "$csv_lines"
        done
        
        # Registrar estatísticas da coleta
        local collection_end=$(date +%s)
        local collection_time=$((collection_end - collection_start))
        
        if [ $metrics_collected -gt 0 ]; then
            successful_collections=$((successful_collections + 1))
        else
            failed_collections=$((failed_collections + 1))
            
            # Se tivermos falhas consecutivas, tentar reconectar ao Prometheus
            if [ $((failed_collections % 3)) -eq 0 ]; then
                echo "[$ts] WARN: Múltiplas falhas consecutivas na coleta, tentando reconectar ao Prometheus..." >> "$log_file"
                setup_prometheus_access "$log_file"
            fi
        fi
        
        echo "[$ts] INFO: Coletadas $metrics_collected métricas em $collection_time segundos (falhas: $failed_queries, total até agora: sucesso=${successful_collections}, falha=${failed_collections})" >> "$log_file"
        
        # Calcular quanto tempo dormir para manter o intervalo constante
        local sleep_time=$((interval - collection_time))
        if [ $sleep_time -lt 1 ]; then
            sleep_time=1
        fi
        
        sleep $sleep_time
    done
}

# Função para iniciar a coleta contínua
start_collecting_metrics() {
    local phase="$1"
    local round="$2"
    local metrics_dir="$3"
    local collect_metrics="$4"
    
    if [ "$collect_metrics" = true ]; then
        # Criar diretório para logs de métricas
        local metrics_log_dir="$metrics_dir/round-$round/$phase/logs"
        mkdir -p "$metrics_log_dir"
        local log_file="$metrics_log_dir/metrics_collection.log"
        
        collect_metrics_continuously "$phase" "$round" "$metrics_dir" "$log_file" &
        METRICS_PID=$!
        log "$BLUE" "Coleta de métricas iniciada com PID: $METRICS_PID (log: $log_file)"
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
        
        # Finalizar também o port-forward do Prometheus se estiver ativo
        pkill -f "kubectl.*port-forward.*9090:9090" || true
        
        if [ -n "$METRICS_LOG_FILE" ] && [ -f "$METRICS_LOG_FILE" ]; then
            log "$BLUE" "Log de coleta de métricas salvo em: $METRICS_LOG_FILE"
        fi
        
        log "$BLUE" "Coleta de métricas finalizada."
    fi
    unset METRICS_PID
}
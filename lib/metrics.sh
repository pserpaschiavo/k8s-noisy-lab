#!/bin/bash

# Importar logger e métricas de tenant
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/lib/logger.sh"
source "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/lib/tenant_metrics.sh"

# Variável para armazenar o PID do processo de coleta de métricas
METRICS_PID=""
METRICS_LOG_FILE=""

# Definir diretamente as queries PromQL para coleta de métricas (baseado no arquivo de backup)
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
    
    # Métricas de latência 
    ["latency_process_time"]="rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=~\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_connections_total{namespace=~\"ingress-nginx\",state=\"handled\"}[1m])"
    ["latency_bytes_per_request"]="rate(nginx_ingress_controller_nginx_process_read_bytes_total{namespace=~\"ingress-nginx\"}[1m]) / rate(nginx_ingress_controller_nginx_process_requests_total{namespace=~\"ingress-nginx\"}[1m])"
    
    # Métricas de jitter
    ["jitter_admission_process"]="stddev_over_time(nginx_ingress_controller_admission_roundtrip_duration{namespace=\"ingress-nginx\"}[5m])"
    ["jitter_processing_rate"]="stddev_over_time(rate(nginx_ingress_controller_nginx_process_cpu_seconds_total{namespace=\"ingress-nginx\"}[1m])[5m:1m])"
    
    # Métricas avançadas de CPU, memória e rede
    ["cpu_usage_variability"]="stddev_over_time(sum by (namespace) (rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))[5m:])"
    ["memory_pressure"]="sum by (namespace) (container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}) / sum by (namespace) (container_spec_memory_limit_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"})"
    ["network_total_bandwidth"]="sum by (namespace) (rate(container_network_receive_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_network_transmit_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["network_packet_rate"]="sum by (namespace) (rate(container_network_receive_packets_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_network_transmit_packets_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["network_error_rate"]="sum by (namespace) (rate(container_network_receive_errors_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_network_transmit_errors_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    
    # Métricas de disco
    ["disk_io_total"]="sum by (namespace) (rate(container_fs_reads_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_fs_writes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    ["disk_throughput_total"]="sum by (namespace) (rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))"
    
    # Métricas relacionais entre tenants
    ["cpu_usage_noisy_victim_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-c\"}[1m]))"
    ["memory_usage_noisy_victim_ratio"]="sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=\"tenant-c\"})"
    ["network_usage_noisy_victim_ratio"]="sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-b\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-c\"}[1m]) + rate(container_network_receive_bytes_total{namespace=\"tenant-c\"}[1m]))"
    ["resource_dominance_index"]="(sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-b\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}[1m]))) * (sum(container_memory_working_set_bytes{namespace=\"tenant-b\"}) / sum(container_memory_working_set_bytes{namespace=~\"tenant-a|tenant-b|tenant-c|tenant-d\"}))"
    
    # Métricas para tenant-d (postgres)
    ["postgres_disk_io"]="sum(rate(pg_stat_database_blks_read{namespace=\"tenant-d\"}[1m]) + rate(pg_stat_database_blks_written{namespace=\"tenant-d\"}[1m])) by (datname)"
    ["postgres_connections"]="sum(pg_stat_database_numbackends{namespace=\"tenant-d\"}) by (datname)"
    ["postgres_transactions"]="sum(rate(pg_stat_database_xact_commit{namespace=\"tenant-d\"}[1m]) + rate(pg_stat_database_xact_rollback{namespace=\"tenant-d\"}[1m])) by (datname)"
    ["disk_io_tenant_d"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m])) by (container)"
    ["cpu_tenant_d_vs_other_ratio"]="sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-d\"}[1m])) / sum(rate(container_cpu_usage_seconds_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]))"
    ["disk_tenant_d_vs_other_ratio"]="sum(rate(container_fs_reads_bytes_total{namespace=\"tenant-d\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=\"tenant-d\"}[1m])) / sum(rate(container_fs_reads_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]) + rate(container_fs_writes_bytes_total{namespace=~\"tenant-a|tenant-b|tenant-c\"}[1m]))"
)

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
    echo "[$(date +%Y%m%d_%H%M%S)] Métricas configuradas para coleta: ${#PROM_QUERIES[@]}" >> "$log_file"
    
    # Configurar acesso ao Prometheus
    if ! setup_prometheus_access "$log_file"; then
        log "$RED" "Falha ao configurar acesso ao Prometheus. A coleta de métricas pode não funcionar corretamente."
        echo "[$(date +%Y%m%d_%H%M%S)] AVISO: Configuração do Prometheus falhou, as métricas podem não ser coletadas" >> "$log_file"
    fi
    
    # Contadores de métricas para diagnóstico
    local total_collections=0
    local successful_collections=0
    local failed_collections=0
    
    # DEBUG: Verificar se há espaço suficiente no disco
    df -h >> "$log_file"
    
    # DEBUG: Verificar se há permissões de escrita no diretório de métricas
    echo "[$(date +%Y%m%d_%H%M%S)] DEBUG: Verificando permissões de escrita em $metrics_dir" >> "$log_file"
    touch "$metrics_dir/test_write.tmp" && rm "$metrics_dir/test_write.tmp" && echo "Escrita permitida" >> "$log_file" || echo "ERRO: Escrita não permitida" >> "$log_file"
    
    # DEBUG: Verificar se PROM_QUERIES tem conteúdo
    echo "[$(date +%Y%m%d_%H%M%S)] DEBUG: Número total de métricas: ${#PROM_QUERIES[@]}" >> "$log_file"
    
    # Implementação simples baseada no backup que funcionava
    while true; do
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
                failed_queries=$((failed_queries + 1))
                continue
            fi
            
            # Extrai namespace e valor, cada linha CSV: ns,val (implementação simples do backup)
            local csv_lines
            csv_lines=$(echo "$resp" | jq -r '.data.result[]? | [(.metric.namespace // .metric.pod // .metric.instance // .metric.job // .metric.state // .metric.datname // "unknown"), (.value[1] // "")] | @csv')
            
            if [ -z "$csv_lines" ]; then
                echo "[$ts] WARN: sem dados para $name" >> "$log_file"
                continue
            fi
            
            # Grava cada linha em CSV por namespace (Versão simplificada do backup)
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
                
                if [ ! -f "$file" ];then
                    echo "timestamp,value" > "$file"
                fi
                
                # Versão exatamente igual ao backup
                echo "\"${ts}\",\"${val}\"" >> "$file"
                metrics_collected=$((metrics_collected + 1))
            done <<< "$csv_lines"
        done
        
        if [ $metrics_collected -gt 0 ]; then
            successful_collections=$((successful_collections + 1))
            echo "[$ts] INFO: Coletadas $metrics_collected métricas com sucesso (falhas: $failed_queries, total até agora: sucesso=${successful_collections}, falha=${failed_collections})" >> "$log_file"
        else
            failed_collections=$((failed_collections + 1))
            echo "[$ts] WARN: Nenhuma métrica coletada neste ciclo (falhas: $failed_queries, total até agora: sucesso=${successful_collections}, falha=${failed_collections})" >> "$log_file"
            
            # Se tivermos falhas consecutivas, tentar reconectar ao Prometheus
            if [ $((failed_collections % 3)) -eq 0 ]; then
                echo "[$ts] WARN: Múltiplas falhas consecutivas na coleta, tentando reconectar ao Prometheus..." >> "$log_file"
                setup_prometheus_access "$log_file"
            fi
        fi
        
        # Aguardar intervalo antes da próxima coleta
        sleep "$interval"
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
        
        # Exportar a variável para o script principal
        export METRICS_PID
        
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
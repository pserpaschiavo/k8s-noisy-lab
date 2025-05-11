#!/bin/bash

set -eo pipefail

# Diretório base
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Importar módulos
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/tenant_metrics.sh"

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NO_COLOR='\033[0m'

# Função de ajuda
show_help() {
    echo "Uso: $0 <tenant-id> [métrica]"
    echo
    echo "Tenants disponíveis:"
    echo "  a, tenant-a     - Tenant sensível à rede"
    echo "  b, tenant-b     - Tenant barulhento"
    echo "  c, tenant-c     - Tenant sensível à memória"
    echo "  d, tenant-d     - Tenant sensível a CPU e disco"
    echo
    echo "Comparações disponíveis:"
    echo "  b-vs-a          - Relação entre tenant barulhento e tenant sensível à rede"
    echo "  b-vs-c          - Relação entre tenant barulhento e tenant sensível à memória"
    echo "  b-vs-d          - Relação entre tenant barulhento e tenant sensível a CPU e disco"
    echo
    echo "Opções:"
    echo "  -h, --help      - Mostra esta ajuda"
    echo "  -l, --list      - Lista métricas disponíveis para o tenant especificado"
    echo
    echo "Exemplos:"
    echo "  $0 a            - Diagnóstico geral do tenant-a (rede)"
    echo "  $0 b -l         - Lista todas as métricas disponíveis para o tenant barulhento"
    echo "  $0 b-vs-a       - Mostra relação entre tenant barulhento e tenant de rede"
    echo "  $0 c memory_usage - Mostra uso de memória específico do tenant-c"
}

# Função para mostrar dados de um tenant
show_tenant_data() {
    local tenant="$1"
    local full_tenant_name=""
    
    # Converter abreviações para nomes completos
    case "$tenant" in
        "a") full_tenant_name="tenant-a" ;;
        "b") full_tenant_name="tenant-b" ;;
        "c") full_tenant_name="tenant-c" ;;
        "d") full_tenant_name="tenant-d" ;;
        "tenant-a"|"tenant-b"|"tenant-c"|"tenant-d"|"tenant-b-vs-a"|"tenant-b-vs-c"|"tenant-b-vs-d") 
            full_tenant_name="$tenant" 
            ;;
        *)
            echo -e "${RED}Tenant inválido: $tenant${NO_COLOR}"
            show_help
            exit 1
            ;;
    esac
    
    # Mostrar informações do tenant
    echo -e "${GREEN}=== Diagnóstico para $full_tenant_name ===${NO_COLOR}"
    
    # Verificar se o tenant existe no cluster
    if [[ "$full_tenant_name" == tenant-* && ! "$full_tenant_name" == *-vs-* ]]; then
        if ! kubectl get namespace "$full_tenant_name" &>/dev/null; then
            echo -e "${RED}Namespace $full_tenant_name não encontrado no cluster${NO_COLOR}"
            return 1
        fi
        
        echo -e "${BLUE}Pods no namespace $full_tenant_name:${NO_COLOR}"
        kubectl get pods -n "$full_tenant_name" -o wide
        echo
    fi
    
    # Se um segundo argumento foi fornecido, ele é a métrica específica
    if [ -n "$2" ]; then
        if [ "$2" == "-l" ] || [ "$2" == "--list" ]; then
            echo -e "${YELLOW}Métricas disponíveis para $full_tenant_name:${NO_COLOR}"
            list_tenant_metrics "$full_tenant_name" | sort
        else
            # Obter a query para a métrica solicitada
            local metric="$2"
            local query=$(get_tenant_metric "$full_tenant_name" "$metric")
            
            if [ -z "$query" ]; then
                echo -e "${RED}Métrica desconhecida: $metric${NO_COLOR}"
                echo "Use a opção -l para listar métricas disponíveis."
                return 1
            fi
            
            echo -e "${CYAN}Obtendo métrica: $metric${NO_COLOR}"
            echo -e "${PURPLE}Query: $query${NO_COLOR}"
            echo
            
            echo -e "${GREEN}Resultado atual:${NO_COLOR}"
            if ! curl -s -G "http://localhost:9090/api/v1/query" --data-urlencode "query=$query" | jq '.data.result[] | {labels: .metric, value: .value[1]}'; then
                echo -e "${RED}Falha ao consultar o Prometheus. Ele está acessível em localhost:9090?${NO_COLOR}"
                echo "Tente executar um port-forward: kubectl -n monitoring port-forward svc/prometheus-server 9090:80"
            fi
        fi
    else
        # Sem métrica específica, mostrar visão geral do tenant
        case "$full_tenant_name" in
            "tenant-a")
                echo -e "${BLUE}Tenant A - Sensível à Rede${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- network_receive: Recebimento de dados"
                echo -e "- network_transmit: Transmissão de dados"
                echo -e "- network_dropped: Pacotes descartados"
                echo -e "- network_efficiency: Eficiência da rede"
                echo -e "\nUse: $0 a -l para listar todas as métricas disponíveis"
                ;;
            "tenant-b")
                echo -e "${BLUE}Tenant B - Barulhento (Noisy Neighbor)${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- cpu_usage: Uso de CPU"
                echo -e "- memory_usage: Uso de memória"
                echo -e "- resource_dominance_index: Dominância de recursos"
                echo -e "\nUse: $0 b -l para listar todas as métricas disponíveis"
                ;;
            "tenant-c")
                echo -e "${BLUE}Tenant C - Sensível à Memória${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- memory_usage: Uso de memória"
                echo -e "- memory_pressure: Pressão de memória"
                echo -e "- memory_oomkill_events: Eventos OOMKilled"
                echo -e "\nUse: $0 c -l para listar todas as métricas disponíveis"
                ;;
            "tenant-d")
                echo -e "${BLUE}Tenant D - Sensível a CPU e Disco${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- cpu_usage: Uso de CPU"
                echo -e "- disk_io_total: Operações de I/O"
                echo -e "- disk_throughput_total: Throughput de disco"
                echo -e "\nUse: $0 d -l para listar todas as métricas disponíveis"
                ;;
            "tenant-b-vs-a")
                echo -e "${BLUE}Relação Tenant B -> Tenant A (Impacto na Rede)${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- network_usage_noisy_network_ratio: Razão de uso de rede"
                echo -e "- network_packets_noisy_network_ratio: Razão de pacotes"
                echo -e "- network_dropped_noisy_network_ratio: Razão de pacotes descartados"
                echo -e "\nUse: $0 b-vs-a -l para listar todas as métricas disponíveis"
                ;;
            "tenant-b-vs-c")
                echo -e "${BLUE}Relação Tenant B -> Tenant C (Impacto na Memória)${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- memory_usage_noisy_victim_ratio: Razão de uso de memória"
                echo -e "- cpu_usage_noisy_victim_ratio: Razão de uso de CPU"
                echo -e "\nUse: $0 b-vs-c -l para listar todas as métricas disponíveis"
                ;;
            "tenant-b-vs-d")
                echo -e "${BLUE}Relação Tenant B -> Tenant D (Impacto em CPU/Disco)${NO_COLOR}"
                echo -e "Métricas recomendadas para monitorar:"
                echo -e "- cpu_tenant_d_vs_other_ratio: CPU do tenant D vs resto"
                echo -e "- disk_tenant_d_vs_other_ratio: I/O de disco do tenant D vs resto"
                echo -e "\nUse: $0 b-vs-d -l para listar todas as métricas disponíveis"
                ;;
        esac
    fi
}

# Função principal
main() {
    if [ "$#" -eq 0 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        show_help
        exit 0
    fi

    # Verificar disponibilidade do Prometheus
    if ! curl -s "http://localhost:9090/api/v1/status/config" > /dev/null; then
        echo -e "${YELLOW}AVISO: Prometheus não parece estar acessível em localhost:9090${NO_COLOR}"
        echo "Execute um port-forward para acessar o Prometheus:"
        echo "  kubectl -n monitoring port-forward svc/prometheus-server 9090:80"
        echo
        # Continuar mesmo sem acesso ao Prometheus para poder listar métricas e mostrar informações básicas
    fi

    show_tenant_data "$@"
}

# Iniciar a execução
main "$@"
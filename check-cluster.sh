#!/bin/bash
# filepath: /home/phil/Projects/k8s-noisy-lab/check-cluster.sh

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
NO_COLOR='\033[0m'

echo -e "${PURPLE}==========================================${NO_COLOR}"
echo -e "${PURPLE}     VERIFICAÇÃO PRÉ-EXPERIMENTO         ${NO_COLOR}"
echo -e "${PURPLE}==========================================${NO_COLOR}"

# 1. Verificar se o kubectl está disponível
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERRO: kubectl não encontrado. Instale o kubectl antes de prosseguir.${NO_COLOR}"
    exit 1
fi

# 2. Verificar conectividade com o cluster
echo -e "${PURPLE}Verificando conectividade com o cluster...${NO_COLOR}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}ERRO: Não foi possível conectar ao cluster. Verifique sua configuração do kubectl.${NO_COLOR}"
    exit 1
fi
echo -e "${GREEN}✓ Conexão com o cluster estabelecida com sucesso${NO_COLOR}"

# 3. Verificar estado dos nós
echo -e "${PURPLE}Verificando estado dos nós do cluster...${NO_COLOR}"
NOT_READY_NODES=$(kubectl get nodes | grep -v "Ready" | grep -v "NAME" | wc -l)
if [ "$NOT_READY_NODES" -gt 0 ]; then
    echo -e "${YELLOW}AVISO: Existem nós que não estão no estado 'Ready':${NO_COLOR}"
    kubectl get nodes | grep -v "Ready" | grep -v "NAME"
fi
NODE_COUNT=$(kubectl get nodes -o name | wc -l)
echo -e "${GREEN}✓ O cluster possui $NODE_COUNT nós disponíveis${NO_COLOR}"

# 4. Verificar recursos disponíveis - MÉTODO CORRIGIDO COMPLETAMENTE
echo -e "${PURPLE}Verificando recursos disponíveis no cluster...${NO_COLOR}"

# MÉTODO DIRETO: Obter CPU e memória diretamente das capacidades dos nós
# Este método é mais confiável e não depende de métricas em tempo real

# Obter CPU cores usando o formato correto (inteiro)
AVAILABLE_CPU=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.cpu}{"\n"}{end}' | awk '{s+=$1} END {print s}')

# Obter memória em formato mais confiável
MEM_VALUES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.memory}{"\n"}{end}')

# Calcular total de memória em GB
TOTAL_MEM_GB=0
while IFS= read -r mem_str; do
    if [[ $mem_str == *Ki ]]; then
        mem_val=$(echo $mem_str | sed 's/Ki//')
        mem_gb=$(echo "scale=2; $mem_val / 1024 / 1024" | bc)
    elif [[ $mem_str == *Mi ]]; then
        mem_val=$(echo $mem_str | sed 's/Mi//')
        mem_gb=$(echo "scale=2; $mem_val / 1024" | bc)
    elif [[ $mem_str == *Gi ]]; then
        mem_val=$(echo $mem_str | sed 's/Gi//')
        mem_gb=$mem_val
    else
        # Assumindo bytes
        mem_val=$mem_str
        mem_gb=$(echo "scale=2; $mem_val / 1024 / 1024 / 1024" | bc)
    fi
    TOTAL_MEM_GB=$(echo "$TOTAL_MEM_GB + $mem_gb" | bc)
done <<< "$MEM_VALUES"

AVAILABLE_MEM=$TOTAL_MEM_GB

echo -e "CPU: ${PURPLE}$AVAILABLE_CPU${NO_COLOR} cores"
echo -e "Memória: ${PURPLE}$AVAILABLE_MEM${NO_COLOR} GB"

REQUESTED_CPU=3.8  # Total de CPUs necessárias para todos os workloads
REQUESTED_MEM=3.8  # Total de GB necessários para todos os workloads

if (( $(echo "$AVAILABLE_CPU < $REQUESTED_CPU" | bc -l) )); then
    echo -e "${RED}AVISO CRÍTICO: O cluster não tem CPUs suficientes para executar o experimento!${NO_COLOR}"
    echo -e "${RED}  Requerido: $REQUESTED_CPU cores${NO_COLOR}"
    echo -e "${RED}  Disponível: $AVAILABLE_CPU cores${NO_COLOR}"
    echo -e "${YELLOW}Recomendação: Configure um cluster com pelo menos 4 CPUs${NO_COLOR}"
    exit 1
fi

if (( $(echo "$AVAILABLE_MEM < $REQUESTED_MEM" | bc -l) )); then
    echo -e "${RED}AVISO CRÍTICO: O cluster não tem memória suficiente para executar o experimento!${NO_COLOR}"
    echo -e "${RED}  Requerido: $REQUESTED_MEM GB${NO_COLOR}"
    echo -e "${RED}  Disponível: $AVAILABLE_MEM GB${NO_COLOR}"
    echo -e "${YELLOW}Recomendação: Configure um cluster com pelo menos 4GB de RAM${NO_COLOR}"
    exit 1
fi
echo -e "${GREEN}✓ Recursos do cluster são suficientes para o experimento${NO_COLOR}"

# 5. Verificar namespaces necessárias
echo -e "${PURPLE}Verificando namespaces necessárias...${NO_COLOR}"
REQUIRED_NAMESPACES=("tenant-a" "tenant-b" "tenant-c" "monitoring")
MISSING_NS=0

for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if ! kubectl get namespace $ns &> /dev/null; then
        echo -e "${YELLOW}Namespace '$ns' não encontrada - será criada durante a execução${NO_COLOR}"
        MISSING_NS=1
    else
        echo -e "${GREEN}✓ Namespace '$ns' encontrada${NO_COLOR}"
        
        # Verifica se há alguma quota configurada
        if [ "$ns" != "monitoring" ] && ! kubectl get resourcequota -n $ns &> /dev/null; then
            echo -e "${YELLOW}  ⚠️ Namespace '$ns' não possui ResourceQuota configurada${NO_COLOR}"
        fi
    fi
done

# 6. Verificar disponibilidade do Prometheus
echo -e "${PURPLE}Verificando disponibilidade do Prometheus...${NO_COLOR}"
if ! kubectl get namespace monitoring &> /dev/null; then
    echo -e "${YELLOW}Namespace 'monitoring' não encontrada - O Prometheus será instalado durante a execução${NO_COLOR}"
else
    # Verificar se o Prometheus está rodando
    if ! kubectl get pods -n monitoring -l app=prometheus &> /dev/null; then
        echo -e "${YELLOW}Prometheus não encontrado na namespace 'monitoring'${NO_COLOR}"
        echo -e "${YELLOW}Será instalado durante a execução do experimento${NO_COLOR}"
    else
        PROM_READY=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -o "true" | wc -l)
        PROM_TOTAL=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | wc -w)
        
        if [ "$PROM_READY" -lt "$PROM_TOTAL" ]; then
            echo -e "${YELLOW}Alguns pods do Prometheus não estão prontos ($PROM_READY/$PROM_TOTAL)${NO_COLOR}"
        else
            echo -e "${GREEN}✓ Prometheus está rodando e pronto${NO_COLOR}"
            
            # 7. Verificar disponibilidade das métricas necessárias
            echo -e "${PURPLE}Verificando disponibilidade das métricas essenciais...${NO_COLOR}"
            if kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090 &>/dev/null & then
                PF_PID=$!
                sleep 3
                
                # Testando métricas essenciais
                METRICS_TO_TEST=(
                    "container_cpu_usage_seconds_total"
                    "container_memory_working_set_bytes"
                    "container_network_receive_bytes_total"
                    "container_network_transmit_bytes_total"
                    "container_cpu_cfs_throttled_periods_total"
                    "container_cpu_cfs_periods_total"
                )
                
                for metric in "${METRICS_TO_TEST[@]}"; do
                    if curl -s "http://localhost:9090/api/v1/query?query=$metric" | grep -q "result"; then
                        echo -e "${GREEN}✓ Métrica '$metric' disponível${NO_COLOR}"
                    else
                        echo -e "${YELLOW}⚠️ Métrica '$metric' não encontrada${NO_COLOR}"
                        echo -e "${YELLOW}  Esta métrica é necessária para o experimento de noisy neighbours.${NO_COLOR}"
                    fi
                done
                
                # Matando o port-forward
                kill $PF_PID 2>/dev/null
            else
                echo -e "${YELLOW}Não foi possível verificar métricas (falha no port-forward)${NO_COLOR}"
            fi
        fi
    fi
fi

# 8. Verificar permissões
echo -e "${PURPLE}Verificando permissões necessárias...${NO_COLOR}"
if ! kubectl auth can-i create namespace &> /dev/null; then
    echo -e "${RED}AVISO: O usuário atual não tem permissão para criar namespaces${NO_COLOR}"
    echo -e "${RED}Isso pode causar problemas durante a execução do experimento${NO_COLOR}"
fi

if ! kubectl auth can-i create pods --all-namespaces &> /dev/null; then
    echo -e "${RED}AVISO: O usuário atual pode não ter permissão para criar pods em todas as namespaces${NO_COLOR}"
    echo -e "${RED}Isso pode causar problemas durante a execução do experimento${NO_COLOR}"
fi

# 9. Verificar recursos do Prometheus Operator
echo -e "${PURPLE}Verificando CRDs do Prometheus Operator...${NO_COLOR}"
REQUIRED_CRDS=("servicemonitors.monitoring.coreos.com" "prometheusrules.monitoring.coreos.com")
MISSING_CRD=0

for crd in "${REQUIRED_CRDS[@]}"; do
    if ! kubectl get crd $crd &> /dev/null; then
        echo -e "${YELLOW}Custom Resource Definition '$crd' não encontrada${NO_COLOR}"
        echo -e "${YELLOW}Será criada durante a instalação do Prometheus Operator${NO_COLOR}"
        MISSING_CRD=1
    else
        echo -e "${GREEN}✓ CRD '$crd' encontrada${NO_COLOR}"
    fi
done

echo -e "${PURPLE}==========================================${NO_COLOR}"
echo -e "${GREEN}✓ Cluster validado com sucesso para o experimento${NO_COLOR}"
echo -e "${PURPLE}==========================================${NO_COLOR}"

echo -e "\nInformações adicionais:"
echo -e "- O experimento utiliza métricas da cAdvisor integradas ao kubelet"
echo -e "- As queries do Prometheus usam principalmente métricas rate() com 1m de janela"
echo -e "- Os workloads são distribuídos em 3 tenants para simular o cenário de noisy neighbour"
echo -e "\nRecomendações finais:"
echo -e "- Certifique-se de ter pelo menos 15-20% de recursos livres além dos solicitados"
echo -e "- Se estiver usando Minikube, use a opção '--driver=docker' para melhor desempenho"
echo -e "- Verifique se não há outros processos consumindo recursos significativos nos nós"

exit 0
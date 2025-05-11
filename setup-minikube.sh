#!/bin/bash

set -eo pipefail

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações padrão
CPUS=8
MEMORY=16g
DISK_SIZE=40g
LIMITED_RESOURCES=false

# Função para imprimir mensagens
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Função de ajuda
show_help() {
    print_message "$BLUE" "Uso: $0 [opções]"
    print_message "$BLUE" "Opções:"
    print_message "$BLUE" "  -h, --help             Mostra esta ajuda"
    print_message "$BLUE" "  -l, --limited          Usa configuração para recursos limitados (4 CPUs, 8GB RAM)"
    print_message "$BLUE" "  --cpus NUM             Define o número de CPUs (padrão: 8)"
    print_message "$BLUE" "  --memory SIZE          Define a quantidade de memória (padrão: 16g)"
    print_message "$BLUE" "  --disk SIZE            Define o tamanho do disco (padrão: 40g)"
}

# Processamento de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) 
            show_help
            exit 0 
            ;;
        -l|--limited)
            LIMITED_RESOURCES=true
            shift
            ;;
        --cpus)
            CPUS="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --disk)
            DISK_SIZE="$2"
            shift 2
            ;;
        *)
            print_message "$RED" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Aplicar configuração para recursos limitados se solicitado
if [ "$LIMITED_RESOURCES" = true ]; then
    CPUS=4
    MEMORY=8g
    DISK_SIZE=30g
    print_message "$YELLOW" "Usando configuração para recursos limitados: $CPUS CPUs, $MEMORY RAM, $DISK_SIZE disco"
else
    print_message "$GREEN" "Usando configuração recomendada: $CPUS CPUs, $MEMORY RAM, $DISK_SIZE disco"
fi

# Verificar pré-requisitos
check_prerequisites() {
    print_message "$BLUE" "Verificando pré-requisitos..."
    
    # Verificar minikube
    if ! command -v minikube &> /dev/null; then
        print_message "$RED" "Minikube não encontrado. Por favor, instale o Minikube."
        print_message "$YELLOW" "Instruções: https://minikube.sigs.k8s.io/docs/start/"
        exit 1
    fi
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        print_message "$RED" "Kubectl não encontrado. Por favor, instale o Kubectl."
        print_message "$YELLOW" "Instruções: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        exit 1
    fi
    
    print_message "$GREEN" "Todos os pré-requisitos estão instalados."
}

# Iniciar cluster minikube
start_minikube() {
    print_message "$BLUE" "Iniciando cluster Minikube..."
    
    # Verificar se o minikube já está em execução
    if minikube status | grep -q "Running"; then
        print_message "$YELLOW" "Minikube já está em execução. Deseja reiniciar? (s/n)"
        read -r answer
        if [[ "$answer" =~ ^[Ss]$ ]]; then
            print_message "$YELLOW" "Excluindo cluster Minikube existente..."
            minikube delete
        else
            print_message "$YELLOW" "Mantendo o cluster existente. Verifique se os recursos estão adequados para o experimento."
            return 0
        fi
    fi
    
    # Iniciar o cluster com recursos adequados para o experimento de "noisy neighbors"
    print_message "$GREEN" "Iniciando novo cluster Minikube com $CPUS CPUs e $MEMORY de RAM..."
    
    minikube start \
        --driver=docker \
        --cpus=$CPUS \
        --memory=$MEMORY \
        --disk-size=$DISK_SIZE \
        --kubernetes-version=v1.24.0 \
        --feature-gates="StartupProbe=true" \
        --extra-config=kubelet.eviction-hard="memory.available<500Mi,nodefs.available<10%,nodefs.inodesFree<5%" \
        --extra-config=scheduler.bind-utilization-above-watermark=true

    # Verificar se o minikube iniciou com sucesso
    if [ $? -ne 0 ]; then
        print_message "$RED" "Falha ao iniciar o Minikube. Tente ajustar os recursos conforme disponível em seu sistema."
        print_message "$YELLOW" "Você pode tentar com menos recursos: ./setup-minikube.sh --limited"
        exit 1
    fi
    
    print_message "$GREEN" "Cluster Minikube iniciado com sucesso!"
}

# Habilitar addons necessários
enable_addons() {
    print_message "$BLUE" "Habilitando addons necessários..."
    
    minikube addons enable metrics-server
    minikube addons enable dashboard
    minikube addons enable ingress
    minikube addons enable storage-provisioner
    
    print_message "$GREEN" "Addons habilitados com sucesso!"
}

# Criar namespaces para o experimento
create_namespaces() {
    print_message "$BLUE" "Criando namespaces para o experimento..."
    
    kubectl create namespace tenant-a 2>/dev/null || true
    kubectl create namespace tenant-b 2>/dev/null || true
    kubectl create namespace tenant-c 2>/dev/null || true
    kubectl create namespace tenant-d 2>/dev/null || true
    kubectl create namespace monitoring 2>/dev/null || true
    kubectl create namespace ingress-nginx 2>/dev/null || true
    
    print_message "$GREEN" "Namespaces criados com sucesso!"
}

# Aplicar labels aos namespaces para identificar os tenants
apply_namespace_labels() {
    print_message "$BLUE" "Aplicando labels aos namespaces..."
    
    kubectl label namespace tenant-a tenant=network-sensitive --overwrite
    kubectl label namespace tenant-b tenant=noisy-neighbor --overwrite
    kubectl label namespace tenant-c tenant=memory-sensitive --overwrite
    kubectl label namespace tenant-d tenant=cpu-disk-sensitive --overwrite
    kubectl label namespace monitoring purpose=observability --overwrite
    kubectl label namespace ingress-nginx purpose=ingress --overwrite
    
    print_message "$GREEN" "Labels aplicados com sucesso!"
}

# Verificar status do cluster
check_cluster_status() {
    print_message "$BLUE" "Verificando status do cluster..."
    
    minikube status
    kubectl cluster-info
    kubectl get nodes -o wide
    kubectl get namespaces
    
    print_message "$GREEN" "Cluster está pronto para o experimento!"
}

# Mostrar instruções finais
show_instructions() {
    print_message "$BLUE" "=== PRÓXIMOS PASSOS ==="
    print_message "$YELLOW" "1. Instale o Prometheus e Grafana:"
    echo "   ./install-prom-operator.sh"
    
    print_message "$YELLOW" "2. Instale o NGINX Ingress Controller:"
    echo "   ./install-nginx-controller.sh"
    
    print_message "$YELLOW" "3. Aplique as quotas de recursos:"
    echo "   kubectl apply -f manifests/namespace/resource-quotas.yaml"
    
    print_message "$YELLOW" "4. Execute o experimento:"
    if [ "$LIMITED_RESOURCES" = true ]; then
        echo "   ./run-experiment.sh --limited-resources"
        print_message "$YELLOW" "IMPORTANTE: Como você está usando recursos limitados, certifique-se de ajustar"
        print_message "$YELLOW" "os recursos nos manifestos de deployment dos tenants ou use a flag --limited-resources"
    else
        echo "   ./run-experiment.sh"
    fi
    
    print_message "$YELLOW" "5. Para acessar o Grafana (após instalação):"
    echo "   kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80"
    echo "   Acesse: http://localhost:3000 (usuário: admin, senha: admin)"
    
    print_message "$GREEN" "Seu ambiente de laboratório para estudar o efeito 'noisy neighbors' está configurado!"
}

# Função principal
main() {
    print_message "$BLUE" "=== CONFIGURAÇÃO DO CLUSTER KUBERNETES PARA EXPERIMENTO DE NOISY NEIGHBORS ==="
    
    check_prerequisites
    start_minikube
    enable_addons
    create_namespaces
    apply_namespace_labels
    check_cluster_status
    show_instructions
}

# Executar função principal
main
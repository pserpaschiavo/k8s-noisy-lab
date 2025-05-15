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
# Atualizando a versão do Kubernetes para ser mais compatível com kubectl 1.33.0
K8S_VERSION="v1.32.0"  # Versão mais compatível com kubectl 1.33.0
MINIKUBE_TIMEOUT=600   # Timeout em segundos (10 minutos)
FORCE_DELETE=false     # Flag para forçar exclusão do cluster existente
CNI_PLUGIN="flannel"   # CNI padrão, mais compatível com Kata Containers

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
    print_message "$BLUE" "  --k8s-version VERSION  Define a versão do Kubernetes (padrão: ${K8S_VERSION})"
    print_message "$BLUE" "  --timeout SECONDS      Define o timeout para inicialização do Minikube (padrão: ${MINIKUBE_TIMEOUT}s)"
    print_message "$BLUE" "  --cni PLUGIN           Define o CNI a ser usado (padrão: $CNI_PLUGIN, opções: flannel, calico, cilium)"
    print_message "$BLUE" "  -f, --force            Força a exclusão do cluster existente antes de criar um novo"
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
        -f|--force)
            FORCE_DELETE=true
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
        --k8s-version)
            K8S_VERSION="$2"
            shift 2
            ;;
        --timeout)
            MINIKUBE_TIMEOUT="$2"
            shift 2
            ;;
        --cni)
            CNI_PLUGIN="$2"
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
    
    # Verificar a versão do kubectl e sugerir versão apropriada do Kubernetes
    kubectl_version=$(kubectl version --client -o json 2>/dev/null | grep -oP '(?<="gitVersion": ")[^"]*' || kubectl version --client --short 2>/dev/null | awk '{print $3}')
    print_message "$GREEN" "Versão do kubectl detectada: $kubectl_version"
    
    # Extrair apenas os números de versão para comparação simples
    kubectl_major=$(echo $kubectl_version | cut -d. -f1 | tr -d 'v')
    kubectl_minor=$(echo $kubectl_version | cut -d. -f2)
    
    # Sugerir versão do Kubernetes com base no kubectl
    if [[ $kubectl_major -eq 1 ]]; then
        if [[ $kubectl_minor -eq 33 ]]; then
            # Para kubectl 1.33.x, recomendamos K8s 1.32.x para melhor compatibilidade
            SUGGESTED_K8S="v1.32.0"
        elif [[ $kubectl_minor -eq 32 ]]; then
            SUGGESTED_K8S="v1.28.10"
        elif [[ $kubectl_minor -eq 31 ]]; then
            SUGGESTED_K8S="v1.27.4"
        elif [[ $kubectl_minor -eq 30 ]]; then
            SUGGESTED_K8S="v1.26.7"
        fi
    fi
    
    # Se foi detectada uma versão recomendada e não foi explicitamente definida pelo usuário
    if [[ -n "$SUGGESTED_K8S" ]]; then
        if [[ "$K8S_VERSION" != "$SUGGESTED_K8S" ]]; then
            print_message "$YELLOW" "Versão sugerida do Kubernetes para kubectl $kubectl_version: $SUGGESTED_K8S"
            print_message "$YELLOW" "Você está usando: $K8S_VERSION"
            read -p "Deseja usar a versão recomendada $SUGGESTED_K8S? (s/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Ss]$ ]]; then
                K8S_VERSION=$SUGGESTED_K8S
                print_message "$GREEN" "Usando versão do Kubernetes: $K8S_VERSION"
            fi
        fi
    fi
    
    print_message "$GREEN" "Versão do Kubernetes a ser usada: $K8S_VERSION"
    
    # Verificar se Docker está funcionando
    if ! docker info &>/dev/null; then
        print_message "$RED" "Docker não está em execução ou o usuário atual não tem permissões."
        print_message "$YELLOW" "Verifique se o Docker está instalado e em execução, ou execute este script como root/sudo."
        exit 1
    fi
    
    print_message "$GREEN" "Todos os pré-requisitos estão instalados."
}

# Iniciar cluster minikube
start_minikube() {
    print_message "$BLUE" "Iniciando cluster Minikube..."
    
    # Verificar se o minikube já está em execução
    if minikube status &>/dev/null; then
        if [ "$FORCE_DELETE" = true ]; then
            print_message "$YELLOW" "Excluindo cluster Minikube existente (modo forçado)..."
            minikube delete
        else
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
    fi
    
    # Iniciar o cluster com recursos adequados para o experimento de "noisy neighbors"
    print_message "$GREEN" "Iniciando novo cluster Minikube com $CPUS CPUs, $MEMORY de RAM e versão Kubernetes $K8S_VERSION..."
    
    # Adicionar variável de ambiente para aumentar o timeout do Docker
    export DOCKER_LAUNCH_TIMEOUT=600

    # Usar timeout para evitar ficar preso indefinidamente
    print_message "$YELLOW" "Configurado timeout de $MINIKUBE_TIMEOUT segundos para inicialização..."
    
    # Verificar qual driver é mais apropriado
    DRIVER="docker"
    print_message "$GREEN" "Usando driver: $DRIVER"
    
    # Determinar o cgroup driver do Docker
    DOCKER_CGROUP_DRIVER=$(docker info 2>/dev/null | grep "Cgroup Driver" | awk '{print $3}')
    print_message "$GREEN" "Docker Cgroup Driver detectado: $DOCKER_CGROUP_DRIVER"
    
    # Garantir que não haverá um downgrade tentando iniciar
    minikube delete >/dev/null 2>&1 || true
    sleep 2
    
    # Comando de inicialização do minikube com timeout
    print_message "$YELLOW" "Iniciando Minikube com configurações otimizadas..."

    print_message "$GREEN" "Usando CNI: $CNI_PLUGIN"
    timeout $MINIKUBE_TIMEOUT minikube start \
        --driver=$DRIVER \
        --cpus=$CPUS \
        --memory=$MEMORY \
        --disk-size=$DISK_SIZE \
        --kubernetes-version=$K8S_VERSION \
        --cni=$CNI_PLUGIN \
        --driver=docker \
        --container-runtime=containerd \
        --bootstrapper=kubeadm \
        --extra-config=kubelet.cpu-manager-policy=static \
        --extra-config=kubelet.housekeeping-interval=5s \
        --extra-config=kubelet.system-reserved=cpu=1,memory=2Gi \
        --extra-config=apiserver.enable-admission-plugins=ResourceQuota,LimitRanger \
        --extra-config=kubelet.eviction-hard="memory.available<500Mi,nodefs.available<10%,nodefs.inodesFree<5%" \
        --extra-config=kubelet.cgroup-driver=$DOCKER_CGROUP_DRIVER \
    
    
    local result=$?
    if [ $result -eq 124 ]; then
        print_message "$RED" "Timeout atingido após $MINIKUBE_TIMEOUT segundos. O Minikube está demorando muito para iniciar."
        print_message "$YELLOW" "Tentando abordagem alternativa..."
        
        # Tentar com mais memória e menos recursos
        print_message "$YELLOW" "Tentando com configuração mais leve..."
        minikube delete >/dev/null 2>&1 || true
        sleep 2
        
        minikube start \
            --driver=$DRIVER \
            --cpus=4 \
            --memory=8g \
            --disk-size=$DISK_SIZE \
            --kubernetes-version=$K8S_VERSION
            
        if [ $? -ne 0 ]; then
            print_message "$RED" "Tentativa com configurações reduzidas também falhou."
            print_message "$YELLOW" "Tente manualmente com: minikube start --kubernetes-version=$K8S_VERSION"
            exit 1
        else
            print_message "$GREEN" "Minikube iniciado com configurações reduzidas."
        fi
    elif [ $result -ne 0 ]; then
        print_message "$RED" "Falha ao iniciar o Minikube. Código de erro: $result"
        print_message "$YELLOW" "Tentando com versão alternativa do Kubernetes..."
        
        # Tentar com outra versão mais antiga como fallback
        local FALLBACK_VERSION="v1.25.0"
        print_message "$YELLOW" "Tentando com versão de fallback do Kubernetes: $FALLBACK_VERSION"
        
        minikube delete >/dev/null 2>&1 || true
        sleep 2
        
        minikube start \
            --driver=$DRIVER \
            --cpus=$CPUS \
            --memory=$MEMORY \
            --disk-size=$DISK_SIZE \
            --kubernetes-version=$FALLBACK_VERSION
            
        if [ $? -ne 0 ]; then
            print_message "$RED" "Todas as tentativas falharam. Tente manualmente com:"
            print_message "$YELLOW" "minikube start --kubernetes-version=$FALLBACK_VERSION"
            exit 1
        else
            print_message "$GREEN" "Minikube iniciado com versão alternativa do Kubernetes: $FALLBACK_VERSION"
            K8S_VERSION=$FALLBACK_VERSION
        fi
    fi
    
    print_message "$GREEN" "Cluster Minikube iniciado com sucesso!"
}

# Habilitar addons necessários
enable_addons() {
    print_message "$BLUE" "Habilitando addons necessários..."
    
    minikube addons enable metrics-server || true
    minikube addons enable storage-provisioner || true
    
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
    print_message "$GREEN" "Versão do Kubernetes em uso: $K8S_VERSION"
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
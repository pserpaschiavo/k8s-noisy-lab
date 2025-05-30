#!/bin/bash

set -eo pipefail

# Diretório base
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Import logging library
source "$BASE_DIR/lib/logger.sh"

# Initialize logger with default log file
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
init_logger "$LOG_DIR/kata-containers-setup-$(date +%Y%m%d-%H%M%S).log"

# Configurações padrão (alinhadas com setup-minikube.sh)
CPUS=8
MEMORY=16g
DISK_SIZE=40g
LIMITED_RESOURCES=false
K8S_VERSION="v1.32.0"
KATA_SETUP_TIMEOUT=600  # Timeout em segundos (10 minutos)
FORCE_SETUP=false       # Flag para forçar reinstalação do Kata
USE_KATA_DEPLOY=true    # Usar kata-deploy para instalação (recomendado)
CNI_PLUGIN="flannel"    # CNI compatível com Kata Containers

# Cores para output (alinhadas com setup-minikube.sh)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de ajuda
show_help() {
    echo -e "${BLUE}Uso: $0 [opções]${NC}"
    echo
    echo -e "${BLUE}Este script configura Kata Containers no Minikube para experimentos de isolamento.${NC}"
    echo
    echo -e "${BLUE}Opções:${NC}"
    echo -e "${BLUE}  -h, --help             Mostra esta ajuda${NC}"
    echo -e "${BLUE}  -l, --limited          Usa configuração para recursos limitados (4 CPUs, 8GB RAM)${NC}"
    echo -e "${BLUE}  --cpus NUM             Define o número de CPUs (padrão: $CPUS)${NC}"
    echo -e "${BLUE}  --memory SIZE          Define a quantidade de memória (padrão: $MEMORY)${NC}"
    echo -e "${BLUE}  --disk SIZE            Define o tamanho do disco (padrão: $DISK_SIZE)${NC}"
    echo -e "${BLUE}  --k8s-version VERSION  Define a versão do Kubernetes (padrão: ${K8S_VERSION})${NC}"
    echo -e "${BLUE}  --timeout SECONDS      Define o timeout para configuração (padrão: ${KATA_SETUP_TIMEOUT}s)${NC}"
    echo -e "${BLUE}  --cni PLUGIN           Define o CNI a ser usado (padrão: $CNI_PLUGIN, opções: flannel, cilium)${NC}" 
    echo -e "${BLUE}  --manual-setup         Usa instalação manual em vez do kata-deploy${NC}"
    echo -e "${BLUE}  -f, --force            Força a reinstalação do Kata Containers${NC}"
}

# Function to check if required tools are installed
check_requirements() {
  log_info "Verificando pré-requisitos..."
  
  # Check if minikube is installed
  if ! command -v minikube &> /dev/null; then
    log_error "minikube não está instalado. Por favor, instale-o primeiro."
    return 1
  fi
  
  # Check if kubectl is installed
  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl não está instalado. Por favor, instale-o primeiro."
    return 1
  fi
  
  # Verificar suporte à virtualização aninhada
  if [ -f "/sys/module/kvm_intel/parameters/nested" ]; then
    NESTED=$(cat /sys/module/kvm_intel/parameters/nested)
    if [ "$NESTED" != "Y" ] && [ "$NESTED" != "1" ]; then
        log_warning "Virtualização aninhada não está habilitada para kvm_intel."
        log_warning "Consulte: https://www.linux-kvm.org/page/Nested_Guests"
        log_warning "Kata Containers pode não funcionar corretamente."
    else
        log_info "Virtualização aninhada habilitada para kvm_intel: $NESTED"
    fi
  elif [ -f "/sys/module/kvm_amd/parameters/nested" ]; then
    NESTED=$(cat /sys/module/kvm_amd/parameters/nested)
    if [ "$NESTED" != "Y" ] && [ "$NESTED" != "1" ]; then
        log_warning "Virtualização aninhada não está habilitada para kvm_amd."
        log_warning "Consulte: https://www.linux-kvm.org/page/Nested_Guests"
        log_warning "Kata Containers pode não funcionar corretamente."
    else
        log_info "Virtualização aninhada habilitada para kvm_amd: $NESTED"
    fi
  else
    log_warning "Não foi possível determinar o suporte à virtualização aninhada."
  fi
  
  # Verificar Git para kata-deploy
  if [ "$USE_KATA_DEPLOY" = true ] && ! command -v git &> /dev/null; then
      log_error "Git não encontrado, necessário para kata-deploy. Por favor, instale o Git."
      return 1
  fi
  
  log_success "Pré-requisitos verificados com sucesso."
  return 0
}

# Configurar/reiniciar o Minikube para uso com Kata Containers
setup_minikube() {
  log_info "Configurando Minikube para Kata Containers..."
  
  # Parar minikube se estiver em execução e --force está ativo
  if minikube status &>/dev/null; then
      if [ "$FORCE_SETUP" = true ]; then
          log_warning "Parando minikube para reconfiguração forçada..."
          minikube stop || true
      else
          log_warning "Minikube já está em execução."
          log_warning "Use a flag --force para forçar a reconfiguração."
          log_warning "Continuando com a configuração atual do Minikube."
          return 0
      fi
  fi
  
  # Configurar minikube para usar containerd
  log_info "Configurando minikube para usar containerd..."
  minikube config set container-runtime containerd
  
  # Converter memória para MB para o minikube se estiver em formato Xg
  if [[ $MEMORY =~ ^([0-9]+)g$ ]]; then
      MEMORY_MB=$((${BASH_REMATCH[1]} * 1024))
  else
      MEMORY_MB=$MEMORY
  fi
  
  # Verificar memória mínima para Kata (6GB)
  if [ "$MEMORY_MB" -lt 6144 ]; then
      log_warning "Memória configurada ($MEMORY) é menor que o mínimo recomendado (6GB) para Kata Containers."
      log_warning "Aumentando para 6GB (6144MB)."
      MEMORY_MB=6144
  fi
  
  # Obter o driver de cgroup do Docker para maior consistência
  if command -v docker &>/dev/null && docker info &>/dev/null; then
      DOCKER_CGROUP_DRIVER=$(docker info 2>/dev/null | grep "Cgroup Driver" | awk '{print $3}')
      log_info "Docker Cgroup Driver detectado: $DOCKER_CGROUP_DRIVER"
  else
      DOCKER_CGROUP_DRIVER="systemd"
      log_warning "Docker não detectado. Usando Cgroup Driver padrão: $DOCKER_CGROUP_DRIVER"
  fi
  
  # Iniciar o Minikube com parâmetros otimizados para Kata Containers
  log_info "Iniciando Minikube com configurações para Kata Containers..."
  log_info "Recursos: $CPUS CPUs, ${MEMORY_MB}MB RAM, $DISK_SIZE disco"
  log_info "CNI: $CNI_PLUGIN, Runtime: containerd"
  
  minikube start \
    --memory=${MEMORY_MB} \
    --cpus=${CPUS} \
    --disk-size=${DISK_SIZE} \
    --kubernetes-version=${K8S_VERSION} \
    --driver=docker \
    --cni=${CNI_PLUGIN} \
    --container-runtime=containerd \
    --bootstrapper=kubeadm \
    --image-mirror-country='cn' \
    --extra-config=kubelet.cpu-manager-policy=static \
    --extra-config=kubelet.housekeeping-interval=5s \
    --extra-config=kubelet.system-reserved=cpu=1,memory=2Gi \
    --extra-config=apiserver.enable-admission-plugins=ResourceQuota,LimitRanger
  
  # Verificar se o minikube iniciou corretamente
  if ! minikube status &>/dev/null; then
      log_error "Falha ao iniciar o Minikube. Verifique os logs para detalhes."
      return 1
  fi
  
  # Verificar se a virtualização está habilitada dentro do Minikube (adaptado para driver docker)
  # Como estamos usando o driver Docker, verificamos se o Docker está executando e tem suporte a virtualização
  if ! docker info 2>/dev/null | grep -q "Operating System"; then
      log_error "Docker não parece estar funcionando corretamente."
      log_error "O Kata Containers pode não funcionar corretamente."
      return 1
  fi
  
  log_info "Usando driver Docker para Minikube, a virtualização aninhada depende do host."
  
  log_success "Minikube configurado e pronto para Kata Containers."
  return 0
}

# Instalar Kata Containers usando kata-deploy (método oficial)
install_kata_with_katadeploy() {
  log_info "Instalando Kata Containers usando kata-deploy (método oficial)..."
  
  # Criar diretório temporário e fazer clone do repo do Kata
  local KATA_TEMP_DIR="/tmp/kata-containers-setup-$$"
  mkdir -p "$KATA_TEMP_DIR"
  
  log_info "Clonando repositório do Kata Containers..."
  git clone -q https://github.com/kata-containers/kata-containers.git "$KATA_TEMP_DIR" || {
      log_error "Falha ao clonar o repositório do Kata Containers."
      rm -rf "$KATA_TEMP_DIR"
      return 1
  }
  
  # Instalar componentes RBAC e kata-deploy
  log_info "Aplicando componentes RBAC e kata-deploy..."
  kubectl apply -f "$KATA_TEMP_DIR/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml" || {
      log_error "Falha ao aplicar kata-rbac.yaml."
      rm -rf "$KATA_TEMP_DIR"
      return 1
  }
  
  kubectl apply -f "$KATA_TEMP_DIR/tools/packaging/kata-deploy/kata-deploy/base/kata-deploy.yaml" || {
      log_error "Falha ao aplicar kata-deploy.yaml."
      rm -rf "$KATA_TEMP_DIR"
      return 1
  }
  
  # Aguardar a conclusão do kata-deploy
  log_info "Aguardando kata-deploy concluir a instalação (isso pode levar alguns minutos)..."
  
  # Esperar até que o pod kata-deploy esteja em execução
  local timeout=300
  local start_time=$(date +%s)
  local pod_running=false
  
  while true; do
      if kubectl -n kube-system get pods | grep -q "kata-deploy.*Running"; then
          pod_running=true
          break
      fi
      
      current_time=$(date +%s)
      elapsed=$((current_time - start_time))
      
      if [ $elapsed -gt $timeout ]; then
          log_error "Timeout aguardando pod kata-deploy iniciar."
          rm -rf "$KATA_TEMP_DIR"
          return 1
      fi
      
      log_warning "Aguardando pod kata-deploy iniciar... ($elapsed segundos)"
      sleep 10
  done
  
  # Verificar se o kata-deploy está concluído (executando sleep infinity)
  if [ "$pod_running" = true ]; then
      local podname=$(kubectl -n kube-system get pods -o=name | grep -F kata-deploy | sed 's?pod/??')
      local timeout=300
      local start_time=$(date +%s)
      
      while true; do
          if kubectl -n kube-system exec $podname -- ps -ef | grep -q "sleep infinity"; then
              log_success "kata-deploy concluído com sucesso!"
              break
          fi
          
          current_time=$(date +%s)
          elapsed=$((current_time - start_time))
          
          if [ $elapsed -gt $timeout ]; then
              log_error "Timeout aguardando kata-deploy concluir."
              rm -rf "$KATA_TEMP_DIR"
              return 1
          fi
          
          log_warning "Ainda instalando... ($elapsed segundos)"
          sleep 10
      done
  fi
  
  # Registrar a RuntimeClass para Kata Containers
  log_info "Registrando RuntimeClass para Kata Containers..."
  kubectl apply -f "$KATA_TEMP_DIR/tools/packaging/kata-deploy/runtimeclasses/kata-runtimeClasses.yaml" || {
      log_error "Falha ao registrar RuntimeClass do Kata."
      rm -rf "$KATA_TEMP_DIR"
      return 1
  }
  
  # Limpar diretório temporário
  rm -rf "$KATA_TEMP_DIR"
  
  log_success "Kata Containers instalado com sucesso usando kata-deploy!"
  return 0
}

# Instalar Kata Containers manualmente (alternativa)
setup_kata_containers() {
  log_info "Instalando Kata Containers manualmente..."
  
  # Install kata-containers in minikube
  log_info "Instalando Kata Containers no minikube..."
  minikube ssh "sudo apt-get update && sudo apt-get install -y kata-runtime"
  
  # Configure containerd to use Kata Containers
  log_info "Configurando containerd para usar Kata Containers..."
  minikube ssh "sudo mkdir -p /etc/containerd"
  
  # Obter o driver de cgroup do Docker para maior consistência
  if command -v docker &>/dev/null && docker info &>/dev/null; then
      DOCKER_CGROUP_DRIVER=$(docker info 2>/dev/null | grep "Cgroup Driver" | awk '{print $3}')
      log_info "Docker Cgroup Driver detectado: $DOCKER_CGROUP_DRIVER"
  else
      DOCKER_CGROUP_DRIVER="systemd"
      log_warning "Docker não detectado. Usando Cgroup Driver padrão: $DOCKER_CGROUP_DRIVER"
  fi
  
  # Create containerd configuration with Kata support
  minikube ssh "cat << EOF | sudo tee /etc/containerd/config.toml
version = 2
[plugins]
  [plugins.\"io.containerd.grpc.v1.cri\"]
    systemd_cgroup = $([ "$DOCKER_CGROUP_DRIVER" = "systemd" ] && echo "true" || echo "false")
    [plugins.\"io.containerd.grpc.v1.cri\".containerd]
      default_runtime_name = \"runc\"
      [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes]
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runc]
          runtime_type = \"io.containerd.runc.v2\"
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.kata]
          runtime_type = \"io.containerd.kata.v2\"
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.kata-qemu]
          runtime_type = \"io.containerd.kata.v2\"
EOF"
  
  # Restart containerd
  log_info "Restarting containerd service..."
  minikube ssh "sudo systemctl restart containerd"
  
  # Verificar se containerd está executando
  sleep 10
  if ! minikube ssh "systemctl is-active --quiet containerd"; then
      log_error "containerd não está executando após reinicialização."
      return 1
  fi
  
  # Create RuntimeClass for Kata Containers
  log_info "Creating RuntimeClass for Kata Containers..."
  cat << EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata
EOF
  
  # Criar também a RuntimeClass kata-qemu para compatibilidade com o kata-deploy
  cat << EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-qemu
handler: kata
EOF
  
  return 0
}

# Verificar a instalação do Kata Containers
verify_kata_installation() {
  log_info "Verificando a instalação do Kata Containers..."
  
  # Verificar se as RuntimeClasses existem
  if ! kubectl get runtimeclass kata &>/dev/null; then
      log_error "RuntimeClass 'kata' não encontrada."
      return 1
  fi
  
  if ! kubectl get runtimeclass kata-qemu &>/dev/null; then
      log_warning "RuntimeClass 'kata-qemu' não encontrada. Alguns exemplos podem não funcionar."
  fi
  
  # Criar pod de teste para verificar
  log_info "Criando pod de teste com Kata Containers..."
  
  # Remover o pod de teste anterior se existir
  kubectl delete pod kata-test &>/dev/null || true
  
  # Criar o pod de teste
  cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: kata-test
spec:
  runtimeClassName: kata
  containers:
  - name: nginx
    image: nginx:latest
EOF
  
  # Aguardar o pod iniciar
  log_info "Aguardando pod iniciar (isso pode levar alguns segundos)..."
  kubectl wait --for=condition=Ready pod/kata-test --timeout=120s || {
      log_error "O pod de teste não iniciou no tempo esperado."
      kubectl describe pod kata-test
      kubectl delete pod kata-test &>/dev/null || true
      return 1
  }
  
  # Verificar se há processos QEMU em execução (indicando VM do Kata)
  local qemu_procs=$(minikube ssh "pgrep -c qemu" || echo "0")
  if [ "$qemu_procs" -eq "0" ]; then
      log_error "Não foram encontrados processos QEMU. O pod pode não estar usando Kata Containers."
      kubectl delete pod kata-test &>/dev/null || true
      return 1
  fi
  
  # Comparar kernel do host vs. kernel do contêiner
  local host_kernel=$(minikube ssh "uname -r")
  local pod_kernel=$(kubectl exec kata-test -- uname -r)
  
  if [ "$host_kernel" = "$pod_kernel" ]; then
      log_error "O kernel no pod é o mesmo do host ($host_kernel)."
      log_error "Isso indica que o pod NÃO está executando em uma VM Kata."
      kubectl delete pod kata-test &>/dev/null || true
      return 1
  fi
  
  log_info "Kernel do host: $host_kernel"
  log_info "Kernel do pod Kata: $pod_kernel"
  log_success "Verificação bem-sucedida: o pod está executando em uma VM Kata!"
  
  # Limpar o pod de teste
  kubectl delete pod kata-test
  
  log_success "Verificação concluída: Kata Containers configurado corretamente."
  return 0
}

# Function to create an example deployment using kata containers
create_example_deployment() {
  mkdir -p manifests/kata-containers
  
  cat << EOF > manifests/kata-containers/example-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kata-example
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kata-example
  template:
    metadata:
      labels:
        app: kata-example
    spec:
      runtimeClassName: kata
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          limits:
            cpu: "0.5"
            memory: "256Mi"
          requests:
            cpu: "0.2"
            memory: "128Mi"
        ports:
        - containerPort: 80
EOF
  
  log_info "Example deployment created at manifests/kata-containers/example-deployment.yaml"
  log_info "To deploy it, run: kubectl apply -f manifests/kata-containers/example-deployment.yaml"
}

# Processar argumentos da linha de comando
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
            FORCE_SETUP=true
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
            KATA_SETUP_TIMEOUT="$2"
            shift 2
            ;;
        --cni)
            CNI_PLUGIN="$2"
            shift 2
            ;;
        --manual-setup)
            USE_KATA_DEPLOY=false
            shift
            ;;
        *)
            log_error "Opção desconhecida: $1"
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
    log_warning "Usando configuração para recursos limitados: $CPUS CPUs, $MEMORY RAM, $DISK_SIZE disco"
else
    # Se não estiver usando recursos limitados, garantir memória mínima para Kata (6GB)
    if [[ $MEMORY =~ ^([0-9]+)g$ ]] && [ ${BASH_REMATCH[1]} -lt 6 ]; then
        log_warning "Aumentando memória para o mínimo recomendado para Kata Containers: 6g"
        MEMORY="6g"
    fi
    log_info "Usando configuração: $CPUS CPUs, $MEMORY RAM, $DISK_SIZE disco"
fi

# Função principal
main() {
    log_info "==============================================" 
    log_info "Configuração do Kata Containers com Minikube"
    log_info "=============================================="
    
    # Criar diretório temporário para download e cleanup
    local KATA_TEMP_DIR="/tmp/kata-containers-setup-$$"
    mkdir -p "$KATA_TEMP_DIR"

    # Garantir limpeza do diretório temporário na saída
    trap "rm -rf \"$KATA_TEMP_DIR\"" EXIT
    
    # Verificar pré-requisitos
    if ! check_requirements; then
        log_error "Falha em verificar pré-requisitos. Abortando."
        exit 1
    fi
    
    # Verificar se já existe RuntimeClass do Kata
    if kubectl get runtimeclass kata &>/dev/null && [ "$FORCE_SETUP" = false ]; then
        log_warning "RuntimeClass 'kata' já existe no cluster."
        log_warning "Para reinstalar, use a flag --force."
        
        # Verificar a instalação
        if verify_kata_installation; then
            log_success "Kata Containers já está instalado e funcionando corretamente!"
            log_success "Para executar experimentos, use: ./run-kata-experiment.sh"
            exit 0
        else
            log_warning "Instalação existente de Kata não está funcionando corretamente."
            log_warning "Forçando reinstalação..."
            FORCE_SETUP=true
        fi
    fi
    
    # Configurar/reiniciar minikube
    if ! setup_minikube; then
        log_error "Falha na configuração do Minikube. Abortando."
        exit 1
    fi
    
    # Instalar Kata Containers
    if [ "$USE_KATA_DEPLOY" = true ]; then
        if ! install_kata_with_katadeploy; then
            log_warning "Falha na instalação do Kata Containers com kata-deploy."
            log_warning "Tentando instalação manual..."
            if ! setup_kata_containers; then
                log_error "Falha também na instalação manual. Abortando."
                exit 1
            fi
        fi
    else
        if ! setup_kata_containers; then
            log_error "Falha na instalação manual do Kata Containers. Abortando."
            exit 1
        fi
    fi
    
    # Verificar a instalação
    if ! verify_kata_installation; then
        log_error "Verificação da instalação falhou. O Kata Containers pode não funcionar corretamente."
        exit 1
    fi
    
    # Criar exemplo de deployment
    create_example_deployment
    
    log_success "Configuração do Kata Containers concluída com sucesso!"
    log_success "Para executar experimentos, use: ./run-kata-experiment.sh"
}

# Definir uma função de limpeza em caso de timeout
cleanup_on_timeout() {
    log_error "Timeout de $KATA_SETUP_TIMEOUT segundos atingido durante a configuração."
    log_error "Verifique se há problemas com a instalação do Kata Containers."
    exit 1
}

# Registrar trap para o SIGALRM
trap cleanup_on_timeout ALRM

# Configurar o timeout usando o SIGALRM
( sleep $KATA_SETUP_TIMEOUT && kill -ALRM $$ ) &
TIMEOUT_PID=$!

# Executar a função main
main

# Cancelar o timeout se chegamos aqui
kill $TIMEOUT_PID 2>/dev/null || true

exit 0

#!/bin/bash
# filepath: /home/phil/Projects/k8s-noisy-lab/setup-minikube.sh

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NO_COLOR='\033[0m'

echo -e "${GREEN}Configurando Minikube para o experimento de noisy neighbours...${NO_COLOR}"

# Parar o Minikube se estiver rodando
if minikube status &>/dev/null; then
  echo -e "${BLUE}Parando o Minikube existente...${NO_COLOR}"
  minikube stop
  minikube delete
fi

echo "🧹 Limpando perfil antigo (se existir)…"
minikube delete --all || true


echo "🚀 Iniciando Minikube (${K8S_VERSION})…"
minikube start \
  --profile="noisy-lab" \
  --kubernetes-version="1.32.0" \
  --cpus=4 \
  --memory=6g \
  --disk-size=20gb \
  --driver=docker \
  --container-runtime=containerd \
  --cni=calico \
  --bootstrapper=kubeadm \
  --extra-config=kubelet.cpu-manager-policy=static \
  --extra-config=kubelet.housekeeping-interval=5s \
  --extra-config=kubelet.system-reserved=cpu=400m,memory=400Mi \
  --extra-config=apiserver.enable-admission-plugins=ResourceQuota,LimitRanger,NodeRestriction \
  --extra-config=kubelet.eviction-hard="memory.available<100Mi,nodefs.available<5%,nodefs.inodesFree<5%" \
  --extra-config=kubelet.authentication-token-webhook=true \
  --extra-config=kubelet.authorization-mode=Webhook


# Adicionar timer para garantir que o cluster esteja completamente inicializado
echo -e "${YELLOW}Aguardando inicialização completa do cluster (30s)...${NO_COLOR}"
sleep 15

# Aguardar até que o nó esteja Ready
echo -e "${BLUE}Esperando o nó ficar pronto...${NO_COLOR}"
kubectl wait --for=condition=Ready node -l minikube.k8s.io/name=noisy-lab --timeout=2m || {
  echo -e "${RED}Timeout esperando pelo nó. Continuando mesmo assim...${NO_COLOR}"
}

# Verificar a instalação
echo -e "${BLUE}Verificando a instalação do Kubernetes...${NO_COLOR}"
kubectl version
kubectl get nodes

# Criar namespaces para o experimento
echo -e "${BLUE}Criando namespaces para o experimento...${NO_COLOR}"
kubectl create namespace tenant-a
kubectl create namespace tenant-b
kubectl create namespace tenant-c
kubectl create namespace monitoring

echo -e "${GREEN}Minikube configurado com sucesso para o experimento noisy-neighbours!${NO_COLOR}"
echo -e "${YELLOW}Recursos alocados: 4 CPUs, 6GB RAM${NO_COLOR}"
echo -e "${YELLOW}Namespaces criados: tenant-a, tenant-b, tenant-c, monitoring${NO_COLOR}"
echo -e "${YELLOW}Addons habilitados: metrics-server, dashboard, ingress${NO_COLOR}"
echo
echo -e "${GREEN}Para executar o experimento:${NO_COLOR}"
echo -e "1. Execute: ${BLUE}bash run-experiment.sh${NO_COLOR}"
echo -e "2. Para acessar o Grafana: ${BLUE}kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80${NO_COLOR}"
echo -e "3. Para acessar o dashboard: ${BLUE}minikube dashboard${NO_COLOR}"
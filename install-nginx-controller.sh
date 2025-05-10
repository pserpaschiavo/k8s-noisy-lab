#!/bin/bash

set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NO_COLOR='\033[0m'

echo -e "${GREEN}Installing NGINX Ingress Controller...${NO_COLOR}"
# Install NGINX Ingress Controller
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true \
  --set controller.serviceMonitor.enabled=true \
  --set controller.serviceMonitor.namespace=monitoring \
  --set controller.serviceMonitor.additionalLabels.release=kube-prometheus-stack \
  --set controller.config.enable-opentracing=true \
  --set controller.config.jaeger-collector-host=jaeger-collector.monitoring.svc.cluster.local \
  --set controller.config.jaeger-sampler-type=const \
  --set controller.config.jaeger-sampler-param=1 \
  --set controller.service.annotations."prometheus\.io/scrape"="true" \
  --set controller.service.annotations."prometheus\.io/port"="10254" \
  --set controller.service.annotations."prometheus\.io/path"="/metrics" \
  --set controller.service.labels."app\.kubernetes\.io/name"="ingress-nginx" \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.additionalLabels.release=prometheus

echo -e "${ORANGE}Waiting for NGINX Ingress Controller to be ready...${NO_COLOR}"
kubectl wait --namespace ingress-nginx   --for=condition=Ready \
    pod -l app.kubernetes.io/name=ingress-nginx --timeout=120s

echo -e "${GREEN}NGINX Ingress Controller is ready!${NO_COLOR}"

# Port-forward to access the NGINX Ingress Controller
echo -e "${ORANGE}Port-forwarding to access NGINX Ingress Controller...${NO_COLOR}"
kubectl port-forward svc/ingress-nginx-controller -n ingress-nginx 8080:80
echo -e "${GREEN}NGINX Ingress Controller is accessible at http://localhost:8080${NO_COLOR}"
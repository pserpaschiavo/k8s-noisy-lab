#!/usr/bin/env bash

# Prerequisites:
# * kubectl 1.18+ points to a running K8s cluster
# * helm 3+
# * environment variables SLACK_CHANNEL and SLACK_API_URL are set

set -eo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NO_COLOR='\033[0m'

printf "%bInstalling kube-prometheus-stack...%b\n" "$GREEN" "$NO_COLOR"
# helm search repo prometheus-community/kube-prometheus-stack
KUBE_PROMETHEUS_STACK_VERSION='70.0.0'
KUBE_PROMETHEUS_STACK_NAME='prometheus'
KUBE_PROMETHEUS_STACK_NAMESPACE='monitoring'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade "$KUBE_PROMETHEUS_STACK_NAME" prometheus-community/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_VERSION" \
  --install \
  --namespace "$KUBE_PROMETHEUS_STACK_NAMESPACE" \
  --create-namespace \
  --wait \
  --set "defaultRules.create=true" \
  --set "nodeExporter.enabled=true" \
  --set "prometheus.prometheusSpec.scrapeInterval=5s" \
  --set "prometheus.prometheusSpec.retention=1d" \
  --set "prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.probeSelectorNilUsesHelmValues=false" \
  --set "prometheus.prometheusSpec.resources.requests.cpu=250m" \
  --set "prometheus.prometheusSpec.resources.requests.memory=512Mi" \
  --set "prometheus.prometheusSpec.resources.limits.cpu=500m" \
  --set "prometheus.prometheusSpec.resources.limits.memory=1Gi" \
  --set "alertmanager.alertmanagerSpec.useExistingSecret=true" \
  --set "grafana.env.GF_INSTALL_PLUGINS=flant-statusmap-panel" \
  --set "grafana.adminPassword=admin" \
  --set "kubelet.enabled=true" \
  --set "kubeScheduler.enabled=true" \
  --set "kubeControllerManager.enabled=true" \
  --set "kubeEtcd.enabled=true" \
  --set "kubeProxy.enabled=true" \
  --set "kube-state-metrics.enabled=true" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.apiVersion=1" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].name=default" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].orgId=1" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].folder=''" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].type=file" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].disableDeletion=false" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].editable=true" \
  --set "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].options.path=/var/lib/grafana/dashboards/default" \
  -f "$DIR/observability/prometheus-values.yaml"

# Apply ServiceMonitors for each tenant
printf "\n%bCreating ServiceMonitors for tenants...%b\n" "$GREEN" "$NO_COLOR"
kubectl apply -f "$DIR/observability/servicemonitors/"

# Create the noisy-neighbours dashboard in Grafana
printf "\n%bCreating Noisy Neighbours Dashboard for Grafana...%b\n" "$GREEN" "$NO_COLOR"
kubectl apply -f "$DIR/observability/grafana-dashboards/noisy-neighbours-dashboard.yaml"

# Create PrometheusRules for detecting noisy neighbours
printf "\n%bCreating PrometheusRules for noisy neighbour detection...%b\n" "$GREEN" "$NO_COLOR"
kubectl apply -f "$DIR/observability/prometheus-rules/noisy-neighbours-rules.yaml"


printf "\n%bTo open Prometheus UI execute \nkubectl -n %s port-forward svc/%s-kube-prometheus-prometheus 9090\nand open your browser at http://localhost:9090\n\n" "$GREEN" "$KUBE_PROMETHEUS_STACK_NAMESPACE" "$KUBE_PROMETHEUS_STACK_NAME"
printf "To open Grafana UI execute \nkubectl -n %s port-forward svc/%s-grafana 3000:80\nand open your browser at http://localhost:3000\nusername: admin, password: admin%b\n" "$KUBE_PROMETHEUS_STACK_NAMESPACE" "$KUBE_PROMETHEUS_STACK_NAME" "$NO_COLOR"

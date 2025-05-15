#!/bin/bash

# Import logging library
source lib/logger.sh
source lib/kubernetes.sh

# Default settings
ALL_TENANTS=false
TENANT_LIST=()
DRY_RUN=false

# Function to display help
show_help() {
  echo "Uso: $0 [opções]"
  echo
  echo "Este script aplica os manifestos do Kata Containers para os tenants especificados."
  echo
  echo "Opções:"
  echo "  -h, --help                Mostra esta ajuda"
  echo "  -a, --all                 Aplica manifestos Kata para todos os tenants"
  echo "  -t, --tenant TENANT       Aplica manifestos Kata para um tenant específico (a, b, c ou d)"
  echo "                            Pode ser usado múltiplas vezes para especificar vários tenants"
  echo "  --dry-run                 Realiza um dry-run sem aplicar os manifestos"
  echo
  echo "Exemplos:"
  echo "  $0 --all                  Aplica todos os manifestos Kata"
  echo "  $0 -t a -t c              Aplica manifestos Kata apenas para tenant-a e tenant-c"
  echo "  $0 --tenant b --dry-run   Mostra o que seria aplicado para tenant-b sem executar"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      exit 0
      ;;
    -a|--all)
      ALL_TENANTS=true
      shift
      ;;
    -t|--tenant)
      if [[ -z "$2" || ! "$2" =~ ^[a-d]$ ]]; then
        log_error "Tenant inválido. Deve ser a, b, c ou d."
        exit 1
      fi
      TENANT_LIST+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      log_error "Opção desconhecida: $1"
      show_help
      exit 1
      ;;
  esac
done

# Check if Kata Containers is set up
check_kata_setup() {
  log_info "Verificando configuração do Kata Containers..."
  
  # Check if kata runtime class exists
  if ! kubectl get runtimeclass kata &> /dev/null; then
    log_error "RuntimeClass 'kata' não encontrada. Execute setup-kata-containers.sh primeiro."
    exit 1
  fi
  
  log_success "Kata Containers está configurado corretamente."
}

# Apply namespace manifest
apply_namespace_manifest() {
  local tenant=$1
  local dry_run_flag=""
  
  if [ "$DRY_RUN" = true ]; then
    dry_run_flag="--dry-run=client"
  fi
  
  log_info "Aplicando manifesto de namespace para tenant-$tenant..."
  kubectl apply -f manifests-kata/namespace/tenant-$tenant.yaml $dry_run_flag
}

# Apply tenant manifests
apply_tenant_manifests() {
  local tenant=$1
  local dry_run_flag=""
  
  if [ "$DRY_RUN" = true ]; then
    dry_run_flag="--dry-run=client"
  fi
  
  if [ -d "manifests-kata/tenant-$tenant" ]; then
    log_info "Aplicando manifestos para tenant-$tenant..."
    kubectl apply -f manifests-kata/tenant-$tenant/ $dry_run_flag
    log_success "Manifestos de tenant-$tenant aplicados com sucesso."
  else
    log_warning "Diretório manifests-kata/tenant-$tenant não encontrado."
  fi
}

# Apply resource quotas
apply_resource_quotas() {
  local tenant=$1
  local dry_run_flag=""
  
  if [ "$DRY_RUN" = true ]; then
    dry_run_flag="--dry-run=client"
  fi
  
  log_info "Aplicando cotas de recursos para tenant-$tenant..."
  # Use yq or grep to extract only the specific tenant's quota from the file
  kubectl apply -f manifests-kata/namespace/resource-quotas.yaml $dry_run_flag
}

# Main execution
main() {
  # Show banner
  log_info "==============================================="
  log_info "  Aplicação de Manifestos do Kata Containers"
  log_info "==============================================="
  
  # Check Kata Containers setup
  check_kata_setup
  
  # Determine tenants to process
  if [ "$ALL_TENANTS" = true ]; then
    TENANT_LIST=("a" "b" "c" "d")
  fi
  
  # Check if tenant list is empty
  if [ ${#TENANT_LIST[@]} -eq 0 ]; then
    log_error "Nenhum tenant especificado. Use --all ou --tenant."
    show_help
    exit 1
  fi
  
  # Process each tenant
  for tenant in "${TENANT_LIST[@]}"; do
    log_info "Processando tenant-$tenant com Kata Containers..."
    
    # Apply namespace
    apply_namespace_manifest "$tenant"
    
    # Apply resource quotas
    apply_resource_quotas "$tenant"
    
    # Apply tenant manifests
    apply_tenant_manifests "$tenant"
    
    log_success "Tenant-$tenant configurado com Kata Containers."
    echo
  done
  
  log_success "Processo concluído."
  
  if [ "$DRY_RUN" = true ]; then
    log_info "Modo dry-run. Nenhuma alteração foi aplicada."
  else
    log_info "Para verificar os pods usando Kata Containers, execute:"
    echo "kubectl get pods -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,RUNTIME:.spec.runtimeClassName"
  fi
}

main "$@"

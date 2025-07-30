#!/bin/bash

# Script para configurar o cluster Kubernetes com ArgoCD e Jenkins
set -e

echo "🚀 Configurando ambiente Kubernetes para CI/CD"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funções auxiliares
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se kubectl está instalado
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl não está instalado. Instale primeiro!"
    exit 1
fi

# Verificar se helm está instalado
if ! command -v helm &> /dev/null; then
    log_warn "Helm não encontrado. Instalando..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 1. Criar namespaces
log_info "Criando namespaces..."
kubectl apply -f k8s/base/namespace.yaml

# 2. Instalar ingress-nginx se não existir
if ! kubectl get namespace ingress-nginx &> /dev/null; then
    log_info "Instalando NGINX Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
    
    log_info "Aguardando NGINX Ingress ficar pronto..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s
fi

# 3. Instalar cert-manager se não existir
if ! kubectl get namespace cert-manager &> /dev/null; then
    log_info "Instalando cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    log_info "Aguardando cert-manager ficar pronto..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=120s
    
    # Criar ClusterIssuer
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
fi

# 4. Instalar ArgoCD
if ! kubectl get namespace argocd &> /dev/null; then
    log_info "Instalando ArgoCD..."
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    log_info "Aguardando ArgoCD ficar pronto..."
    kubectl wait --namespace argocd \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=argocd-server \
        --timeout=300s
    
    # Aplicar configurações customizadas
    kubectl apply -f argocd/argocd-installation.yaml
    kubectl apply -f argocd/projects/app-project.yaml
    kubectl apply -f argocd/repository-secret.yaml
    kubectl apply -f argocd/applications/
    
else
    log_info "ArgoCD já está instalado. Atualizando configurações..."
    kubectl apply -f argocd/argocd-installation.yaml
    kubectl apply -f argocd/projects/app-project.yaml
    kubectl apply -f argocd/repository-secret.yaml
    kubectl apply -f argocd/applications/
fi

# 5. Instalar Prometheus e Grafana (opcional)
if [[ "${INSTALL_MONITORING:-false}" == "true" ]]; then
    log_info "Instalando stack de monitoramento..."
    
    # Adicionar repositório Helm
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Instalar kube-prometheus-stack
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set grafana.adminPassword=admin123 \
        --set alertmanager.enabled=true \
        --set prometheus.prometheusSpec.retention=30d
fi

# 6. Configurar secrets básicos
log_info "Criando secrets básicos..."

# Secret para autenticação básica (homologação)
kubectl create secret generic basic-auth \
    --from-literal=auth="$(htpasswd -nb admin admin123)" \
    --namespace app-hml \
    --dry-run=client -o yaml | kubectl apply -f -

# 7. Aplicar manifestos dos ambientes
log_info "Aplicando manifestos dos ambientes..."
kubectl apply -k k8s/dev/
kubectl apply -k k8s/hml/

# 8. Obter informações importantes
log_info "🎉 Configuração concluída!"
echo ""
echo "📋 Informações importantes:"
echo ""

# ArgoCD Password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "🔐 ArgoCD Admin Password: $ARGOCD_PASSWORD"

# URLs importantes
echo "🌐 URLs importantes:"
echo "   - ArgoCD: https://argocd.yourdomain.com"
echo "   - App Dev: https://app-dev.yourdomain.com"
echo "   - App HML: https://app-hml.yourdomain.com"

if [[ "${INSTALL_MONITORING:-false}" == "true" ]]; then
    echo "   - Grafana: https://grafana.yourdomain.com (admin/admin123)"
    echo "   - Prometheus: https://prometheus.yourdomain.com"
fi

echo ""
echo "⚠️  Lembre-se de:"
echo "   1. Atualizar os domínios nos arquivos de configuração"
echo "   2. Configurar seus DNS para apontar para o Load Balancer"
echo "   3. Configurar as credenciais no Jenkins"
echo "   4. Verificar se os secrets estão corretos"
echo ""

log_info "Para acompanhar o status dos pods:"
echo "kubectl get pods -A"
echo ""
log_info "Para fazer port-forward do ArgoCD (se necessário):"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
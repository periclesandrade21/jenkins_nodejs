#!/bin/bash

# Script para deploy manual da aplicação
set -e

# Configurações
ENVIRONMENT=${1:-dev}
IMAGE_TAG=${2:-latest}
DOCKER_REGISTRY=${DOCKER_REGISTRY:-your-registry.com}

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Validar ambiente
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "hml" ]]; then
    log_error "Ambiente deve ser 'dev' ou 'hml'"
    exit 1
fi

NAMESPACE="app-${ENVIRONMENT}"

log_info "🚀 Iniciando deploy para ambiente: $ENVIRONMENT"
log_info "📦 Tag da imagem: $IMAGE_TAG"
log_info "🏷️  Namespace: $NAMESPACE"

# 1. Verificar se o namespace existe
log_step "Verificando namespace..."
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    log_error "Namespace $NAMESPACE não existe. Execute o setup primeiro!"
    exit 1
fi

# 2. Build das imagens (se necessário)
if [[ "$BUILD_IMAGES" == "true" ]]; then
    log_step "Fazendo build das imagens..."
    
    # Backend
    log_info "Building backend image..."
    docker build -f Dockerfile.backend -t $DOCKER_REGISTRY/fastapi-backend:$IMAGE_TAG .
    docker push $DOCKER_REGISTRY/fastapi-backend:$IMAGE_TAG
    
    # Frontend
    log_info "Building frontend image..."
    docker build -f Dockerfile.frontend -t $DOCKER_REGISTRY/react-frontend:$IMAGE_TAG .
    docker push $DOCKER_REGISTRY/react-frontend:$IMAGE_TAG
fi

# 3. Aplicar configurações
log_step "Aplicando configurações do Kubernetes..."
kubectl apply -k k8s/$ENVIRONMENT/

# 4. Atualizar imagens nos deployments
log_step "Atualizando imagens nos deployments..."

kubectl set image deployment/backend-deployment \
    backend=$DOCKER_REGISTRY/fastapi-backend:$IMAGE_TAG \
    -n $NAMESPACE

kubectl set image deployment/frontend-deployment \
    frontend=$DOCKER_REGISTRY/react-frontend:$IMAGE_TAG \
    -n $NAMESPACE

# 5. Aguardar rollout
log_step "Aguardando rollout dos deployments..."

kubectl rollout status deployment/backend-deployment -n $NAMESPACE --timeout=300s
kubectl rollout status deployment/frontend-deployment -n $NAMESPACE --timeout=300s

# 6. Verificar saúde dos pods
log_step "Verificando saúde dos pods..."

# Aguardar pods ficarem prontos
kubectl wait --for=condition=ready pod \
    --selector=app=backend \
    --namespace=$NAMESPACE \
    --timeout=120s

kubectl wait --for=condition=ready pod \
    --selector=app=frontend \
    --namespace=$NAMESPACE \
    --timeout=120s

# 7. Executar smoke tests básicos
log_step "Executando smoke tests..."

# Obter URL do serviço
if [[ "$ENVIRONMENT" == "dev" ]]; then
    APP_URL="https://app-dev.yourdomain.com"
else
    APP_URL="https://app-hml.yourdomain.com"
fi

# Teste básico de conectividade
log_info "Testando conectividade com $APP_URL..."
if curl -f -s --connect-timeout 10 $APP_URL > /dev/null; then
    log_info "✅ Frontend está respondendo"
else
    log_warn "⚠️  Frontend pode não estar acessível externamente ainda"
fi

# Teste da API
API_URL="$APP_URL/api/"
log_info "Testando API em $API_URL..."
if curl -f -s --connect-timeout 10 $API_URL > /dev/null; then
    log_info "✅ API está respondendo"
else
    log_warn "⚠️  API pode não estar acessível externamente ainda"
fi

# 8. Mostrar informações finais
log_step "Informações do deploy:"

echo ""
echo "📋 Status dos recursos:"
kubectl get pods,svc,ingress -n $NAMESPACE

echo ""
echo "🌐 URLs da aplicação:"
echo "   - Frontend: $APP_URL"
echo "   - API: $API_URL"

echo ""
echo "🔍 Para acompanhar os logs:"
echo "   Backend:  kubectl logs -f deployment/backend-deployment -n $NAMESPACE"
echo "   Frontend: kubectl logs -f deployment/frontend-deployment -n $NAMESPACE"

echo ""
echo "📊 Para verificar métricas:"
echo "   kubectl top pods -n $NAMESPACE"

echo ""
log_info "✅ Deploy concluído com sucesso!"

# 9. Opcional: Sync no ArgoCD
if command -v argocd &> /dev/null && [[ "$SYNC_ARGOCD" == "true" ]]; then
    log_step "Sincronizando com ArgoCD..."
    
    APP_NAME="fastapi-react-app-$ENVIRONMENT"
    
    # Login no ArgoCD (se necessário)
    if [[ -n "$ARGOCD_SERVER" && -n "$ARGOCD_TOKEN" ]]; then
        argocd login $ARGOCD_SERVER --auth-token $ARGOCD_TOKEN --insecure
        argocd app sync $APP_NAME
        argocd app wait $APP_NAME --timeout 300
        log_info "✅ ArgoCD sincronizado"
    fi
fi
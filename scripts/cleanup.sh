#!/bin/bash

# Script para limpeza de recursos do cluster
set -e

# Configurações
ENVIRONMENT=${1:-all}
FORCE=${2:-false}

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

# Função para confirmação
confirm() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    read -p "Tem certeza? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

log_warn "🧹 Script de limpeza do cluster Kubernetes"

case $ENVIRONMENT in
    "dev")
        log_info "Limpando ambiente de desenvolvimento..."
        if confirm; then
            kubectl delete namespace app-dev --ignore-not-found=true
        fi
        ;;
    "hml")
        log_info "Limpando ambiente de homologação..."
        if confirm; then
            kubectl delete namespace app-hml --ignore-not-found=true
        fi
        ;;
    "argocd")
        log_info "Removendo ArgoCD..."
        if confirm; then
            kubectl delete -f argocd/applications/ --ignore-not-found=true
            kubectl delete -f argocd/projects/ --ignore-not-found=true
            kubectl delete namespace argocd --ignore-not-found=true
        fi
        ;;
    "monitoring")
        log_info "Removendo monitoramento..."
        if confirm; then
            helm uninstall monitoring --namespace monitoring || true
            kubectl delete namespace monitoring --ignore-not-found=true
        fi
        ;;
    "jenkins")
        log_info "Parando Jenkins..."
        if confirm; then
            docker-compose -f jenkins/docker-compose.jenkins.yml down -v
        fi
        ;;
    "all")
        log_error "⚠️  ATENÇÃO: Isso removerá TODOS os recursos!"
        echo "Isso inclui:"
        echo "  - Namespaces app-dev e app-hml"
        echo "  - ArgoCD completo"
        echo "  - Jenkins e containers"
        echo "  - Monitoramento (se instalado)"
        echo ""
        
        if confirm; then
            log_step "Removendo aplicações..."
            kubectl delete namespace app-dev app-hml --ignore-not-found=true
            
            log_step "Removendo ArgoCD..."
            kubectl delete -f argocd/applications/ --ignore-not-found=true
            kubectl delete -f argocd/projects/ --ignore-not-found=true
            kubectl delete namespace argocd --ignore-not-found=true
            
            log_step "Removendo monitoramento..."
            helm uninstall monitoring --namespace monitoring || true
            kubectl delete namespace monitoring --ignore-not-found=true
            
            log_step "Parando Jenkins..."
            docker-compose -f jenkins/docker-compose.jenkins.yml down -v
            
            log_step "Limpando imagens Docker..."
            docker system prune -f
            
            log_info "✅ Limpeza completa!"
        fi
        ;;
    *)
        log_error "Ambiente inválido. Use: dev, hml, argocd, monitoring, jenkins, ou all"
        exit 1
        ;;
esac

log_info "🎉 Limpeza concluída!"
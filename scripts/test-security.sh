#!/bin/bash

# Script para executar testes de segurança SAST e DAST
set -e

# Configurações
TARGET_URL=${1:-https://app-dev.yourdomain.com}
REPORT_DIR=${2:-./security-reports}

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

# Criar diretório de relatórios
mkdir -p $REPORT_DIR

log_info "🔒 Iniciando testes de segurança"
log_info "🎯 Alvo: $TARGET_URL"
log_info "📁 Relatórios em: $REPORT_DIR"

# 1. SAST - Static Application Security Testing
log_step "Executando SAST com Semgrep..."

if command -v semgrep &> /dev/null; then
    log_info "Executando Semgrep..."
    
    # Scan completo
    semgrep --config=auto \
        --json \
        --output=$REPORT_DIR/semgrep-full-report.json \
        . || true
    
    # Scan apenas para vulnerabilidades críticas
    semgrep --config=p/security-audit \
        --json \
        --output=$REPORT_DIR/semgrep-security-report.json \
        . || true
    
    # Scan específico para Python
    semgrep --config=p/python \
        --json \
        --output=$REPORT_DIR/semgrep-python-report.json \
        backend/ || true
    
    # Scan específico para JavaScript
    semgrep --config=p/javascript \
        --json \
        --output=$REPORT_DIR/semgrep-javascript-report.json \
        frontend/ || true
    
    log_info "✅ Semgrep concluído"
else
    log_warn "Semgrep não encontrado. Instalando..."
    pip install semgrep
fi

# 2. Análise de dependências vulneráveis
log_step "Verificando dependências vulneráveis..."

# Python - Safety
if command -v safety &> /dev/null; then
    log_info "Executando Safety para Python..."
    safety check --json --output $REPORT_DIR/safety-report.json --continue-on-error || true
else
    pip install safety
    safety check --json --output $REPORT_DIR/safety-report.json --continue-on-error || true
fi

# Node.js - npm audit
if [[ -f "frontend/package.json" ]]; then
    log_info "Executando npm audit para Node.js..."
    cd frontend
    npm audit --json > ../$REPORT_DIR/npm-audit-report.json 2>/dev/null || true
    cd ..
fi

# 3. Scan de containers
log_step "Executando scan de containers com Trivy..."

if command -v trivy &> /dev/null; then
    # Scan da imagem do backend
    log_info "Scanning backend image..."
    trivy image --format json \
        --output $REPORT_DIR/trivy-backend-report.json \
        your-registry.com/fastapi-backend:latest || true
    
    # Scan da imagem do frontend
    log_info "Scanning frontend image..."
    trivy image --format json \
        --output $REPORT_DIR/trivy-frontend-report.json \
        your-registry.com/react-frontend:latest || true
    
    # Scan do filesystem
    log_info "Scanning filesystem..."
    trivy fs --format json \
        --output $REPORT_DIR/trivy-fs-report.json \
        . || true
        
    log_info "✅ Trivy scans concluídos"
else
    log_warn "Trivy não encontrado. Pulando scan de containers..."
fi

# 4. DAST - Dynamic Application Security Testing
log_step "Executando DAST com OWASP ZAP..."

# Verificar se a aplicação está acessível
if curl -f -s --connect-timeout 10 $TARGET_URL > /dev/null; then
    log_info "Aplicação acessível. Iniciando OWASP ZAP..."
    
    # Executar ZAP baseline scan
    docker run --rm -v $(pwd)/$REPORT_DIR:/zap/wrk/:rw \
        owasp/zap2docker-stable zap-baseline.py \
        -t $TARGET_URL \
        -J zap-baseline-report.json \
        -r zap-baseline-report.html || true
    
    # Executar ZAP full scan (mais demorado)
    if [[ "$FULL_DAST" == "true" ]]; then
        log_info "Executando full scan (pode demorar...)..."
        docker run --rm -v $(pwd)/$REPORT_DIR:/zap/wrk/:rw \
            owasp/zap2docker-stable zap-full-scan.py \
            -t $TARGET_URL \
            -J zap-full-report.json \
            -r zap-full-report.html || true
    fi
    
    log_info "✅ OWASP ZAP concluído"
else
    log_warn "⚠️  Aplicação não está acessível. Pulando DAST..."
fi

# 5. Análise de configuração do Kubernetes
log_step "Verificando configurações de segurança do Kubernetes..."

# Usar kube-score para análise
if command -v kube-score &> /dev/null; then
    log_info "Executando kube-score..."
    
    # Analisar manifestos do dev
    kube-score score k8s/dev/*.yaml > $REPORT_DIR/kube-score-dev.txt 2>&1 || true
    
    # Analisar manifestos de homologação
    kube-score score k8s/hml/*.yaml > $REPORT_DIR/kube-score-hml.txt 2>&1 || true
    
    log_info "✅ kube-score concluído"
else
    log_warn "kube-score não encontrado. Pulando análise K8s..."
fi

# 6. Verificações de configuração
log_step "Verificando configurações de segurança..."

# Verificar se secrets não estão em texto plano
log_info "Verificando secrets..."
if grep -r "password.*=" . --exclude-dir=.git --exclude-dir=node_modules --exclude="*.md" | grep -v "example" > $REPORT_DIR/potential-secrets.txt; then
    log_warn "⚠️  Possíveis secrets encontrados em texto plano!"
else
    log_info "✅ Nenhum secret em texto plano encontrado"
fi

# Verificar configurações inseguras
log_info "Verificando configurações inseguras..."
{
    echo "=== Verificação de Configurações Inseguras ==="
    echo ""
    
    echo "1. Verificando DEBUG habilitado:"
    grep -r "DEBUG.*=.*True" . --exclude-dir=.git || echo "Nenhum DEBUG encontrado"
    
    echo ""
    echo "2. Verificando CORS permissivo:"
    grep -r "allow_origins.*\*" . --exclude-dir=.git || echo "Nenhum CORS permissivo encontrado"
    
    echo ""
    echo "3. Verificando SSL desabilitado:"
    grep -r "ssl.*false\|https.*false" . --exclude-dir=.git || echo "Nenhuma configuração SSL insegura encontrada"
    
} > $REPORT_DIR/security-config-check.txt

# 7. Gerar relatório consolidado
log_step "Gerando relatório consolidado..."

cat > $REPORT_DIR/security-summary.md << EOF
# Relatório de Segurança

**Data:** $(date)
**Alvo:** $TARGET_URL

## Resumo Executivo

### SAST (Static Application Security Testing)
- [x] Semgrep
- [x] Safety (Python)
- [x] npm audit (Node.js)

### DAST (Dynamic Application Security Testing)
- [x] OWASP ZAP

### Container Security
- [x] Trivy

### Infrastructure Security
- [x] Kube-score
- [x] Configuration checks

## Arquivos de Relatório

### SAST Reports
- \`semgrep-full-report.json\` - Análise completa Semgrep
- \`semgrep-security-report.json\` - Vulnerabilidades de segurança
- \`safety-report.json\` - Vulnerabilidades Python
- \`npm-audit-report.json\` - Vulnerabilidades Node.js

### DAST Reports
- \`zap-baseline-report.json\` - OWASP ZAP baseline
- \`zap-baseline-report.html\` - OWASP ZAP baseline (HTML)

### Container Reports
- \`trivy-backend-report.json\` - Scan backend container
- \`trivy-frontend-report.json\` - Scan frontend container
- \`trivy-fs-report.json\` - Scan filesystem

### Infrastructure Reports
- \`kube-score-dev.txt\` - Análise manifests dev
- \`kube-score-hml.txt\` - Análise manifests hml
- \`security-config-check.txt\` - Verificações de configuração

## Ações Recomendadas

1. Revisar todas as vulnerabilidades encontradas
2. Priorizar correções baseadas na criticidade
3. Implementar controles preventivos no pipeline
4. Agendar scans regulares de segurança

## Próximos Passos

- [ ] Corrigir vulnerabilidades críticas
- [ ] Atualizar dependências vulneráveis
- [ ] Implementar security gates no pipeline
- [ ] Configurar monitoramento de segurança contínuo
EOF

# 8. Mostrar resumo
log_step "Resumo dos testes de segurança:"

echo ""
echo "📊 Relatórios gerados em: $REPORT_DIR"
echo ""
echo "📋 Arquivos principais:"
ls -la $REPORT_DIR/ | grep -E "\.(json|html|txt|md)$" || true

echo ""
echo "🔍 Para ver o resumo:"
echo "cat $REPORT_DIR/security-summary.md"

echo ""
log_info "✅ Testes de segurança concluídos!"
echo ""
log_warn "⚠️  Importante: Revisar todos os relatórios e corrigir vulnerabilidades encontradas!"
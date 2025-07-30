# 🚀 Guia Passo a Passo - Pipeline CI/CD Completo

Este guia te levará do zero até ter um pipeline CI/CD completo funcionando com Jenkins, SAST, DAST, Kubernetes e ArgoCD.

## 📋 Pré-requisitos

### 1. **Ferramentas Necessárias**
```bash
# Verificar se estão instaladas
docker --version          # Docker 20.10+
kubectl version --client  # kubectl 1.24+
git --version             # Git 2.x+
```

### 2. **Acessos Necessários**
- [ ] Cluster Kubernetes funcionando
- [ ] Docker Registry (Docker Hub, Google Container Registry, etc.)
- [ ] GitHub repository: `git@github.com:periclesandrade21/jenkins_nodejs.git`
- [ ] Domínios para as aplicações (ou usar nip.io para testes)

---

## 🔧 FASE 1: Preparação do Ambiente

### Passo 1.1: Clonar e Configurar Repositório
```bash
# Clonar seu repositório
git clone git@github.com:periclesandrade21/jenkins_nodejs.git
cd jenkins_nodejs

# Copiar arquivos da infraestrutura (do ambiente atual)
# Você precisa copiar todos os arquivos que foram criados para seu repositório
```

### Passo 1.2: Verificar Dependências
```bash
# Usar o comando make para verificar
make check-deps
```

### Passo 1.3: Configurar Permissões
```bash
# Dar permissão aos scripts
chmod +x scripts/*.sh
```

---

## ⚙️ FASE 2: Configuração de Credenciais

### Passo 2.1: Configurar Jenkins
```bash
# Copiar arquivo de exemplo
cp jenkins/.env.example jenkins/.env

# Editar com suas credenciais
nano jenkins/.env
```

**Configurar as seguintes variáveis em `jenkins/.env`:**
```bash
# Jenkins
JENKINS_ADMIN_PASSWORD=SuaSenhaSegura123

# Docker Registry (exemplo Docker Hub)
DOCKER_REGISTRY=docker.io/seuusuario
DOCKER_REGISTRY_USER=seuusuario
DOCKER_REGISTRY_PASSWORD=suasenhadockerhub

# Git (Token do GitHub)
GIT_USERNAME=periclesandrade21
GIT_TOKEN=ghp_seu_token_aqui

# SonarQube (será gerado depois)
SONARQUBE_TOKEN=deixe_vazio_por_enquanto

# Kubernetes (será configurado depois)
KUBECONFIG_B64=deixe_vazio_por_enquanto
```

### Passo 2.2: Atualizar Domínios
**Opção A: Usar seus domínios reais**
```bash
# Substituir yourdomain.com pelos seus domínios
find . -name "*.yaml" -exec sed -i 's/yourdomain.com/seudominio.com/g' {} \\;
```

**Opção B: Usar nip.io para testes (mais fácil)**
```bash
# Obter IP do seu cluster
CLUSTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "IP do cluster: $CLUSTER_IP"

# Atualizar com nip.io
find . -name "*.yaml" -exec sed -i "s/yourdomain.com/${CLUSTER_IP}.nip.io/g" {} \\;
```

### Passo 2.3: Configurar Registry
```bash
# Substituir your-registry.com pelo seu registry
find . -name "*.yaml" -name "Jenkinsfile" -exec sed -i 's/your-registry.com/docker.io\\/seuusuario/g' {} \\;
```

---

## 🏗️ FASE 3: Setup da Infraestrutura

### Passo 3.1: Configurar Cluster Kubernetes
```bash
# Verificar conexão com cluster
kubectl cluster-info

# Executar setup completo
make setup
```

**O script vai instalar:**
- NGINX Ingress Controller
- cert-manager (para HTTPS)
- ArgoCD
- Namespaces (app-dev, app-hml)
- Aplicar todos os manifestos

### Passo 3.2: Obter Informações Importantes
```bash
# Senha do ArgoCD
make argocd-password

# Status dos pods
kubectl get pods -A
```

---

## 🚀 FASE 4: Configurar Jenkins

### Passo 4.1: Iniciar Jenkins
```bash
# Iniciar containers do Jenkins
make setup-jenkins

# Verificar se está rodando
docker-compose -f jenkins/docker-compose.jenkins.yml ps
```

### Passo 4.2: Acessar Jenkins
```bash
# Jenkins estará disponível em:
# http://localhost:8080
# User: admin
# Password: (definida no .env)
```

### Passo 4.3: Configurar SonarQube
```bash
# SonarQube estará em:
# http://localhost:9000
# User: admin
# Password: admin (altere na primeira vez)

# Após login no SonarQube:
# 1. Ir em Administration > Security > Users
# 2. Gerar token para admin
# 3. Copiar o token e atualizar jenkins/.env
echo "SONARQUBE_TOKEN=seu_token_aqui" >> jenkins/.env

# Reiniciar Jenkins para carregar nova variável
docker-compose -f jenkins/docker-compose.jenkins.yml restart jenkins
```

### Passo 4.4: Configurar Kubeconfig no Jenkins
```bash
# Gerar kubeconfig em base64
cat ~/.kube/config | base64 -w 0 > kubeconfig.b64

# Adicionar ao .env
echo "KUBECONFIG_B64=$(cat kubeconfig.b64)" >> jenkins/.env

# Reiniciar Jenkins
docker-compose -f jenkins/docker-compose.jenkins.yml restart jenkins
```

---

## 🔒 FASE 5: Testar Segurança

### Passo 5.1: Executar Testes Locais
```bash
# Testes básicos de segurança
make security

# Testes completos (demora mais)
make security-full
```

### Passo 5.2: Verificar Relatórios
```bash
# Ver relatórios gerados
ls -la security-reports/
cat security-reports/security-summary.md
```

---

## 🚢 FASE 6: Deploy e Testes

### Passo 6.1: Build e Deploy Local
```bash
# Build das imagens
make build

# Push para registry
make push

# Deploy para desenvolvimento
make deploy-dev
```

### Passo 6.2: Verificar Deploy
```bash
# Status dos pods
make status

# Logs da aplicação
make logs

# Testar aplicação
curl https://app-dev.${CLUSTER_IP}.nip.io/api/
```

### Passo 6.3: Deploy para Homologação
```bash
# Deploy para homologação
make deploy-hml

# Verificar
kubectl get pods -n app-hml
```

---

## 🔄 FASE 7: Configurar Pipeline Automático

### Passo 7.1: Fazer Commit das Configurações
```bash
# Adicionar arquivos ao git
git add .
git commit -m "feat: pipeline CI/CD completo configurado"
git push origin main
```

### Passo 7.2: Verificar Jenkins Pipeline
1. Acessar Jenkins: http://localhost:8080
2. O job `fastapi-react-app` deve aparecer automaticamente
3. Verificar se o pipeline está rodando

### Passo 7.3: Testar Pipeline Completo
```bash
# Criar branch de desenvolvimento
git checkout -b develop
echo "# Teste" >> README.md
git add README.md
git commit -m "test: pipeline automation"
git push origin develop
```

**O pipeline deve:**
1. Fazer checkout do código
2. Instalar dependências
3. Executar testes
4. Executar SAST/DAST
5. Build das imagens
6. Deploy para dev

---

## 📊 FASE 8: Verificar ArgoCD

### Passo 8.1: Acessar ArgoCD
```bash
# Port-forward se necessário
make argocd-port-forward

# Ou acesse diretamente (se configurou domínio)
# https://argocd.seudominio.com
```

### Passo 8.2: Verificar Aplicações
- Login: admin
- Senha: (obtida com `make argocd-password`)
- Verificar aplicações `fastapi-react-app-dev` e `fastapi-react-app-hml`

---

## 🎯 FASE 9: Monitoramento (Opcional)

### Passo 9.1: Instalar Stack de Monitoramento
```bash
# Instalar Prometheus + Grafana
make monitoring
```

### Passo 9.2: Acessar Dashboards
```bash
# Port-forward do Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

# Acesse: http://localhost:3000
# User: admin / Password: admin123
```

---

## ✅ FASE 10: Validação Final

### Passo 10.1: Checklist de Validação
```bash
# 1. Verificar todos os pods estão rodando
kubectl get pods -A

# 2. Testar aplicações
curl https://app-dev.${CLUSTER_IP}.nip.io/
curl https://app-hml.${CLUSTER_IP}.nip.io/

# 3. Verificar Jenkins
curl http://localhost:8080

# 4. Verificar ArgoCD
curl https://argocd.${CLUSTER_IP}.nip.io

# 5. Executar testes completos
make test
```

### Passo 10.2: Teste de Pipeline End-to-End
```bash
# 1. Fazer mudança no código
echo "console.log('Pipeline test');" >> frontend/src/App.js

# 2. Commit e push
git add .
git commit -m "test: pipeline end-to-end"
git push origin develop

# 3. Acompanhar pipeline no Jenkins
# 4. Verificar deploy automático no ArgoCD
# 5. Validar aplicação funcionando
```

---

## 🛠️ Comandos Úteis para o Dia a Dia

### Desenvolvimento
```bash
make help                 # Ver todos os comandos
make build               # Build das imagens
make test                # Executar testes
make deploy-dev          # Deploy para dev
make logs                # Ver logs
make status              # Status dos recursos
```

### Segurança
```bash
make security            # Testes de segurança básicos
make security-full       # Testes completos
make lint                # Linting do código
```

### Troubleshooting
```bash
make jenkins-logs        # Logs do Jenkins
make sonar-logs          # Logs do SonarQube
kubectl describe pod POD_NAME -n NAMESPACE  # Debug de pods
```

### Limpeza
```bash
make clean              # Limpar recursos locais
make clean-dev          # Limpar ambiente dev
make clean-hml          # Limpar ambiente hml
make clean-all          # CUIDADO: Limpa tudo!
```

---

## 🚨 Troubleshooting Comum

### Problema 1: Jenkins não inicia
```bash
# Verificar logs
make jenkins-logs

# Verificar permissões Docker
sudo usermod -aG docker $USER
newgrp docker
```

### Problema 2: Pods não iniciam no Kubernetes
```bash
# Ver eventos
kubectl get events --sort-by=.metadata.creationTimestamp

# Verificar recursos
kubectl describe pod POD_NAME -n NAMESPACE
```

### Problema 3: ArgoCD não sincroniza
```bash
# Verificar aplicações
kubectl get applications -n argocd

# Forçar sync
kubectl patch application fastapi-react-app-dev -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

### Problema 4: Registry não permite push
```bash
# Login no Docker
docker login -u seuusuario

# Verificar credenciais no Jenkins
# Ir em Jenkins > Credentials > System > Global credentials
```

---

## 📞 Próximos Passos

Após seguir todos os passos, você terá:

✅ **Jenkins** rodando com pipeline completo  
✅ **Kubernetes** com aplicações em dev/hml  
✅ **ArgoCD** gerenciando GitOps  
✅ **SAST/DAST** integrados no pipeline  
✅ **Monitoramento** (se instalado)  
✅ **Automação** completa via Makefile  

### Para Produção:
1. Configurar domínios reais com DNS
2. Configurar certificados SSL válidos
3. Configurar backup do Jenkins
4. Implementar disaster recovery
5. Configurar alertas no monitoramento
6. Review de segurança completo

**🎉 Seu pipeline CI/CD está funcionando!**

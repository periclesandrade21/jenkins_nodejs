# Pipeline CI/CD com Jenkins, DAST, SAST e ArgoCD

Este repositório contém uma configuração completa de CI/CD para uma aplicação FastAPI + React usando Jenkins, DAST, SAST e ArgoCD no Kubernetes.

## 🏗️ Arquitetura

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Jenkins     │    │   SonarQube     │    │   OWASP ZAP     │
│   (CI/CD)       │    │    (SAST)       │    │    (DAST)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
         ┌───────────────────────▼───────────────────────┐
         │            Kubernetes Cluster                 │
         │                                              │
         │  ┌─────────────┐  ┌─────────────┐           │
         │  │   DEV ENV    │  │   HML ENV    │           │
         │  │ (Namespace)  │  │ (Namespace)  │           │
         │  └─────────────┘  └─────────────┘           │
         │                                              │
         │  ┌─────────────────────────────────────────┐ │
         │  │            ArgoCD                       │ │
         │  │          (GitOps)                       │ │
         │  └─────────────────────────────────────────┘ │
         └──────────────────────────────────────────────┘
```

## 🚀 Componentes

### 1. **Jenkins**
- Pipeline completo com stages de build, test, security e deploy
- Integração com Docker para build de containers
- SAST com SonarQube e Semgrep
- DAST com OWASP ZAP
- Deploy automático para dev/hml

### 2. **Kubernetes**
- Dois ambientes: `app-dev` e `app-hml`
- Configurações com Kustomize
- Ingress com HTTPS
- Network Policies para segurança
- HPA para auto-scaling

### 3. **ArgoCD**
- GitOps workflow
- Sync automático dos ambientes
- Rollback automático em caso de falha
- Interface web para monitoramento

### 4. **Security**
- **SAST**: SonarQube + Semgrep
- **DAST**: OWASP ZAP
- **Container Security**: Trivy
- **Dependency Check**: Safety + npm audit

## 📋 Pré-requisitos

- Cluster Kubernetes funcionando
- Docker e Docker Compose
- kubectl configurado
- Helm 3.x
- Acesso ao registry de containers

## 🛠️ Instalação

### 1. Configurar o Cluster

```bash
# Clonar o repositório
git clone git@github.com:periclesandrade21/jenkins_nodejs.git
cd jenkins_nodejs

# Executar setup do cluster
./scripts/setup-cluster.sh
```

### 2. Configurar Jenkins

```bash
# Copiar arquivo de exemplo
cp jenkins/.env.example jenkins/.env

# Editar variáveis de ambiente
vim jenkins/.env

# Iniciar Jenkins
docker-compose -f jenkins/docker-compose.jenkins.yml up -d
```

### 3. Configurar Credenciais

No Jenkins (http://localhost:8080):

1. **Docker Registry**: Adicionar credenciais do registry
2. **Kubernetes**: Upload do kubeconfig
3. **Git**: Token de acesso ao repositório
4. **SonarQube**: Token de autenticação

## 🔧 Configuração

### Variáveis de Ambiente

```bash
# Docker Registry
DOCKER_REGISTRY=your-registry.com
DOCKER_REGISTRY_USER=your-user
DOCKER_REGISTRY_PASSWORD=your-password

# SonarQube
SONARQUBE_TOKEN=your-sonarqube-token

# Kubernetes
KUBECONFIG_B64=base64-encoded-kubeconfig

# Git
GIT_USERNAME=your-username
GIT_TOKEN=your-token
```

### Domínios

Atualizar os domínios nos arquivos:
- `k8s/dev/ingress.yaml`
- `k8s/hml/ingress.yaml`
- `argocd/argocd-installation.yaml`

## 🚀 Deploy

### Deploy Manual

```bash
# Deploy para desenvolvimento
BUILD_IMAGES=true ./scripts/deploy.sh dev latest

# Deploy para homologação
BUILD_IMAGES=true ./scripts/deploy.sh hml v1.0.0
```

### Deploy via Pipeline

1. Push código para branch `develop` → Deploy automático em DEV
2. Push código para branch `main` → Deploy automático em HML

## 🔒 Testes de Segurança

### Executar Testes Completos

```bash
# Testes básicos
./scripts/test-security.sh https://app-dev.yourdomain.com

# Testes completos (inclui full DAST)
FULL_DAST=true ./scripts/test-security.sh https://app-dev.yourdomain.com
```

### Relatórios Gerados

- **SAST**: Semgrep, SonarQube, Safety
- **DAST**: OWASP ZAP baseline e full scan
- **Containers**: Trivy vulnerability scan
- **Infrastructure**: Kube-score analysis

## 📊 Monitoramento

### ArgoCD
- Interface: https://argocd.yourdomain.com
- Usuário: admin
- Senha: Obtida via `kubectl -n argocd get secret argocd-initial-admin-secret`

### Aplicação
- **DEV**: https://app-dev.yourdomain.com
- **HML**: https://app-hml.yourdomain.com

### Logs
```bash
# Backend logs
kubectl logs -f deployment/backend-deployment -n app-dev

# Frontend logs
kubectl logs -f deployment/frontend-deployment -n app-dev
```

## 🔄 Pipeline Stages

1. **Checkout**: Clone do repositório
2. **Dependencies**: Instalação de dependências Python/Node.js
3. **Code Quality**: Lint, format check
4. **SAST**: Análise estática com SonarQube/Semgrep
5. **Unit Tests**: Testes unitários com coverage
6. **Quality Gate**: Verificação SonarQube
7. **Build**: Build das imagens Docker
8. **Container Security**: Scan com Trivy
9. **Deploy DEV**: Deploy automático para desenvolvimento
10. **DAST**: Testes dinâmicos com OWASP ZAP
11. **Integration Tests**: Testes de integração
12. **Deploy HML**: Deploy para homologação (apenas main)
13. **ArgoCD Sync**: Atualização via GitOps

## 📁 Estrutura do Projeto

```
├── backend/                 # Código FastAPI
├── frontend/                # Código React
├── k8s/                    # Manifestos Kubernetes
│   ├── base/               # Recursos base
│   ├── dev/                # Overlay desenvolvimento
│   └── hml/                # Overlay homologação
├── argocd/                 # Configurações ArgoCD
├── jenkins/                # Configurações Jenkins
├── docker/                 # Configurações Docker
├── scripts/                # Scripts de automação
├── Jenkinsfile            # Pipeline definição
├── docker-compose.yml     # Ambiente local
└── README-CICD.md        # Esta documentação
```

## 🧹 Limpeza

```bash
# Limpar ambiente específico
./scripts/cleanup.sh dev

# Limpar tudo (CUIDADO!)
./scripts/cleanup.sh all
```

## 🚨 Troubleshooting

### Jenkins não inicia
```bash
# Verificar logs
docker-compose -f jenkins/docker-compose.jenkins.yml logs jenkins
```

### Pods não iniciam
```bash
# Verificar eventos
kubectl describe pod <pod-name> -n <namespace>

# Verificar logs
kubectl logs <pod-name> -n <namespace>
```

### ArgoCD não sincroniza
```bash
# Verificar status da aplicação
kubectl get applications -n argocd

# Sync manual
argocd app sync fastapi-react-app-dev
```

## 📚 Documentação Adicional

- [Configuração Jenkins](jenkins/README.md)
- [Manifestos Kubernetes](k8s/README.md)
- [Configuração ArgoCD](argocd/README.md)
- [Scripts de Automação](scripts/README.md)

## 🤝 Contribuição

1. Fork o projeto
2. Crie uma branch para sua feature
3. Commit suas mudanças
4. Push para a branch
5. Abra um Pull Request

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para detalhes.
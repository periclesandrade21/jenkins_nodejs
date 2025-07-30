# Makefile para automação do projeto CI/CD

.PHONY: help setup build test deploy clean security lint

# Variáveis
DOCKER_REGISTRY ?= your-registry.com
IMAGE_TAG ?= latest
ENVIRONMENT ?= dev
KUBECONFIG ?= ~/.kube/config

# Cores para output
GREEN=\033[0;32m
YELLOW=\033[1;33m
RED=\033[0;31m
NC=\033[0m # No Color

help: ## Mostra esta mensagem de ajuda
	@echo "$(GREEN)Comandos disponíveis:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## Configura o ambiente completo
	@echo "$(GREEN)Configurando ambiente...$(NC)"
	chmod +x scripts/*.sh
	./scripts/setup-cluster.sh

setup-jenkins: ## Configura apenas o Jenkins
	@echo "$(GREEN)Configurando Jenkins...$(NC)"
	cp jenkins/.env.example jenkins/.env
	docker-compose -f jenkins/docker-compose.jenkins.yml up -d
	@echo "$(YELLOW)Edite jenkins/.env com suas credenciais antes de usar$(NC)"

build: ## Faz build das imagens Docker
	@echo "$(GREEN)Building images...$(NC)"
	docker build -f Dockerfile.backend -t $(DOCKER_REGISTRY)/fastapi-backend:$(IMAGE_TAG) .
	docker build -f Dockerfile.frontend -t $(DOCKER_REGISTRY)/react-frontend:$(IMAGE_TAG) .

push: build ## Faz push das imagens para o registry
	@echo "$(GREEN)Pushing images...$(NC)"
	docker push $(DOCKER_REGISTRY)/fastapi-backend:$(IMAGE_TAG)
	docker push $(DOCKER_REGISTRY)/react-frontend:$(IMAGE_TAG)

test: ## Executa todos os testes
	@echo "$(GREEN)Executando testes...$(NC)"
	# Testes Python
	cd backend && python -m pytest ../tests/ -v
	# Testes Node.js
	cd frontend && yarn test --watchAll=false
	# Testes do pipeline
	python -m pytest tests/test_pipeline.py -v

test-backend: ## Executa testes do backend
	@echo "$(GREEN)Testando backend...$(NC)"
	cd backend && python -m venv venv && . venv/bin/activate && pip install -r requirements.txt && python -m pytest -v

test-frontend: ## Executa testes do frontend
	@echo "$(GREEN)Testando frontend...$(NC)"
	cd frontend && yarn install && yarn test --watchAll=false

lint: ## Executa linting do código
	@echo "$(GREEN)Executando lint...$(NC)"
	# Python
	cd backend && flake8 . --max-line-length=88
	cd backend && black --check .
	cd backend && isort --check-only .
	# JavaScript
	cd frontend && yarn lint

format: ## Formata o código
	@echo "$(GREEN)Formatando código...$(NC)"
	# Python
	cd backend && black .
	cd backend && isort .
	# JavaScript
	cd frontend && yarn prettier --write src/

security: ## Executa testes de segurança
	@echo "$(GREEN)Executando testes de segurança...$(NC)"
	./scripts/test-security.sh

security-full: ## Executa testes de segurança completos (inclui DAST full)
	@echo "$(GREEN)Executando testes de segurança completos...$(NC)"
	FULL_DAST=true ./scripts/test-security.sh

deploy-dev: ## Deploy para desenvolvimento
	@echo "$(GREEN)Deploy para desenvolvimento...$(NC)"
	BUILD_IMAGES=true ./scripts/deploy.sh dev $(IMAGE_TAG)

deploy-hml: ## Deploy para homologação
	@echo "$(GREEN)Deploy para homologação...$(NC)"
	BUILD_IMAGES=true ./scripts/deploy.sh hml $(IMAGE_TAG)

deploy-local: ## Executa aplicação localmente
	@echo "$(GREEN)Executando aplicação localmente...$(NC)"
	docker-compose up -d

logs: ## Mostra logs da aplicação no Kubernetes
	@echo "$(GREEN)Logs do ambiente $(ENVIRONMENT):$(NC)"
	kubectl logs -f deployment/backend-deployment -n app-$(ENVIRONMENT) &
	kubectl logs -f deployment/frontend-deployment -n app-$(ENVIRONMENT)

status: ## Mostra status dos recursos
	@echo "$(GREEN)Status dos recursos:$(NC)"
	kubectl get pods,svc,ingress -n app-$(ENVIRONMENT)

clean: ## Limpa recursos locais
	@echo "$(GREEN)Limpando recursos locais...$(NC)"
	docker-compose down -v
	docker system prune -f

clean-dev: ## Limpa ambiente de desenvolvimento
	@echo "$(YELLOW)Limpando ambiente de desenvolvimento...$(NC)"
	./scripts/cleanup.sh dev

clean-hml: ## Limpa ambiente de homologação
	@echo "$(YELLOW)Limpando ambiente de homologação...$(NC)"
	./scripts/cleanup.sh hml

clean-all: ## Limpa todos os recursos (CUIDADO!)
	@echo "$(RED)ATENÇÃO: Isso removerá TODOS os recursos!$(NC)"
	@read -p "Tem certeza? (y/N): " -n 1 -r; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		./scripts/cleanup.sh all; \
	fi

argocd-password: ## Obtém senha do ArgoCD
	@echo "$(GREEN)Senha do ArgoCD:$(NC)"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo

argocd-port-forward: ## Faz port-forward do ArgoCD
	@echo "$(GREEN)ArgoCD disponível em: http://localhost:8080$(NC)"
	kubectl port-forward svc/argocd-server -n argocd 8080:443

jenkins-logs: ## Mostra logs do Jenkins
	docker-compose -f jenkins/docker-compose.jenkins.yml logs -f jenkins

sonar-logs: ## Mostra logs do SonarQube
	docker-compose -f jenkins/docker-compose.jenkins.yml logs -f sonarqube

validate-k8s: ## Valida manifestos Kubernetes
	@echo "$(GREEN)Validando manifestos Kubernetes...$(NC)"
	# Validar sintaxe YAML
	find k8s/ -name "*.yaml" -exec yaml-lint {} \;
	# Validar com kubectl (dry-run)
	kubectl apply --dry-run=client -k k8s/dev/
	kubectl apply --dry-run=client -k k8s/hml/

generate-secrets: ## Gera secrets base64 para Kubernetes
	@echo "$(GREEN)Gerando secrets:$(NC)"
	@echo "MongoDB URL (base64):"
	@echo -n "mongodb://admin:password123@mongodb-service:27017/test_database?authSource=admin" | base64
	@echo "MongoDB Password (base64):"
	@echo -n "password123" | base64

monitoring: ## Instala stack de monitoramento
	@echo "$(GREEN)Instalando monitoramento...$(NC)"
	INSTALL_MONITORING=true ./scripts/setup-cluster.sh

docs: ## Gera documentação
	@echo "$(GREEN)Documentação disponível em:$(NC)"
	@echo "  - README principal: README.md"
	@echo "  - CI/CD: README-CICD.md"
	@echo "  - Jenkins: http://localhost:8080"
	@echo "  - SonarQube: http://localhost:9000"

check-deps: ## Verifica dependências necessárias
	@echo "$(GREEN)Verificando dependências...$(NC)"
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)Docker não encontrado$(NC)"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)kubectl não encontrado$(NC)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(YELLOW)Helm não encontrado (será instalado)$(NC)"; }
	@echo "$(GREEN)✅ Dependências OK$(NC)"

info: ## Mostra informações do ambiente
	@echo "$(GREEN)Informações do ambiente:$(NC)"
	@echo "  Docker Registry: $(DOCKER_REGISTRY)"
	@echo "  Image Tag: $(IMAGE_TAG)"
	@echo "  Environment: $(ENVIRONMENT)"
	@echo "  Kubeconfig: $(KUBECONFIG)"
	@echo ""
	@echo "$(GREEN)URLs importantes:$(NC)"
	@echo "  - App Dev: https://app-dev.yourdomain.com"
	@echo "  - App HML: https://app-hml.yourdomain.com"
	@echo "  - ArgoCD: https://argocd.yourdomain.com"
	@echo "  - Jenkins: http://localhost:8080"
	@echo "  - SonarQube: http://localhost:9000"

# Aliases úteis
install: setup
start: deploy-local
stop: clean
restart: clean deploy-local
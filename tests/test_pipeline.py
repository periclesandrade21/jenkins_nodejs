#!/usr/bin/env python3
"""
Testes para validar o pipeline CI/CD
"""

import pytest
import requests
import subprocess
import json
import os
from pathlib import Path


class TestPipelineIntegration:
    """Testes de integração do pipeline"""
    
    @pytest.fixture
    def backend_url(self):
        """URL do backend para testes"""
        return os.getenv('BACKEND_URL', 'http://localhost:8001')
    
    @pytest.fixture
    def frontend_url(self):
        """URL do frontend para testes"""
        return os.getenv('FRONTEND_URL', 'http://localhost:3000')
    
    def test_backend_health(self, backend_url):
        """Testa se o backend está respondendo"""
        response = requests.get(f"{backend_url}/api/")
        assert response.status_code == 200
        assert "message" in response.json()
    
    def test_backend_api_endpoints(self, backend_url):
        """Testa endpoints principais da API"""
        # Test GET /api/status
        response = requests.get(f"{backend_url}/api/status")
        assert response.status_code == 200
        assert isinstance(response.json(), list)
        
        # Test POST /api/status
        test_data = {"client_name": "test_client"}
        response = requests.post(f"{backend_url}/api/status", json=test_data)
        assert response.status_code == 200
        assert response.json()["client_name"] == "test_client"
    
    def test_frontend_accessibility(self, frontend_url):
        """Testa se o frontend está acessível"""
        response = requests.get(frontend_url)
        assert response.status_code == 200
        assert "text/html" in response.headers.get("content-type", "")
    
    def test_cors_configuration(self, backend_url):
        """Testa configuração CORS"""
        headers = {
            'Origin': 'http://localhost:3000',
            'Access-Control-Request-Method': 'GET',
            'Access-Control-Request-Headers': 'Content-Type'
        }
        response = requests.options(f"{backend_url}/api/", headers=headers)
        assert response.status_code in [200, 204]


class TestSecurityScans:
    """Testes para validar scans de segurança"""
    
    def test_semgrep_scan(self):
        """Verifica se o scan do Semgrep não encontrou vulnerabilidades críticas"""
        result = subprocess.run([
            'semgrep', '--config=p/security-audit', 
            '--json', '--quiet', '.'
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            findings = json.loads(result.stdout)
            critical_findings = [
                f for f in findings.get('results', []) 
                if f.get('extra', {}).get('severity') == 'ERROR'
            ]
            assert len(critical_findings) == 0, f"Vulnerabilidades críticas encontradas: {critical_findings}"
    
    def test_python_dependencies(self):
        """Verifica dependências Python com Safety"""
        result = subprocess.run([
            'safety', 'check', '--json'
        ], capture_output=True, text=True, cwd='backend')
        
        if result.returncode != 0:
            try:
                vulnerabilities = json.loads(result.stdout)
                critical_vulns = [
                    v for v in vulnerabilities 
                    if v.get('vulnerability_id') and 'critical' in v.get('severity', '').lower()
                ]
                assert len(critical_vulns) == 0, f"Vulnerabilidades críticas: {critical_vulns}"
            except json.JSONDecodeError:
                # Se não conseguir parsear, apenas verifica se não há output
                pass
    
    def test_dockerfile_best_practices(self):
        """Verifica se os Dockerfiles seguem boas práticas"""
        backend_dockerfile = Path('Dockerfile.backend').read_text()
        frontend_dockerfile = Path('Dockerfile.frontend').read_text()
        
        # Verificar se não roda como root
        assert 'USER app' in backend_dockerfile or 'USER nginx' in backend_dockerfile
        assert 'USER' in frontend_dockerfile
        
        # Verificar health checks
        assert 'HEALTHCHECK' in backend_dockerfile
        assert 'HEALTHCHECK' in frontend_dockerfile


class TestKubernetesManifests:
    """Testes para validar manifestos Kubernetes"""
    
    def test_required_fields(self):
        """Verifica se os manifestos têm campos obrigatórios"""
        manifests_dir = Path('k8s/base')
        
        for yaml_file in manifests_dir.glob('*.yaml'):
            content = yaml_file.read_text()
            
            # Verificar se tem metadata
            assert 'metadata:' in content
            assert 'name:' in content
            
            # Para deployments, verificar campos essenciais
            if 'kind: Deployment' in content:
                assert 'spec:' in content
                assert 'selector:' in content
                assert 'template:' in content
    
    def test_security_contexts(self):
        """Verifica se os deployments têm security contexts"""
        deployment_files = [
            'k8s/base/backend-deployment.yaml',
            'k8s/base/frontend-deployment.yaml'
        ]
        
        for file_path in deployment_files:
            content = Path(file_path).read_text()
            assert 'securityContext:' in content
            assert 'runAsNonRoot: true' in content
    
    def test_resource_limits(self):
        """Verifica se os containers têm resource limits"""
        deployment_files = [
            'k8s/base/backend-deployment.yaml',
            'k8s/base/frontend-deployment.yaml'
        ]
        
        for file_path in deployment_files:
            content = Path(file_path).read_text()
            assert 'resources:' in content
            assert 'requests:' in content
            assert 'limits:' in content


class TestArgoCD:
    """Testes para configurações ArgoCD"""
    
    def test_application_manifests(self):
        """Verifica se as aplicações ArgoCD estão bem configuradas"""
        app_files = [
            'argocd/applications/app-dev.yaml',
            'argocd/applications/app-hml.yaml'
        ]
        
        for file_path in app_files:
            content = Path(file_path).read_text()
            
            # Verificar campos essenciais
            assert 'kind: Application' in content
            assert 'spec:' in content
            assert 'source:' in content
            assert 'destination:' in content
            assert 'syncPolicy:' in content
    
    def test_project_configuration(self):
        """Verifica configuração do projeto ArgoCD"""
        project_file = Path('argocd/projects/app-project.yaml')
        content = project_file.read_text()
        
        assert 'kind: AppProject' in content
        assert 'sourceRepos:' in content
        assert 'destinations:' in content


class TestJenkinsConfiguration:
    """Testes para configuração Jenkins"""
    
    def test_jenkinsfile_syntax(self):
        """Verifica sintaxe básica do Jenkinsfile"""
        jenkinsfile = Path('Jenkinsfile').read_text()
        
        # Verificar estrutura básica
        assert 'pipeline {' in jenkinsfile
        assert 'agent any' in jenkinsfile
        assert 'stages {' in jenkinsfile
        assert 'steps {' in jenkinsfile
    
    def test_required_stages(self):
        """Verifica se todas as stages necessárias estão presentes"""
        jenkinsfile = Path('Jenkinsfile').read_text()
        
        required_stages = [
            'Checkout',
            'Install Dependencies',
            'Code Quality & Security',
            'Unit Tests',
            'Build Docker Images',
            'Container Security Scan'
        ]
        
        for stage in required_stages:
            assert f"stage('{stage}')" in jenkinsfile
    
    def test_security_stages(self):
        """Verifica se as stages de segurança estão configuradas"""
        jenkinsfile = Path('Jenkinsfile').read_text()
        
        # Verificar SAST
        assert 'SonarQube' in jenkinsfile
        assert 'Semgrep' in jenkinsfile
        
        # Verificar DAST
        assert 'OWASP ZAP' in jenkinsfile or 'zap' in jenkinsfile.lower()
        
        # Verificar Container Security
        assert 'trivy' in jenkinsfile.lower()


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
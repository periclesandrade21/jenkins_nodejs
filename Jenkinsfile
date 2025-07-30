pipeline {
    agent any
    
    environment {
        // Configurações de registry
        DOCKER_REGISTRY = 'your-registry.com'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        BACKEND_IMAGE = "${DOCKER_REGISTRY}/fastapi-backend:${IMAGE_TAG}"
        FRONTEND_IMAGE = "${DOCKER_REGISTRY}/react-frontend:${IMAGE_TAG}"
        
        // Credenciais
        DOCKER_CREDENTIALS = credentials('docker-registry-credentials')
        SONAR_TOKEN = credentials('sonar-token')
        KUBECONFIG = credentials('kubeconfig')
        
        // Ambientes
        DEV_NAMESPACE = 'app-dev'
        HML_NAMESPACE = 'app-hml'
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 60, unit: 'MINUTES')
        skipStagesAfterUnstable()
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out source code...'
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Install Dependencies') {
            parallel {
                stage('Backend Dependencies') {
                    steps {
                        echo 'Installing Python dependencies...'
                        sh '''
                            python3 -m venv venv
                            . venv/bin/activate
                            pip install -r backend/requirements.txt
                        '''
                    }
                }
                stage('Frontend Dependencies') {
                    steps {
                        echo 'Installing Node.js dependencies...'
                        dir('frontend') {
                            sh 'yarn install --frozen-lockfile'
                        }
                    }
                }
            }
        }
        
        stage('Code Quality & Security') {
            parallel {
                stage('SAST - SonarQube') {
                    steps {
                        echo 'Running SonarQube analysis...'
                        script {
                            def scannerHome = tool 'SonarQubeScanner'
                            withSonarQubeEnv('SonarQube') {
                                sh """
                                    ${scannerHome}/bin/sonar-scanner \
                                    -Dsonar.projectKey=fastapi-react-app \
                                    -Dsonar.projectName='FastAPI React App' \
                                    -Dsonar.projectVersion=${IMAGE_TAG} \
                                    -Dsonar.sources=. \
                                    -Dsonar.exclusions='**/node_modules/**,**/venv/**,**/.git/**' \
                                    -Dsonar.python.coverage.reportPaths=coverage.xml \
                                    -Dsonar.javascript.lcov.reportPaths=frontend/coverage/lcov.info
                                """
                            }
                        }
                    }
                }
                
                stage('SAST - Semgrep') {
                    steps {
                        echo 'Running Semgrep security analysis...'
                        sh '''
                            pip install semgrep
                            semgrep --config=auto --json --output=semgrep-results.json . || true
                        '''
                        archiveArtifacts artifacts: 'semgrep-results.json', allowEmptyArchive: true
                    }
                }
                
                stage('Lint & Format Check') {
                    steps {
                        echo 'Running code linting...'
                        parallel (
                            "Python Lint": {
                                sh '''
                                    . venv/bin/activate
                                    flake8 backend/ --max-line-length=88 --exclude=venv
                                    black --check backend/
                                    isort --check-only backend/
                                '''
                            },
                            "JavaScript Lint": {
                                dir('frontend') {
                                    sh 'yarn lint'
                                }
                            }
                        )
                    }
                }
            }
        }
        
        stage('Unit Tests') {
            parallel {
                stage('Backend Tests') {
                    steps {
                        echo 'Running backend tests...'
                        sh '''
                            . venv/bin/activate
                            cd backend
                            pytest --cov=. --cov-report=xml --cov-report=html
                        '''
                    }
                    post {
                        always {
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'backend/htmlcov',
                                reportFiles: 'index.html',
                                reportName: 'Backend Coverage Report'
                            ])
                        }
                    }
                }
                
                stage('Frontend Tests') {
                    steps {
                        echo 'Running frontend tests...'
                        dir('frontend') {
                            sh 'yarn test --coverage --watchAll=false'
                        }
                    }
                    post {
                        always {
                            dir('frontend') {
                                publishHTML([
                                    allowMissing: false,
                                    alwaysLinkToLastBuild: true,
                                    keepAll: true,
                                    reportDir: 'coverage/lcov-report',
                                    reportFiles: 'index.html',
                                    reportName: 'Frontend Coverage Report'
                                ])
                            }
                        }
                    }
                }
            }
        }
        
        stage('SonarQube Quality Gate') {
            steps {
                echo 'Waiting for SonarQube Quality Gate...'
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
        
        stage('Build Docker Images') {
            parallel {
                stage('Build Backend Image') {
                    steps {
                        echo 'Building backend Docker image...'
                        script {
                            def backendImage = docker.build("${BACKEND_IMAGE}", "-f Dockerfile.backend .")
                            backendImage.push()
                            backendImage.push("latest")
                        }
                    }
                }
                
                stage('Build Frontend Image') {
                    steps {
                        echo 'Building frontend Docker image...'
                        script {
                            def frontendImage = docker.build("${FRONTEND_IMAGE}", "-f Dockerfile.frontend .")
                            frontendImage.push()
                            frontendImage.push("latest")
                        }
                    }
                }
            }
        }
        
        stage('Container Security Scan') {
            parallel {
                stage('Scan Backend Image') {
                    steps {
                        echo 'Scanning backend image for vulnerabilities...'
                        sh """
                            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            -v \$(pwd):/tmp aquasec/trivy image --format json \
                            --output /tmp/backend-scan.json ${BACKEND_IMAGE}
                        """
                        archiveArtifacts artifacts: 'backend-scan.json', allowEmptyArchive: true
                    }
                }
                
                stage('Scan Frontend Image') {
                    steps {
                        echo 'Scanning frontend image for vulnerabilities...'
                        sh """
                            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            -v \$(pwd):/tmp aquasec/trivy image --format json \
                            --output /tmp/frontend-scan.json ${FRONTEND_IMAGE}
                        """
                        archiveArtifacts artifacts: 'frontend-scan.json', allowEmptyArchive: true
                    }
                }
            }
        }
        
        stage('Deploy to Dev') {
            when {
                anyOf {
                    branch 'develop'
                    branch 'main'
                }
            }
            steps {
                echo 'Deploying to development environment...'
                script {
                    withKubeConfig([credentialsId: 'kubeconfig']) {
                        sh """
                            envsubst < k8s/dev/kustomization.yaml | kubectl apply -f -
                            kubectl set image deployment/backend-deployment backend=${BACKEND_IMAGE} -n ${DEV_NAMESPACE}
                            kubectl set image deployment/frontend-deployment frontend=${FRONTEND_IMAGE} -n ${DEV_NAMESPACE}
                            kubectl rollout status deployment/backend-deployment -n ${DEV_NAMESPACE}
                            kubectl rollout status deployment/frontend-deployment -n ${DEV_NAMESPACE}
                        """
                    }
                }
            }
        }
        
        stage('DAST - Dynamic Security Testing') {
            when {
                anyOf {
                    branch 'develop'
                    branch 'main'
                }
            }
            steps {
                echo 'Running OWASP ZAP dynamic security testing...'
                script {
                    def devUrl = "https://app-dev.yourdomain.com"
                    sh """
                        docker run --rm -v \$(pwd):/zap/wrk/:rw \
                        -u zap owasp/zap2docker-stable zap-full-scan.py \
                        -t ${devUrl} -J zap-report.json -r zap-report.html || true
                    """
                    archiveArtifacts artifacts: 'zap-report.*', allowEmptyArchive: true
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                anyOf {
                    branch 'develop'
                    branch 'main'
                }
            }
            steps {
                echo 'Running integration tests...'
                sh '''
                    . venv/bin/activate
                    pytest tests/integration/ --verbose
                '''
            }
        }
        
        stage('Deploy to Homologação') {
            when {
                branch 'main'
            }
            steps {
                echo 'Deploying to homologation environment...'
                script {
                    withKubeConfig([credentialsId: 'kubeconfig']) {
                        sh """
                            envsubst < k8s/hml/kustomization.yaml | kubectl apply -f -
                            kubectl set image deployment/backend-deployment backend=${BACKEND_IMAGE} -n ${HML_NAMESPACE}
                            kubectl set image deployment/frontend-deployment frontend=${FRONTEND_IMAGE} -n ${HML_NAMESPACE}
                            kubectl rollout status deployment/backend-deployment -n ${HML_NAMESPACE}
                            kubectl rollout status deployment/frontend-deployment -n ${HML_NAMESPACE}
                        """
                    }
                }
            }
        }
        
        stage('Update ArgoCD') {
            when {
                branch 'main'
            }
            steps {
                echo 'Updating ArgoCD applications...'
                script {
                    // Atualizar manifests do GitOps repo
                    withCredentials([usernamePassword(credentialsId: 'git-credentials', 
                                                   passwordVariable: 'GIT_PASSWORD', 
                                                   usernameVariable: 'GIT_USERNAME')]) {
                        sh """
                            git clone https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/your-org/gitops-repo.git
                            cd gitops-repo
                            
                            # Atualizar imagens nos manifests
                            sed -i 's|image: .*/fastapi-backend:.*|image: ${BACKEND_IMAGE}|g' apps/*/backend/deployment.yaml
                            sed -i 's|image: .*/react-frontend:.*|image: ${FRONTEND_IMAGE}|g' apps/*/frontend/deployment.yaml
                            
                            git add .
                            git commit -m "Update images to build ${BUILD_NUMBER}" || true
                            git push origin main
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo 'Cleaning up...'
            sh 'docker system prune -f || true'
            cleanWs()
        }
        
        success {
            echo 'Pipeline completed successfully!'
            slackSend(
                channel: '#deployments',
                color: 'good',
                message: "✅ Pipeline SUCCESS: ${env.JOB_NAME} - ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)"
            )
        }
        
        failure {
            echo 'Pipeline failed!'
            slackSend(
                channel: '#deployments',
                color: 'danger',
                message: "❌ Pipeline FAILED: ${env.JOB_NAME} - ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)"
            )
        }
        
        unstable {
            echo 'Pipeline unstable!'
            slackSend(
                channel: '#deployments',
                color: 'warning',
                message: "⚠️ Pipeline UNSTABLE: ${env.JOB_NAME} - ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)"
            )
        }
    }
}
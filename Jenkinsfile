pipeline {
    agent any

    tools {
        maven 'maven3'
    }

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['blue', 'green'], description: 'Which environment to deploy')
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between Blue and Green')
    }

    environment {
        IMAGE_NAME     = 'aniket1805/bankapp'
        TAG            = "${env.BUILD_NUMBER}"  // Unique per build
        KUBE_NAMESPACE = 'webapps'
        SCANNER_HOME   = tool 'sonar-scanner'
    }

    stages {
        stage('Git Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Compile') {
            steps {
                sh 'mvn compile'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn test -DskipTests=true'
            }
        }

        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs --format table -o fs.html .'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh "${SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=multitier -Dsonar.projectName=multitier -Dsonar.java.binaries=target"
                }
            }
        }

        stage('Quality Gate Check') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: false
                }
            }
        }

        stage('Build Jar') {
            steps {
                sh 'mvn package -DskipTests=true'
            }
        }

        stage('Publish Artifact to Nexus') {
            steps {
                withMaven(globalMavenSettingsConfig: 'maven-settings', maven: 'maven3', traceability: true) {
                    sh 'mvn deploy -DskipTests=true'
                }
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh """
                            docker build -t ${IMAGE_NAME}:${TAG} .
                            docker push ${IMAGE_NAME}:${TAG}
                        """
                    }
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh "trivy image --format table -o image.html ${IMAGE_NAME}:${TAG}"
            }
        }

        stage('Deploy MySQL') {
            steps {
                script {
                    withKubeConfig(credentialsId: 'k8-token', serverUrl: 'https://04B156B8E9377A835EC7902A0923ACF5.gr7.us-east-1.eks.amazonaws.com', namespace: "${KUBE_NAMESPACE}") {
                        sh "kubectl apply -f mysql-ds.yml -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }

        stage('Deploy Service') {
            steps {
                script {
                    withKubeConfig(credentialsId: 'k8-token', serverUrl: 'https://04B156B8E9377A835EC7902A0923ACF5.gr7.us-east-1.eks.amazonaws.com', namespace: "${KUBE_NAMESPACE}") {
                        sh """
                            if ! kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}; then
                                kubectl apply -f bankapp-service.yml -n ${KUBE_NAMESPACE}
                            fi
                        """
                    }
                }
            }
        }

        stage('Deploy App') {
            steps {
                script {
                    def deploymentFile = params.DEPLOY_ENV == 'blue' ? 'app-deployment-blue.yml' : 'app-deployment-green.yml'
                    withKubeConfig(credentialsId: 'k8-token', serverUrl: 'https://04B156B8E9377A835EC7902A0923ACF5.gr7.us-east-1.eks.amazonaws.com', namespace: "${KUBE_NAMESPACE}") {
                        // Replace image tag dynamically
                        sh """
                            sed -i 's|aniket1805/bankapp:.*|aniket1805/bankapp:${TAG}|g' ${deploymentFile}
                            kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}
                            kubectl rollout restart deployment bankapp-${params.DEPLOY_ENV} -n ${KUBE_NAMESPACE}
                            kubectl rollout status  deployment bankapp-${params.DEPLOY_ENV} -n ${KUBE_NAMESPACE}
                        """
                    }
                }
            }
        }

        stage('Switch Traffic') {
            when { expression { params.SWITCH_TRAFFIC } }
            steps {
                script {
                    def newEnv = params.DEPLOY_ENV
                    withKubeConfig(credentialsId: 'k8-token', serverUrl: 'https://04B156B8E9377A835EC7902A0923ACF5.gr7.us-east-1.eks.amazonaws.com', namespace: "${KUBE_NAMESPACE}") {
                        sh """
                            kubectl patch service bankapp-service -p '{"spec":{"selector":{"app":"bankapp","version":"${newEnv}"}}}' -n ${KUBE_NAMESPACE}
                        """
                    }
                    echo "✅ Traffic has been switched to the ${newEnv} environment."
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    def verifyEnv = params.DEPLOY_ENV
                    withKubeConfig(credentialsId: 'k8-token', serverUrl: 'https://04B156B8E9377A835EC7902A0923ACF5.gr7.us-east-1.eks.amazonaws.com', namespace: "${KUBE_NAMESPACE}") {
                        sh """
                            kubectl get pods -l version=${verifyEnv} -n ${KUBE_NAMESPACE}
                            kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}
                        """
                    }
                }
            }
        }
    }
}

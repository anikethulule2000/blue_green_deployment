pipeline {
    agent any

    tools {
        maven 'maven3'
    }

    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['blue', 'green'],
            description: 'Choose which environment to deploy (blue | green)'
        )
        choice(
            name: 'DOCKER_TAG',
            choices: ['blue', 'green'],
            description: 'Docker image tag to build & push'
        )
        booleanParam(
            name: 'SWITCH_TRAFFIC',
            defaultValue: false,
            description: 'If true, patch the Service selector to point to the chosen colour'
        )
    }

    environment {
        IMAGE_NAME     = 'aniket1805/bankapp'
        TAG            = "${params.DOCKER_TAG}"
        KUBE_NAMESPACE = 'webapps'
        SCANNER_HOME   = tool 'sonar-scanner'
    }

    stages {

        stage('Git Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Compile') {
            steps {
                sh 'mvn -B compile'
            }
        }

        stage('Unit Test') {
            steps {
                sh 'mvn -B test'
            }
        }

        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs --format table -o fs.html .'
                archiveArtifacts 'fs.html'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh "${SCANNER_HOME}/bin/sonar-scanner " +
                       "-Dsonar.projectKey=multitier " +
                       "-Dsonar.projectName=multitier " +
                       "-Dsonar.java.binaries=target"
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: false
                }
            }
        }

        stage('Package') {
            steps {
                sh 'mvn -B package -DskipTests=true'
            }
        }

        stage('Publish to Nexus') {
            steps {
                withMaven(globalMavenSettingsConfig: 'maven-settings', maven: 'maven3') {
                    sh 'mvn -B deploy -DskipTests=true'
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${TAG} ."
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh "trivy image --format table -o image.html ${IMAGE_NAME}:${TAG}"
                archiveArtifacts 'image.html'
            }
        }

        stage('Docker Push') {
            steps {
                docker.withRegistry('', 'docker-cred') {
                    sh "docker push ${IMAGE_NAME}:${TAG}"
                }
            }
        }

        stage('Deploy MySQL Resources') {
            steps {
                script {
                    withKubeConfig(
                        credentialsId: 'k8-token',
                        clusterName: 'anikettestproject-cluster',
                        namespace: KUBE_NAMESPACE,
                        serverUrl: 'https://27AE060DEFCA3673B772E33E35B76083.gr7.us-east-1.eks.amazonaws.com'
                    ) {
                        sh "kubectl apply -f mysql-ds.yml -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }

        stage('Deploy Service ( idempotent )') {
            steps {
                script {
                    withKubeConfig(
                        credentialsId: 'k8-token',
                        clusterName: 'anikettestproject-cluster',
                        namespace: KUBE_NAMESPACE,
                        serverUrl: 'https://27AE060DEFCA3673B772E33E35B76083.gr7.us-east-1.eks.amazonaws.com'
                    ) {
                        sh """
                           if ! kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}; then
                               kubectl apply -f bankapp-service.yml -n ${KUBE_NAMESPACE}
                           fi
                        """
                    }
                }
            }
        }

        stage('Deploy Application') {
            steps {
                script {
                    def deploymentFile = params.DEPLOY_ENV == 'blue'
                                          ? 'app-deployment-blue.yml'
                                          : 'app-deployment-green.yml'

                    withKubeConfig(
                        credentialsId: 'k8-token',
                        clusterName: 'anikettestproject-cluster',
                        namespace: KUBE_NAMESPACE,
                        serverUrl: 'https://27AE060DEFCA3673B772E33E35B76083.gr7.us-east-1.eks.amazonaws.com'
                    ) {
                        sh "kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }

        stage('Switch Traffic (Blue‑Green)') {
            when {
                expression { params.SWITCH_TRAFFIC }
            }
            steps {
                script {
                    withKubeConfig(
                        credentialsId: 'k8-token',
                        clusterName: 'anikettestproject-cluster',
                        namespace: KUBE_NAMESPACE,
                        serverUrl: 'https://27AE060DEFCA3673B772E33E35B76083.gr7.us-east-1.eks.amazonaws.com'
                    ) {
                        sh """
                           kubectl patch service bankapp-service \
                             -p '{"spec": {"selector": {"app": "bankapp", "version": "${params.DEPLOY_ENV}"}}}' \
                             -n ${KUBE_NAMESPACE}
                        """
                    }
                    echo "Traffic switched to **${params.DEPLOY_ENV}**."
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    withKubeConfig(
                        credentialsId: 'k8-token',
                        clusterName: 'anikettestproject-cluster',
                        namespace: KUBE_NAMESPACE,
                        serverUrl: 'https://27AE060DEFCA3673B772E33E35B76083.gr7.us-east-1.eks.amazonaws.com'
                    ) {
                        sh """
                           kubectl get pods -l version=${params.DEPLOY_ENV} -n ${KUBE_NAMESPACE}
                           kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}
                        """
                    }
                }
            }
        }
    }
}

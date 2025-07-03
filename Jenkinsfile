pipeline {
    agent any

    tools {
        maven 'maven3'
    }

    parameters {
        choice(name: 'DEPLOY_ENV',
               choices: ['blue', 'green'],
               description: 'Choose which environment to deploy: Blue or Green')
        choice(name: 'DOCKER_TAG',
               choices: ['blue', 'green'],
               description: 'Choose the Docker image tag for the deployment')
        booleanParam(name: 'SWITCH_TRAFFIC',
                     defaultValue: false,
                     description: 'Switch traffic between Blue and Green')
    }

    environment {
        IMAGE_NAME    = 'aniket1805/bankapp'
        TAG           = "${params.DOCKER_TAG}"
        KUBE_NAMESPACE = 'webapps'
        SCANNER_HOME  = tool 'sonar-scanner'
    }

    stages {

        stage('Git Checkout') {
            steps { checkout scm }
        }

        stage('Compile')        { steps { sh 'mvn -B compile' } }
        stage('Test')           { steps { sh 'mvn -B test -DskipTests=true' } }
        stage('Trivy FS Scan')  { steps { sh 'trivy fs --format table -o fs.html .' } }

        stage('Sonarqube Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh "${SCANNER_HOME}/bin/sonar-scanner " +
                       "-Dsonar.projectKey=multitier " +
                       "-Dsonar.projectName=multitier " +
                       "-Dsonar.java.binaries=target"
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

        stage('Build') {
            steps { sh 'mvn -B package -DskipTests=true' }
        }

        stage('Publish Artifact to Nexus') {
            steps {
                withMaven(globalMavenSettingsConfig: 'maven-settings',
                          maven: 'maven3',
                          traceability: true) {
                    sh 'mvn -B deploy -DskipTests=true'
                }
            }
        }

        stage('Docker build') {
            steps {
                withDockerRegistry(credentialsId: 'docker-cred') {
                    sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                }
            }
        }

        stage('Trivy Image Scan') {
            steps { sh "trivy image --format table -o image.html ${IMAGE_NAME}:${TAG}" }
        }

        stage('Docker Push Image') {
            steps {
                withDockerRegistry(credentialsId: 'docker-cred') {
                    sh "docker push ${IMAGE_NAME}:${TAG}"
                }
            }
        }

        /* ---------------- Kubernetes deployment & blue‑green logic ---------------- */

        stage('Deploy MySQL') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'anikettestproject-cluster',
                               namespace: KUBE_NAMESPACE) {
                    sh "kubectl apply -f mysql-ds.yml -n ${KUBE_NAMESPACE}"
                }
            }
        }

        stage('Deploy Service') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'anikettestproject-cluster',
                               namespace: KUBE_NAMESPACE) {
                    sh """
                       if ! kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}; then
                           kubectl apply -f bankapp-service.yml -n ${KUBE_NAMESPACE}
                       fi
                       """
                }
            }
        }

        stage('Deploy App') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'anikettestproject-cluster',
                               namespace: KUBE_NAMESPACE) {
                    def deploymentFile = (params.DEPLOY_ENV == 'blue')
                                         ? 'app-deployment-blue.yml'
                                         : 'app-deployment-green.yml'
                    sh "kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}"
                }
            }
        }

        stage('Switch Traffic') {
            when { expression { params.SWITCH_TRAFFIC } }
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'anikettestproject-cluster',
                               namespace: KUBE_NAMESPACE) {
                    sh """
                       kubectl patch service bankapp-service \
                         -p '{\"spec\":{\"selector\":{\"app\":\"bankapp\",\"version\":\"${params.DEPLOY_ENV}\"}}}' \
                         -n ${KUBE_NAMESPACE}
                       """
                }
                echo "Traffic switched to the ${params.DEPLOY_ENV} environment."
            }
        }

        stage('Verify') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'anikettestproject-cluster',
                               namespace: KUBE_NAMESPACE) {
                    sh """
                       kubectl get pods -l version=${params.DEPLOY_ENV} -n ${KUBE_NAMESPACE}
                       kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}
                       """
                }
            }
        }
    }
}

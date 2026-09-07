pipeline {
    agent any

    parameters {
        string(name: 'BUILD_RETENTION', defaultValue: '10', description: 'Number of builds to retain')
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: params.BUILD_RETENTION))
    }

    stages {
        stage('Build') {
            steps {
                sh 'echo "JAVA_HOME=$JAVA_HOME"; java -version; mvn -version'
                sh 'mvn -B -ntp clean compile'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn -B -ntp test'
            }
            post {
                always {
                    junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
                }
            }
        }

        stage('Sonar Scan') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh 'sonar-scanner'
                }
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Publish Artifacts') {
            steps {
                sh 'mvn -B -ntp package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }
    }
}

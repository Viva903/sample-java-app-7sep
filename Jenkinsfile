pipeline {
    agent any

    parameters {
        string(name: 'JDK_TOOL', defaultValue: 'jdk17', description: 'Name of the JDK installation configured in Jenkins Global Tool Configuration')
        string(name: 'MAVEN_TOOL', defaultValue: 'maven3', description: 'Name of the Maven installation configured in Jenkins Global Tool Configuration')
        string(name: 'BUILD_RETENTION', defaultValue: '10', description: 'Number of builds to retain')
    }

    tools {
        jdk params.JDK_TOOL
        maven params.MAVEN_TOOL
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
                sh 'mvn -B -ntp clean compile'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn -B -ntp test'
            }
        }
    }

    post {
        always {
            junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
        }
    }
}

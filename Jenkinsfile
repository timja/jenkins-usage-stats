pipeline {
    agent {
        label 'docker && linux-amd64'
    }
    stages {
        stage('Lint') {
            steps {
                sh "make lint"
            }
        }
        stage('Build') {
            steps {
                sh "make build"
            }
        }
        stage('Test') {
            steps {
                sh "make test"
            }
        }
    }
}

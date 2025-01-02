#!/usr/bin/env groovy

node('docker && linux-amd64') {
  stage('Checkout') {
    checkout scm
  }

  stage('Lint') {
    def goPath = "${pwd tmp: true}/gopath"
    env.PATH = "GOPATH=${goPath}:${env.PATH}"
    sh "make lint"
  }

  stage('Build') {
    sh "make build"
  }

  stage('Test') {
    sh "make test"
  }
}

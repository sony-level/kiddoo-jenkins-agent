pipeline {
    agent {
        label 'amd64-Debian-12'
    }

    options {
        timestamps()
        timeout(time: 10, unit: 'MINUTES')
        skipDefaultCheckout(true)
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Setup') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                '''
            }
        }

        stage('Lint & Format') {
            parallel {
                stage('Python - Black') {
                    steps {
                        sh '''
                            . .venv/bin/activate
                            black --check --diff python/
                        '''
                    }
                }
                stage('Python - Ruff') {
                    steps {
                        sh '''
                            . .venv/bin/activate
                            ruff check python/
                        '''
                    }
                }
                stage('Shell - ShellCheck') {
                    steps {
                        sh '''
                            shellcheck bash/create_server.sh bash/lib/*.sh
                        '''
                    }
                }
            }
        }

        stage('Dry Run') {
            steps {
                sh '''
                    . .venv/bin/activate
                    python3 python/create_server.py --dry-run
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        failure {
            echo 'Pipeline failed — check logs above.'
        }
        success {
            echo 'All checks passed.'
        }
    }
}

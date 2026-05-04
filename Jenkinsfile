pipeline {
    agent {
        label 'Debian-12'
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

        stage('Auto-format') {
            steps {
                sh '''
                    . .venv/bin/activate
                    black python/
                    ruff check --fix python/ || true
                '''
                script {
                    def changes = sh(script: 'git diff --name-only', returnStdout: true).trim()
                    if (changes) {
                        withCredentials([string(credentialsId: 'Github-token', variable: 'GH_TOKEN')]) {
                            sh '''
                                git config user.email "jenkins@kiddoo-infra"
                                git config user.name "Jenkins CI"

                                BRANCH="auto-format/${BUILD_NUMBER}"
                                git checkout -b "$BRANCH"
                                git add -A
                                git commit -m "style: auto-format Python (black + ruff)"
                                git push "https://x-access-token:${GH_TOKEN}@github.com/sony-level/kiddoo-jenkins-agent.git" "$BRANCH"

                                PR_URL=$(gh pr create \
                                    --repo sony-level/kiddoo-jenkins-agent \
                                    --base master \
                                    --head "$BRANCH" \
                                    --title "style: auto-format Python" \
                                    --body "Auto-format par Jenkins (black + ruff).")

                                gh pr merge "$PR_URL" --squash --delete-branch

                                echo "Auto-format PR created and merged: ${PR_URL}"
                            '''
                        }
                    } else {
                        echo 'Code already formatted — nothing to do.'
                    }
                }
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

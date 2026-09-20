// Jenkinsfile - CI pipeline for this monorepo.
//
// WORKING ASSUMPTION: this repo is scanned with `changeset`/path filters so
// only the service(s) that actually changed are built - in a real org with
// 8 teams you do NOT want every team's push rebuilding every service.
// For POC clarity, this pipeline is parameterized by SERVICE_NAME and would
// be invoked once per changed service (via a small detection stage or a
// multibranch/matrix job per service directory).
//
// GITOPS BOUNDARY (important): this pipeline builds, tests, scans and
// PUSHES AN IMAGE. It never runs `kubectl apply` and never talks to any
// Kubernetes cluster directly. The only Kubernetes-facing side effect is a
// git commit that bumps an immutable image tag in the Helm values file for
// the target environment. ArgoCD (running in-cluster) detects that commit
// and reconciles the cluster to match. This keeps the cluster's desired
// state entirely in Git and keeps Jenkins from ever needing cluster
// credentials - a deliberate blast-radius reduction.

pipeline {
    agent any

    parameters {
        string(name: 'SERVICE_NAME', defaultValue: 'catalog-api', description: 'Service directory under services/')
        choice(name: 'TARGET_ENV', choices: ['dev', 'staging', 'prod'], description: 'Environment to promote to')
    }

    environment {
        REGISTRY        = 'registry.example.com/devops-poc'
        SERVICE_DIR      = "services/${params.SERVICE_NAME}"
        // Immutable tag: git short SHA + build number. Never "latest" -
        // "latest" makes rollbacks non-deterministic and breaks the
        // promise that what was scanned is exactly what gets deployed.
        IMAGE_TAG        = "${env.GIT_COMMIT.take(7)}-${env.BUILD_NUMBER}"
        IMAGE_FULL       = "${REGISTRY}/${params.SERVICE_NAME}:${IMAGE_TAG}"
    }

    options {
        timestamps()
        // Never let a stuck stage hang the pipeline / agent indefinitely.
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Unit Tests') {
            steps {
                dir("${SERVICE_DIR}") {
                    sh '''
                        python3 -m venv .venv
                        . .venv/bin/activate
                        pip install --quiet -r requirements.txt pytest
                        pytest tests/ -v --junitxml=test-results.xml
                    '''
                }
            }
            post {
                always {
                    junit "${SERVICE_DIR}/test-results.xml"
                }
            }
        }

        stage('SAST - Dependency & Static Analysis') {
            steps {
                dir("${SERVICE_DIR}") {
                    sh '''
                        . .venv/bin/activate
                        pip install --quiet pip-audit bandit
                        # Dependency scan: known CVEs in pinned requirements.
                        pip-audit -r requirements.txt --format json --output pip-audit-report.json || true
                        # Static analysis: insecure code patterns (e.g. eval, hardcoded secrets).
                        bandit -r src/ -f json -o bandit-report.json || true
                    '''
                }
                // WORKING ASSUMPTION: "|| true" here means findings are
                // captured but don't hard-fail the build automatically.
                // In a real rollout, this pipeline would start in
                // "report-only" mode for 1-2 sprints so teams can burn down
                // existing findings, then flip to hard-fail on
                // HIGH/CRITICAL only - hard-failing on day one on a repo
                // with existing tech debt just trains people to bypass CI.
                script {
                    def audit = readJSON file: "${SERVICE_DIR}/pip-audit-report.json"
                    if (audit && audit.size() > 0) {
                        echo "pip-audit found ${audit.size()} dependency finding(s) - see archived report."
                    }
                }
            }
        }

        stage('Build Image') {
            steps {
                dir("${SERVICE_DIR}") {
                    sh """
                        docker build \
                            --build-arg IMAGE_TAG=${IMAGE_TAG} \
                            -t ${IMAGE_FULL} .
                    """
                }
            }
        }

        stage('Container Scan - Trivy') {
            steps {
                sh """
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --format table \
                        ${IMAGE_FULL}
                """
                // Hard gate: unlike the SAST stage above, this DOES fail
                // the build (--exit-code 1) on HIGH/CRITICAL image
                // vulnerabilities. Rationale for the asymmetry: base-image
                // CVEs are typically fixed by a trivial base-image bump, so
                // the fix cost is low and the risk (shipping a known-
                // exploitable container) is high - a different cost/risk
                // trade-off than application-level SAST findings above.
            }
        }

        stage('Push Image') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry-creds',
                                                    usernameVariable: 'REG_USER',
                                                    passwordVariable: 'REG_PASS')]) {
                    sh """
                        echo "\$REG_PASS" | docker login ${REGISTRY} -u "\$REG_USER" --password-stdin
                        docker push ${IMAGE_FULL}
                    """
                }
            }
        }

        stage('GitOps: Bump Image Tag') {
            when { branch 'main' }
            steps {
                // This is the ONLY step that touches the deployment
                // config, and it only ever touches the dev values file
                // automatically. Promotion to staging/prod is a deliberate
                // human-triggered action (see promote.Jenkinsfile / ArgoCD
                // sync policy below) - auto-promoting straight to prod on
                // every merge is explicitly out of scope for this design.
                sh """
                    yq -i '.image.tag = "${IMAGE_TAG}"' helm/${params.SERVICE_NAME}/values-dev.yaml
                    git config user.email "jenkins-ci@example.com"
                    git config user.name "jenkins-ci"
                    git add helm/${params.SERVICE_NAME}/values-dev.yaml
                    git commit -m "ci: bump ${params.SERVICE_NAME} to ${IMAGE_TAG} [dev]"
                    git push origin HEAD:main
                """
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: "${SERVICE_DIR}/*-report.json", allowEmptyArchive: true
        }
        failure {
            // WORKING ASSUMPTION: Slack webhook configured as a Jenkins
            // credential; kept generic here since the actual channel/token
            // is org-specific and out of scope for this POC.
            echo "Pipeline failed for ${params.SERVICE_NAME} - notify #devops-alerts"
        }
    }
}

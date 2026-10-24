// Jenkins declarative pipeline for the MERN microservices app.
//
// Flow: checkout -> build images -> push to ECR -> deploy to EKS via Helm -> notify (SNS).
//
// Jenkins setup expected on the EC2 controller/agent:
//   - Docker engine + the Docker Pipeline plugin
//   - AWS CLI v2, kubectl, helm, eksctl installed on the agent
//   - "Pipeline: AWS Steps" plugin (REQUIRED - this pipeline uses withAWS)
//   - Credentials: an "AWS Credentials" entry (id set in AWS_CRED_ID below)
//   - GitHub webhook pointing at  http://<jenkins>/github-webhook/  (triggers on push)
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  // Trigger a build automatically on each push from GitHub.
  triggers {
    githubPush()
  }

  parameters {
    booleanParam(name: 'DEPLOY', defaultValue: true,
                 description: 'Deploy to EKS via Helm after pushing images')
  }

  environment {
    // Non-secret identifiers only. The account id, ECR registry host and the
    // full SNS ARN are derived at runtime in the Init stage so the account id
    // never appears in this committed file.
    AWS_REGION      = 'ap-south-1'
    EKS_CLUSTER     = 'mern-eks-cluster'
    HELM_RELEASE    = 'mern'
    HELM_NAMESPACE  = 'mern'
    SNS_TOPIC_NAME  = 'mern-deployments'
    // Short git SHA is computed in the Init stage and reused as the image tag.
    IMAGE_TAG       = 'latest'
    // Jenkins "AWS Credentials" entry id. withAWS(...) injects temporary
    // AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY for the wrapped steps only.
    AWS_CRED_ID     = 'aws-credentials-dnu'
  }

  stages {
    stage('Init') {
      steps {
        script {
          // Derive the account id from the active credentials; never hardcoded.
          withAWS(credentials: env.AWS_CRED_ID, region: env.AWS_REGION) {
            env.AWS_ACCOUNT_ID = sh(
              returnStdout: true,
              script: 'aws sts get-caller-identity --query Account --output text'
            ).trim()
          }

          // Compose the ECR registry host and SNS ARN from the derived id.
          env.ECR_REGISTRY  = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.SNS_TOPIC_ARN = "arn:aws:sns:${env.AWS_REGION}:${env.AWS_ACCOUNT_ID}:${env.SNS_TOPIC_NAME}"

          // Image tag is the short git SHA of the checked-out commit.
          env.IMAGE_TAG = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          echo "Building image tag: ${env.IMAGE_TAG} (account resolved, id not logged)"
        }
      }
    }

    stage('ECR Login') {
      steps {
        withAWS(credentials: env.AWS_CRED_ID, region: env.AWS_REGION) {
          sh '''
            aws ecr get-login-password --region "$AWS_REGION" \
              | docker login --username AWS --password-stdin "$ECR_REGISTRY"
          '''
        }
      }
    }

    stage('Build & Push Images') {
      // Build the three images in parallel for speed.
      parallel {
        stage('frontend') {
          steps { buildAndPush('mern-frontend', './frontend') }
        }
        stage('helloService') {
          steps { buildAndPush('mern-hello-service', './backend/helloService') }
        }
        stage('profileService') {
          steps { buildAndPush('mern-profile-service', './backend/profileService') }
        }
      }
    }

    stage('Deploy to EKS') {
      when { expression { return params.DEPLOY } }
      steps {
        withAWS(credentials: env.AWS_CRED_ID, region: env.AWS_REGION) {
          sh '''
            aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION"

            helm upgrade --install "$HELM_RELEASE" ./helm/mern-stack \
              --namespace "$HELM_NAMESPACE" --create-namespace \
              --set image.registry="$ECR_REGISTRY" \
              --set image.tag="$IMAGE_TAG" \
              --wait --timeout 10m

            kubectl -n "$HELM_NAMESPACE" rollout status deployment/mern-frontend
            kubectl -n "$HELM_NAMESPACE" rollout status deployment/mern-hello-service
            kubectl -n "$HELM_NAMESPACE" rollout status deployment/mern-profile-service
          '''
        }
      }
    }
  }

  post {
    success {
      notifySns("SUCCESS",
        "Build #${env.BUILD_NUMBER} for ${env.JOB_NAME} succeeded (tag ${env.IMAGE_TAG}).")
    }
    failure {
      notifySns("FAILURE",
        "Build #${env.BUILD_NUMBER} for ${env.JOB_NAME} FAILED. See ${env.BUILD_URL}")
    }
    always {
      sh 'docker image prune -f || true'
    }
  }
}

// ----- Helper functions -----

// Build one image and push both the SHA tag and :latest to ECR.
def buildAndPush(String repo, String context) {
  sh """
    docker build -t ${repo}:${IMAGE_TAG} ${context}
    docker tag ${repo}:${IMAGE_TAG} ${ECR_REGISTRY}/${repo}:${IMAGE_TAG}
    docker tag ${repo}:${IMAGE_TAG} ${ECR_REGISTRY}/${repo}:latest
    docker push ${ECR_REGISTRY}/${repo}:${IMAGE_TAG}
    docker push ${ECR_REGISTRY}/${repo}:latest
  """
}

// Publish a deployment event to SNS for ChatOps notifications.
def notifySns(String status, String message) {
  // SNS_TOPIC_ARN is empty if the build failed before the Init stage set it;
  // skip the publish in that case to avoid a malformed command.
  if (!env.SNS_TOPIC_ARN) {
    echo "SNS_TOPIC_ARN not set yet; skipping notification."
    return
  }
  withAWS(credentials: env.AWS_CRED_ID, region: env.AWS_REGION) {
    sh """
      aws sns publish \
        --region ${AWS_REGION} \
        --topic-arn ${SNS_TOPIC_ARN} \
        --subject "Jenkins ${status}: ${JOB_NAME} #${BUILD_NUMBER}" \
        --message "${message}" || echo "SNS publish failed (non-fatal)"
    """
  }
}

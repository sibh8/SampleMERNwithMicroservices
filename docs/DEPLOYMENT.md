# Deployment Guide

End-to-end steps to deploy the MERN microservices app to AWS. Commands assume a
Linux/macOS shell (e.g. the Jenkins EC2 host). Windows equivalents are noted
where they differ.

Default settings used throughout:

| Setting       | Value               |
|---------------|---------------------|
| AWS region    | `ap-south-1`        |
| EKS cluster   | `mern-eks-cluster`  |
| Namespace     | `mern`              |
| SNS topic     | `mern-deployments`  |
| ECR repos     | `mern-frontend`, `mern-hello-service`, `mern-profile-service` |

> Replace the placeholder AWS account id `123456789012` in `Jenkinsfile` and
> `helm/mern-stack/values.yaml` with your real account id.

---

## Step 1: Version control (fork and sync)

1. Fork `https://github.com/UnpredictablePrashant/StreamingApp.git` into your account.
2. Clone your fork and add the upstream remote. See [FORK_AND_SYNC.md](./FORK_AND_SYNC.md).

## Step 2: Containerize

Dockerfiles live beside each component:

- `frontend/Dockerfile` (multi-stage: build with Node, serve with nginx)
- `backend/helloService/Dockerfile`
- `backend/profileService/Dockerfile`

Test everything locally with Docker Compose:

```bash
docker compose up --build
# Frontend:       http://localhost:8080
# helloService:   http://localhost:3001
# profileService: http://localhost:3002
```

## Step 3: AWS CLI

```bash
./scripts/configure-aws-cli.sh      # installs + runs 'aws configure'
aws sts get-caller-identity         # verify credentials
```

## Step 4: Push images to ECR

```bash
# Linux/macOS
AWS_REGION=ap-south-1 IMAGE_TAG=v1 ./scripts/ecr-build-push.sh
```

```powershell
# Windows
$env:AWS_REGION="ap-south-1"; $env:IMAGE_TAG="v1"; ./scripts/ecr-build-push.ps1
```

The script creates each ECR repository if missing, then builds, tags, and pushes.

## Step 5: Jenkins CI

1. Launch an EC2 instance (Amazon Linux 2023, open ports 22 and 8080).
2. Install Jenkins + tooling:
   ```bash
   ./scripts/install-jenkins-ec2.sh
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
3. In Jenkins: install plugins (Git, GitHub, Pipeline, Docker Pipeline,
   Pipeline: AWS Steps, Credentials Binding).
4. Add credentials: either attach an IAM role to the EC2 instance or add an
   `aws-credentials` secret.
5. Create a Pipeline job pointing at your fork; it uses the repo `Jenkinsfile`.
6. Add a GitHub webhook to `http://<jenkins-host>:8080/github-webhook/` so every
   push triggers a build. The pipeline builds, pushes to ECR, and deploys via Helm.

## Step 6: EKS cluster

```bash
cd eks
./create-cluster.sh    # ~15-20 min; also installs ALB controller + metrics-server
kubectl get nodes
```

## Step 7: Deploy with Helm

```bash
helm upgrade --install mern ./helm/mern-stack \
  --namespace mern --create-namespace \
  --set image.registry=<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com \
  --set image.tag=v1 --wait

kubectl -n mern get pods,svc,hpa,ingress
# Get the public ALB hostname:
kubectl -n mern get ingress mern-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Step 8: Monitoring and logging

```bash
./monitoring/install-container-insights.sh
./monitoring/create-cloudwatch-alarms.sh
aws cloudwatch put-dashboard --dashboard-name mern-stack \
  --dashboard-body file://monitoring/cloudwatch-dashboard.json
```

## Step 9 (bonus): SNS ChatOps

```bash
./chatops/create-sns-topic.sh
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
./chatops/deploy-slack-notifier.sh
# Test:
aws sns publish --topic-arn arn:aws:sns:ap-south-1:<ACCOUNT_ID>:mern-deployments \
  --subject "Test" --message "Hello from SNS"
```

## Validation checklist

- [ ] `kubectl -n mern get pods` shows all pods `Running` and `Ready`.
- [ ] ALB hostname loads the frontend in a browser.
- [ ] `helloService` returns `Hello World`; `profileService` `/fetchUser` responds.
- [ ] `kubectl -n mern get hpa` shows active autoscalers.
- [ ] CloudWatch Container Insights shows metrics for the `mern` namespace.
- [ ] A test SNS publish arrives in Slack/Teams.

For the full phase-by-phase validation procedure (commands, expected output, and
troubleshooting for each layer), see [TESTING.md](./TESTING.md).

## Teardown

Minimal path:

```bash
helm -n mern uninstall mern
cd eks && ./delete-cluster.sh
```

That removes the app and cluster, but leaves ECR repos, CloudWatch alarms/logs,
the SNS topic, and the Lambda behind (some keep billing). For a complete, ordered
cleanup of every resource, see [TEARDOWN.md](./TEARDOWN.md) or run
`./scripts/teardown-aws.sh` (AWS) and `./scripts/teardown-podman.ps1` (local).

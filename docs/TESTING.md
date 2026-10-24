# Validation and Testing Guide

How to verify every layer of the system is working, from local containers up to
the full AWS deployment. Each section lists the command, what a healthy result
looks like, and how to fix common failures.

Default settings referenced below:

| Setting     | Value               |
|-------------|---------------------|
| AWS region  | `ap-south-1`        |
| EKS cluster | `mern-eks-cluster`  |
| Namespace   | `mern`              |
| SNS topic   | `mern-deployments`  |

Work through the phases in order. Each phase assumes the previous one passed.

---

## Phase 0: Prerequisites

Confirm the required tools are installed and on PATH.

```bash
docker --version
docker compose version
node --version
aws --version
kubectl version --client
eksctl version
helm version
```

Expected: each prints a version with no "command not found". `helm` and a running
Docker engine are required for the local phases; the AWS phases also need valid
credentials (`aws sts get-caller-identity` returns your account).

---

## Phase 1: Local build and smoke test (Docker Compose)

This validates the Dockerfiles and the app wiring without touching AWS.

```bash
docker compose up --build -d
docker compose ps
```

Expected: `mongo`, `hello-service`, `profile-service`, and `frontend` are all
`Up`. The backend containers report `(healthy)` after ~15s (Docker HEALTHCHECK).

### 1.1 helloService

```bash
curl http://localhost:3001/
curl http://localhost:3001/health
```

Expected: `{"msg":"Hello World"}` and `{"status":"OK"}`.

### 1.2 profileService

```bash
curl http://localhost:3002/health
# Add a user, then fetch the list
curl -X POST http://localhost:3002/addUser \
  -H "Content-Type: application/json" \
  -d '{"name":"Ada","age":36}'
curl http://localhost:3002/fetchUser
```

Expected: `{"status":"OK"}`, then `{"msg":"User Added Successfully"}`, then a JSON
array containing the Ada document. This also confirms MongoDB connectivity.

### 1.3 Frontend

Open `http://localhost:8080` in a browser.

Expected: the page shows the "Hello World" heading (proves the browser reached
helloService) and a Profile section listing any users (proves it reached
profileService). Check the browser devtools Network tab — requests to
`localhost:3001` and `localhost:3002` should return `200`.

### 1.4 Runtime config check

```bash
curl http://localhost:8080/config.js
```

Expected: a `window.__APP_CONFIG__` object with the two backend URLs. This proves
the nginx entrypoint regenerated config from the compose environment variables.

### Teardown

```bash
docker compose down -v
```

### Troubleshooting

- `profile-service` restarting: MongoDB wasn't ready. `docker compose logs profile-service` and confirm `MONGO_URL` resolves to the `mongo` service.
- Frontend loads but Profile is empty: expected if no users were added; add one via 1.2.
- CORS errors in the browser: both backends enable `cors()`, so this usually means the backend URL in `config.js` is wrong.

---

## Phase 2: Image registry (ECR)

```bash
AWS_REGION=ap-south-1 IMAGE_TAG=test ./scripts/ecr-build-push.sh
aws ecr describe-repositories --region ap-south-1 \
  --query 'repositories[].repositoryName'
aws ecr list-images --repository-name mern-frontend --region ap-south-1
```

Expected: three repositories (`mern-frontend`, `mern-hello-service`,
`mern-profile-service`) exist, and each lists the `test` and `latest` tags.

---

## Phase 3: Jenkins CI/CD

### 3.1 Jenkins is reachable

Open `http://<jenkins-ec2-ip>:8080` and log in. The pipeline job for your fork
should exist.

### 3.2 Pipeline runs end to end

Trigger a build (Build Now) or push a commit to your fork.

Expected console output progresses through: Init → ECR Login →
Build & Push Images (3 parallel) → Deploy to EKS → `SUCCESS`. The build should
finish green.

### 3.3 Webhook auto-trigger

Make a trivial commit and push.

Expected: a new build starts automatically within a few seconds. In GitHub →
Settings → Webhooks, the delivery to `/github-webhook/` shows a green checkmark
(HTTP 200).

### Troubleshooting

- Build fails at ECR Login: the EC2 instance role or `aws-credentials` lacks ECR permissions.
- Deploy stage fails: `kubectl`/`helm` not on the Jenkins agent PATH, or kubeconfig not updated. The pipeline runs `aws eks update-kubeconfig` — confirm the role can access the cluster.

---

## Phase 4: EKS cluster

```bash
aws eks update-kubeconfig --name mern-eks-cluster --region ap-south-1
kubectl get nodes
kubectl get pods -A
```

Expected: 2+ nodes in `Ready` state; system pods (coredns, aws-node, kube-proxy)
`Running`. The `aws-load-balancer-controller` pods in `kube-system` are `Running`,
and `metrics-server` is present (required for HPA).

```bash
kubectl top nodes
```

Expected: CPU/memory figures print. If this errors, metrics-server isn't ready —
HPAs will not scale until it is.

---

## Phase 5: Helm deployment

```bash
# Render-only check before applying (no cluster changes)
helm lint ./helm/mern-stack
helm template mern ./helm/mern-stack \
  --set image.registry=<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com \
  --set image.tag=test | head -n 40
```

Expected: `helm lint` reports `1 chart(s) linted, 0 chart(s) failed`, and
`helm template` renders valid YAML.

```bash
helm upgrade --install mern ./helm/mern-stack \
  --namespace mern --create-namespace \
  --set image.registry=<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com \
  --set image.tag=test --wait --timeout 10m

kubectl -n mern get pods,svc,hpa,ingress
```

Expected: all `mern-frontend`, `mern-hello-service`, `mern-profile-service`, and
`mern-mongo` pods `Running`/`Ready`; three HPAs listed; one Ingress named
`mern-ingress`.

### 5.1 Probes and secrets

```bash
kubectl -n mern describe pod -l app=mern-profile-service | grep -A2 -i mongo_url
kubectl -n mern get secret mern-mongo-secret
```

Expected: `MONGO_URL` is injected from the `mern-mongo-secret` secret (value not
printed in plaintext in the describe output).

---

## Phase 6: End-to-end through the ALB

```bash
ALB=$(kubectl -n mern get ingress mern-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$ALB"
```

Wait 2-3 minutes for the ALB to become active, then:

```bash
curl -I "http://$ALB/"              # frontend
curl "http://$ALB/api/hello/"       # helloService (if prefix routing configured)
```

Expected: the frontend returns `HTTP/1.1 200`. Open `http://$ALB/` in a browser
and confirm the app renders.

> Note: as documented in `helm/mern-stack/templates/ingress.yaml`, the backends
> serve at root paths. If `/api/hello` returns 404, either add an ALB rewrite rule
> or point the frontend env (`HELLO_SERVICE_URL`/`PROFILE_SERVICE_URL`) at the
> backends' own hostnames. Verify by checking the browser Network tab resolves the
> backend calls with `200`.

---

## Phase 7: Autoscaling (HPA)

Confirm the HPAs read metrics and scale under load.

```bash
kubectl -n mern get hpa
```

Expected: each HPA shows a real CPU percentage in the TARGETS column (e.g.
`5%/70%`), not `<unknown>`. `<unknown>` means metrics-server isn't delivering
metrics yet.

Generate load against a backend and watch it scale:

```bash
# In one terminal, drive traffic (adjust host to your ALB or port-forward)
kubectl -n mern run load --image=busybox --restart=Never -it --rm -- \
  /bin/sh -c "while true; do wget -q -O- http://mern-hello-service:3001/ >/dev/null; done"

# In another terminal, watch replicas grow toward maxReplicas
kubectl -n mern get hpa -w
kubectl -n mern get pods -l app=mern-hello-service -w
```

Expected: as CPU crosses 70%, the replica count climbs (up to 5). After stopping
the load, it scales back down after the cooldown window.

---

## Phase 8: Monitoring and logging (CloudWatch)

```bash
# Container Insights add-on is active
aws eks describe-addon --cluster-name mern-eks-cluster \
  --addon-name amazon-cloudwatch-observability --region ap-south-1 \
  --query 'addon.status'

# Application log group exists and receives logs
aws logs describe-log-groups --region ap-south-1 \
  --log-group-name-prefix "/aws/containerinsights/mern-eks-cluster"
```

Expected: add-on status `ACTIVE`; log groups for `application`, `dataplane`, and
`host` exist. In the console, **CloudWatch → Insights → Container Insights** shows
the `mern` namespace workloads with live CPU/memory.

```bash
# Alarms were created
aws cloudwatch describe-alarms --region ap-south-1 \
  --alarm-name-prefix "mern-" --query 'MetricAlarms[].AlarmName'
```

Expected: the per-service CPU/memory alarms and `mern-node-high-cpu` are listed.

---

## Phase 9: ChatOps (SNS to Slack/Teams)

```bash
# Topic exists
aws sns list-topics --region ap-south-1 --query "Topics[?contains(TopicArn, 'mern-deployments')]"

# Lambda is subscribed
aws sns list-subscriptions --region ap-south-1 \
  --query "Subscriptions[?contains(TopicArn, 'mern-deployments')].[Protocol,Endpoint]" --output table

# Fire a test message
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws sns publish --region ap-south-1 \
  --topic-arn "arn:aws:sns:ap-south-1:${ACCOUNT_ID}:mern-deployments" \
  --subject "Validation test" \
  --message "ChatOps pipeline test from TESTING.md"
```

Expected: a `lambda` subscription is listed, and the test message appears in your
Slack/Teams channel within a few seconds. If it does not arrive, check the Lambda
logs:

```bash
aws logs tail /aws/lambda/mern-sns-to-slack --region ap-south-1 --since 5m
```

Common cause: `SLACK_WEBHOOK_URL` not set on the function, or the webhook URL is
invalid/expired.

---

## Validation summary checklist

Copy this into your submission to show coverage.

- [ ] Phase 1: Local compose stack healthy; all three endpoints respond; UI renders.
- [ ] Phase 2: Three ECR repos exist with pushed image tags.
- [ ] Phase 3: Jenkins pipeline runs green; webhook auto-triggers on push.
- [ ] Phase 4: EKS nodes Ready; LB controller + metrics-server running.
- [ ] Phase 5: `helm lint` passes; all pods Running; secret-injected MONGO_URL.
- [ ] Phase 6: ALB serves the frontend; backend calls return 200.
- [ ] Phase 7: HPAs show live metrics and scale under load.
- [ ] Phase 8: Container Insights ACTIVE; log groups present; alarms created.
- [ ] Phase 9: SNS test message delivered to Slack/Teams.

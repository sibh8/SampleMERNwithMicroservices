# Teardown Guide

How to remove every resource this project creates. Work top to bottom — the
**order matters**. In particular, delete the Helm release (and its ALB) *before*
the EKS cluster, otherwise the load balancer and its security groups block the
VPC/subnet deletion and `eksctl delete cluster` stalls or leaves orphans.

Resources that keep billing while idle: the EKS control plane, worker EC2 nodes,
the ALB, NAT gateways, and EBS volumes. Delete these promptly after validation.

Defaults referenced below:

| Setting     | Value               |
|-------------|---------------------|
| AWS region  | `ap-south-1`        |
| EKS cluster | `mern-eks-cluster`  |
| Namespace   | `mern`              |
| SNS topic   | `mern-deployments`  |
| Lambda      | `mern-sns-to-slack` |

---

## Quick path (scripted)

From a bash shell (e.g. the Jenkins EC2 host) with AWS creds configured:

```bash
# Removes Helm release + ALB, cluster, ECR, CloudWatch, SNS, Lambda, IAM leftovers.
# Prompts before the cluster delete. Set FORCE=1 to skip prompts.
./scripts/teardown-aws.sh
```

For the local containers, from PowerShell:

```powershell
./scripts/teardown-podman.ps1
```

The rest of this document is the manual, step-by-step equivalent so you can run or
verify each piece individually.

---

## 1. Helm release and the ALB (do this first)

```bash
aws eks update-kubeconfig --name mern-eks-cluster --region ap-south-1

# Uninstall the app. This deletes the Ingress, which tells the ALB controller
# to delete the ALB and its target groups.
helm -n mern uninstall mern

# Wait and confirm the Ingress (and thus the ALB) is gone before continuing.
kubectl -n mern get ingress
kubectl delete namespace mern --ignore-not-found
```

Verify no ALB lingers (the controller should have removed it):

```bash
aws elbv2 describe-load-balancers --region ap-south-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-mern')].LoadBalancerArn"
```

Expected: an empty list `[]`. If an ALB remains, delete it by ARN with
`aws elbv2 delete-load-balancer --load-balancer-arn <arn>`.

---

## 2. CloudWatch (alarms, dashboard, log groups)

```bash
# Alarms created by monitoring/create-cloudwatch-alarms.sh
aws cloudwatch delete-alarms --region ap-south-1 --alarm-names \
  mern-frontend-high-cpu mern-frontend-high-mem \
  mern-hello-service-high-cpu mern-hello-service-high-mem \
  mern-profile-service-high-cpu mern-profile-service-high-mem \
  mern-node-high-cpu

# Dashboard
aws cloudwatch delete-dashboards --region ap-south-1 --dashboard-names mern-stack

# Container Insights log groups (these keep storing/charging if left behind)
for grp in application dataplane host performance; do
  aws logs delete-log-group --region ap-south-1 \
    --log-group-name "/aws/containerinsights/mern-eks-cluster/$grp" 2>/dev/null || true
done

# EKS control-plane log group
aws logs delete-log-group --region ap-south-1 \
  --log-group-name "/aws/eks/mern-eks-cluster/cluster" 2>/dev/null || true
```

> The `amazon-cloudwatch-observability` EKS add-on is removed automatically when
> the cluster is deleted in step 4. To remove it earlier:
> `aws eks delete-addon --cluster-name mern-eks-cluster --addon-name amazon-cloudwatch-observability --region ap-south-1`

---

## 3. ChatOps (SNS topic + Lambda + IAM role)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# SNS topic (also removes its subscriptions)
aws sns delete-topic --region ap-south-1 \
  --topic-arn "arn:aws:sns:ap-south-1:${ACCOUNT_ID}:mern-deployments"

# Lambda function
aws lambda delete-function --region ap-south-1 --function-name mern-sns-to-slack 2>/dev/null || true

# Lambda log group
aws logs delete-log-group --region ap-south-1 \
  --log-group-name "/aws/lambda/mern-sns-to-slack" 2>/dev/null || true

# Lambda IAM role (detach managed policy first)
aws iam detach-role-policy --role-name mern-sns-to-slack-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role --role-name mern-sns-to-slack-role 2>/dev/null || true
```

---

## 4. EKS cluster

With the ALB gone (step 1), this deletes the cluster, managed node group, VPC,
subnets, NAT gateway, and the CloudFormation stacks eksctl created.

```bash
cd eks
./delete-cluster.sh
# equivalent to:
# eksctl delete cluster --name mern-eks-cluster --region ap-south-1 --wait
```

After it finishes, confirm the eksctl CloudFormation stacks are gone:

```bash
aws cloudformation list-stacks --region ap-south-1 \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName,'eksctl-mern-eks-cluster')].StackName"
```

Expected: `[]`.

---

## 5. IAM artifacts from cluster setup

`eks/create-cluster.sh` created an IAM policy and an IRSA service-account role for
the AWS Load Balancer Controller. The IRSA role is removed with the cluster, but
the standalone policy is not.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Only delete if no other cluster uses it.
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" 2>/dev/null \
  || echo "Policy in use or already gone; skipping."
```

---

## 6. ECR repositories (and images)

These store images and incur storage charges. `--force` deletes even if images
are present.

```bash
for repo in mern-frontend mern-hello-service mern-profile-service; do
  aws ecr delete-repository --region ap-south-1 --repository-name "$repo" --force 2>/dev/null || true
done
```

---

## 7. Jenkins EC2 instance

Jenkins was installed on an EC2 instance you launched manually (Step 4 of the
project). Terminate it from the console or CLI when done:

```bash
# Find it (adjust the filter to how you tagged/named it)
aws ec2 describe-instances --region ap-south-1 \
  --filters "Name=tag:Name,Values=jenkins*" \
  --query "Reservations[].Instances[].InstanceId" --output text

# Terminate (irreversible)
aws ec2 terminate-instances --region ap-south-1 --instance-ids <instance-id>
```

Also delete any key pair, security group, and Elastic IP you created just for it.

---

## 8. Local containers (Podman)

```powershell
# Remove the running stack (ignore errors if some are already gone)
podman rm -f mern-frontend mern-profile-service mern-hello-service mern-mongo

# Remove the network and data volume
podman network rm mern-net
podman volume rm mongo-data        # omit to keep the DB data

# Optional: remove the built images
podman rmi mern-frontend:local mern-hello-service:local mern-profile-service:local docker.io/library/mongo:7

# If you used podman-compose instead of individual containers:
# podman-compose -f docker-compose.yml down -v
```

If you ran the stack with Docker instead: replace `podman` with `docker`, or use
`docker compose down -v` from the repo root.

---

## Final verification

```bash
aws eks list-clusters --region ap-south-1
aws ecr describe-repositories --region ap-south-1 --query 'repositories[].repositoryName'
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName'
aws sns list-topics --region ap-south-1 --query "Topics[?contains(TopicArn,'mern')]"
aws cloudwatch describe-alarms --region ap-south-1 --alarm-name-prefix mern- --query 'MetricAlarms[].AlarmName'
```

Expected: empty results across the board. Finally, open the AWS **Billing >
Cost Explorer** and the **EC2 / VPC** consoles to confirm no NAT gateway, EIP, or
EBS volume is still active.

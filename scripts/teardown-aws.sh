#!/usr/bin/env bash
#
# Tear down all AWS resources created by this project, in safe order.
# Order matters: Helm/ALB first, then CloudWatch, ChatOps, cluster, IAM, ECR.
#
# Usage:
#   ./scripts/teardown-aws.sh          # prompts before the cluster delete
#   FORCE=1 ./scripts/teardown-aws.sh  # no prompts
#
# This is destructive. It deletes the EKS cluster, ECR images, alarms,
# SNS topic, and Lambda. It does NOT terminate the Jenkins EC2 instance
# (do that manually - see docs/TEARDOWN.md).
#
set -uo pipefail   # not -e: we want to continue past already-deleted resources

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mern-eks-cluster}"
NAMESPACE="${NAMESPACE:-mern}"
HELM_RELEASE="${HELM_RELEASE:-mern}"
TOPIC_NAME="${TOPIC_NAME:-mern-deployments}"
LAMBDA_NAME="${LAMBDA_NAME:-mern-sns-to-slack}"
LAMBDA_ROLE="${LAMBDA_ROLE:-mern-sns-to-slack-role}"
FORCE="${FORCE:-0}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

confirm() {
  [ "$FORCE" = "1" ] && return 0
  read -r -p "$1 [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

echo "==> Target account ${ACCOUNT_ID}, region ${AWS_REGION}"
confirm "Proceed with teardown of all MERN project resources?" || { echo "Aborted."; exit 0; }

# ---- 1. Helm release + ALB ----
echo "==> [1/6] Uninstalling Helm release and app (removes the ALB)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 \
  && {
    helm -n "$NAMESPACE" uninstall "$HELM_RELEASE" 2>/dev/null || echo "    (release not found)"
    echo "    waiting 60s for the ALB controller to delete the load balancer..."
    sleep 60
    kubectl delete namespace "$NAMESPACE" --ignore-not-found 2>/dev/null
  } || echo "    (cluster not reachable; skipping Helm uninstall)"

# ---- 2. CloudWatch alarms, dashboard, log groups ----
echo "==> [2/6] Deleting CloudWatch alarms, dashboard, and log groups"
aws cloudwatch delete-alarms --region "$AWS_REGION" --alarm-names \
  mern-frontend-high-cpu mern-frontend-high-mem \
  mern-hello-service-high-cpu mern-hello-service-high-mem \
  mern-profile-service-high-cpu mern-profile-service-high-mem \
  mern-node-high-cpu 2>/dev/null
aws cloudwatch delete-dashboards --region "$AWS_REGION" --dashboard-names mern-stack 2>/dev/null
for grp in application dataplane host performance; do
  aws logs delete-log-group --region "$AWS_REGION" \
    --log-group-name "/aws/containerinsights/${CLUSTER_NAME}/${grp}" 2>/dev/null
done
aws logs delete-log-group --region "$AWS_REGION" \
  --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster" 2>/dev/null

# ---- 3. ChatOps: SNS, Lambda, IAM role ----
echo "==> [3/6] Deleting SNS topic, Lambda, and its IAM role"
aws sns delete-topic --region "$AWS_REGION" \
  --topic-arn "arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${TOPIC_NAME}" 2>/dev/null
aws lambda delete-function --region "$AWS_REGION" --function-name "$LAMBDA_NAME" 2>/dev/null
aws logs delete-log-group --region "$AWS_REGION" \
  --log-group-name "/aws/lambda/${LAMBDA_NAME}" 2>/dev/null
aws iam detach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role --role-name "$LAMBDA_ROLE" 2>/dev/null

# ---- 4. EKS cluster ----
echo "==> [4/6] Deleting the EKS cluster (~10-15 min)"
if confirm "Delete EKS cluster ${CLUSTER_NAME}?"; then
  eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait
else
  echo "    skipped cluster delete."
fi

# ---- 5. IAM policy from cluster setup ----
echo "==> [5/6] Deleting AWSLoadBalancerControllerIAMPolicy (if unused)"
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" 2>/dev/null \
  || echo "    (policy in use or already gone)"

# ---- 6. ECR repositories ----
echo "==> [6/6] Deleting ECR repositories and images"
for repo in mern-frontend mern-hello-service mern-profile-service; do
  aws ecr delete-repository --region "$AWS_REGION" --repository-name "$repo" --force 2>/dev/null \
    && echo "    deleted ${repo}" || echo "    ${repo} already gone"
done

echo ""
echo "==> AWS teardown complete."
echo "    NOTE: the Jenkins EC2 instance is NOT terminated by this script."
echo "    Terminate it manually (see docs/TEARDOWN.md section 7)."

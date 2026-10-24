#!/usr/bin/env bash
#
# Create the EKS cluster and install the AWS Load Balancer Controller
# (needed so the frontend Ingress provisions an ALB).
#
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mern-eks-cluster}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

cd "$(dirname "$0")"

echo "==> Creating EKS cluster (this takes ~15-20 minutes)"
eksctl create cluster -f cluster.yaml

echo "==> Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

echo "==> Creating IAM policy for AWS Load Balancer Controller (idempotent)"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  curl -sLo iam-policy.json \
    https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
  aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json
  rm -f iam-policy.json
fi

echo "==> Creating IRSA service account for the LB controller"
eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "$POLICY_ARN" \
  --approve --override-existing-serviceaccounts

echo "==> Installing AWS Load Balancer Controller via Helm"
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

echo "==> Installing metrics-server (required for HPA)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "==> Cluster ready. Nodes:"
kubectl get nodes

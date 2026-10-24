#!/usr/bin/env bash
# Tear down the EKS cluster to avoid ongoing charges.
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mern-eks-cluster}"

echo "==> Deleting EKS cluster ${CLUSTER_NAME} (this can take ~10-15 minutes)"
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait
echo "==> Done."

#!/usr/bin/env bash
#
# Enable Amazon CloudWatch Container Insights on the EKS cluster.
# Installs the CloudWatch agent (metrics) and Fluent Bit (logs) into the
# amazon-cloudwatch namespace using the official quickstart manifest.
#
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mern-eks-cluster}"

echo "==> Attaching CloudWatchAgentServerPolicy to the node instance role"
# Finds the node group role and attaches the managed policy so the agent
# and Fluent Bit can publish metrics/logs.
NODE_ROLE=$(aws eks describe-nodegroup \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name mern-ng \
  --region "$AWS_REGION" \
  --query 'nodegroup.nodeRole' --output text | awk -F'/' '{print $NF}')
aws iam attach-role-policy \
  --role-name "$NODE_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || true

echo "==> Deploying the CloudWatch Observability EKS add-on (Container Insights)"
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name amazon-cloudwatch-observability \
  --region "$AWS_REGION" \
  || echo "    (add-on may already exist, continuing)"

echo "==> Waiting for the add-on to become ACTIVE"
aws eks wait addon-active \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name amazon-cloudwatch-observability \
  --region "$AWS_REGION" || true

echo "==> Container Insights enabled. View in CloudWatch console:"
echo "    CloudWatch > Insights > Container Insights  (cluster: ${CLUSTER_NAME})"
echo "    Application logs: log group /aws/containerinsights/${CLUSTER_NAME}/application"

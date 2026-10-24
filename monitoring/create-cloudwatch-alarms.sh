#!/usr/bin/env bash
#
# Create CloudWatch alarms for the MERN workloads running on EKS.
# Alarms notify the SNS topic used for ChatOps (deployment/ops alerts).
#
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mern-eks-cluster}"
NAMESPACE="${NAMESPACE:-mern}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:mern-deployments}"

# Container Insights publishes pod metrics under the ContainerInsights namespace.
create_cpu_alarm() {
  local service="$1"
  echo "==> Creating high-CPU alarm for ${service}"
  aws cloudwatch put-metric-alarm \
    --region "$AWS_REGION" \
    --alarm-name "mern-${service}-high-cpu" \
    --alarm-description "Avg pod CPU > 80% for ${service}" \
    --namespace "ContainerInsights" \
    --metric-name "pod_cpu_utilization" \
    --dimensions Name=ClusterName,Value="$CLUSTER_NAME" Name=Namespace,Value="$NAMESPACE" Name=Service,Value="$service" \
    --statistic Average \
    --period 60 \
    --evaluation-periods 3 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching \
    --alarm-actions "$SNS_TOPIC_ARN"
}

create_mem_alarm() {
  local service="$1"
  echo "==> Creating high-memory alarm for ${service}"
  aws cloudwatch put-metric-alarm \
    --region "$AWS_REGION" \
    --alarm-name "mern-${service}-high-mem" \
    --alarm-description "Avg pod memory > 80% for ${service}" \
    --namespace "ContainerInsights" \
    --metric-name "pod_memory_utilization" \
    --dimensions Name=ClusterName,Value="$CLUSTER_NAME" Name=Namespace,Value="$NAMESPACE" Name=Service,Value="$service" \
    --statistic Average \
    --period 60 \
    --evaluation-periods 3 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching \
    --alarm-actions "$SNS_TOPIC_ARN"
}

for svc in mern-frontend mern-hello-service mern-profile-service; do
  create_cpu_alarm "$svc"
  create_mem_alarm "$svc"
done

# Node-level alarm: any node running hot.
echo "==> Creating node high-CPU alarm"
aws cloudwatch put-metric-alarm \
  --region "$AWS_REGION" \
  --alarm-name "mern-node-high-cpu" \
  --alarm-description "Node CPU utilization > 85%" \
  --namespace "ContainerInsights" \
  --metric-name "node_cpu_utilization" \
  --dimensions Name=ClusterName,Value="$CLUSTER_NAME" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_TOPIC_ARN"

echo "==> Alarms created. They publish to: ${SNS_TOPIC_ARN}"

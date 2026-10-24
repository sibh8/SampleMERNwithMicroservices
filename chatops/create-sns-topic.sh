#!/usr/bin/env bash
#
# Create the SNS topic used for deployment and operational events.
# Jenkins and CloudWatch alarms publish here; a Lambda forwards to Slack/Teams.
#
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
TOPIC_NAME="${TOPIC_NAME:-mern-deployments}"

echo "==> Creating SNS topic: ${TOPIC_NAME}"
TOPIC_ARN=$(aws sns create-topic \
  --name "$TOPIC_NAME" \
  --region "$AWS_REGION" \
  --query 'TopicArn' --output text)

echo "==> Topic ARN: ${TOPIC_ARN}"
echo ""
echo "Optional: subscribe an email endpoint for quick testing:"
echo "  aws sns subscribe --region ${AWS_REGION} --topic-arn ${TOPIC_ARN} \\"
echo "    --protocol email --notification-endpoint you@example.com"
echo ""
echo "Export this for the Jenkins pipeline / alarm scripts:"
echo "  export SNS_TOPIC_ARN=${TOPIC_ARN}"

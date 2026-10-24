#!/usr/bin/env bash
#
# Package and deploy the SNS->Slack Lambda, then subscribe it to the SNS topic.
# Requires an existing Slack (or Teams) incoming webhook URL.
#
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
TOPIC_NAME="${TOPIC_NAME:-mern-deployments}"
FUNCTION_NAME="${FUNCTION_NAME:-mern-sns-to-slack}"
ROLE_NAME="${ROLE_NAME:-mern-sns-to-slack-role}"
: "${SLACK_WEBHOOK_URL:?Set SLACK_WEBHOOK_URL to your Slack/Teams incoming webhook}"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${TOPIC_NAME}"

cd "$(dirname "$0")"

echo "==> Creating IAM role for Lambda (idempotent)"
cat > trust-policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
JSON

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  echo "    waiting for role propagation..."
  sleep 10
fi
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

echo "==> Packaging Lambda"
zip -j function.zip sns-to-slack-lambda.py >/dev/null

echo "==> Creating or updating the Lambda function"
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" --zip-file fileb://function.zip --region "$AWS_REGION"
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "Variables={SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}}" --region "$AWS_REGION"
else
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --handler sns-to-slack-lambda.handler \
    --role "$ROLE_ARN" \
    --zip-file fileb://function.zip \
    --timeout 15 \
    --environment "Variables={SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}}" \
    --region "$AWS_REGION"
fi

FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

echo "==> Allowing SNS to invoke the Lambda"
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id sns-invoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn "$TOPIC_ARN" \
  --region "$AWS_REGION" 2>/dev/null || echo "    permission already exists"

echo "==> Subscribing the Lambda to the SNS topic"
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol lambda \
  --notification-endpoint "$FUNCTION_ARN" \
  --region "$AWS_REGION"

rm -f function.zip trust-policy.json
echo "==> Done. Test with:"
echo "    aws sns publish --region ${AWS_REGION} --topic-arn ${TOPIC_ARN} --subject 'Test' --message 'Hello from SNS'"

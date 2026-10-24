#!/usr/bin/env bash
#
# Attach the ECR + SNS permissions the Jenkins pipeline user needs.
# The pipeline fails at "ECR Login" if the IAM user lacks
# ecr:GetAuthorizationToken. This grants ECR push/pull + sns:Publish.
#
# Run with ADMIN credentials (a profile that can write IAM), NOT the pipeline
# user's own keys - a user cannot grant itself permissions.
#
# Usage:
#   ./scripts/attach-iam-permissions.sh
#   IAM_USER=gradedassignment3 AWS_PROFILE=admin ./scripts/attach-iam-permissions.sh
#
set -euo pipefail

USER_NAME="${IAM_USER:-gradedassignment3}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
TOPIC_NAME="${TOPIC_NAME:-mern-deployments}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "==> Account ${ACCOUNT_ID}, attaching permissions to user '${USER_NAME}'"

POLICY_FILE="$(mktemp)"
cat > "$POLICY_FILE" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "ECRPushPull",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SNSPublish",
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${TOPIC_NAME}"
    },
    {
      "Sid": "EKSDescribe",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
JSON

echo "==> Putting inline policy 'mern-ecr-sns'"
aws iam put-user-policy \
  --user-name "$USER_NAME" \
  --policy-name mern-ecr-sns \
  --policy-document "file://${POLICY_FILE}"

rm -f "$POLICY_FILE"

echo "==> Done. Inline policies now on '${USER_NAME}':"
aws iam list-user-policies --user-name "$USER_NAME"
echo ""
echo "Re-run the Jenkins job (DEPLOY unchecked) - ECR Login should now succeed."

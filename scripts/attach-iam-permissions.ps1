<#
.SYNOPSIS
  Attach the ECR + SNS permissions the Jenkins pipeline user needs
  (Windows/PowerShell).

.DESCRIPTION
  The pipeline fails at "ECR Login" if the IAM user lacks
  ecr:GetAuthorizationToken. This script attaches an inline policy granting the
  ECR push/pull actions and sns:Publish to the topic.

  Run this with ADMIN credentials (a profile that can write IAM), NOT the
  pipeline user's own keys - a user cannot grant itself permissions.

.PARAMETER UserName
  The IAM user to attach the policy to. Defaults to env:IAM_USER or
  'gradedassignment3'.

.EXAMPLE
  ./scripts/attach-iam-permissions.ps1
  ./scripts/attach-iam-permissions.ps1 -UserName gradedassignment3 -AwsProfile admin
#>
param(
    [string]$UserName,
    [string]$AwsRegion,
    [string]$TopicName,
    [string]$AwsProfile
)
$ErrorActionPreference = "Stop"

if (-not $UserName)  { $UserName  = if ($env:IAM_USER)   { $env:IAM_USER }   else { "gradedassignment3" } }
if (-not $AwsRegion) { $AwsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { "ap-south-1" } }
if (-not $TopicName) { $TopicName = if ($env:TOPIC_NAME) { $env:TOPIC_NAME } else { "mern-deployments" } }

# Optional --profile passthrough for running with admin creds.
$profileArgs = @()
if ($AwsProfile) { $profileArgs = @("--profile", $AwsProfile) }

# Resolve the account id so the SNS resource ARN is scoped correctly.
$AccountId = (aws sts get-caller-identity @profileArgs --query Account --output text)
Write-Host "==> Account $AccountId, attaching permissions to user '$UserName'"

$policy = @"
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
      "Resource": "arn:aws:sns:${AwsRegion}:${AccountId}:${TopicName}"
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
"@

$policyFile = Join-Path $env:TEMP "mern-ecr-sns-policy.json"
Set-Content -Path $policyFile -Value $policy -Encoding ascii

Write-Host "==> Putting inline policy 'mern-ecr-sns'"
aws iam put-user-policy @profileArgs `
    --user-name $UserName `
    --policy-name mern-ecr-sns `
    --policy-document "file://$policyFile"

Remove-Item $policyFile -Force -ErrorAction SilentlyContinue

Write-Host "==> Done. Inline policies now on '$UserName':"
aws iam list-user-policies @profileArgs --user-name $UserName
Write-Host ""
Write-Host "Re-run the Jenkins job (DEPLOY unchecked) - ECR Login should now succeed."

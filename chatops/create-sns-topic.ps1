<#
.SYNOPSIS
  Create the SNS topic used for deployment and operational events (Windows/PowerShell).

.DESCRIPTION
  PowerShell equivalent of create-sns-topic.sh. Jenkins and CloudWatch alarms
  publish here; a Lambda forwards to Slack/Teams.

.EXAMPLE
  ./chatops/create-sns-topic.ps1
  $env:AWS_REGION="us-east-1"; $env:TOPIC_NAME="my-topic"; ./chatops/create-sns-topic.ps1
#>
$ErrorActionPreference = "Stop"

$AwsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { "ap-south-1" }
$TopicName = if ($env:TOPIC_NAME) { $env:TOPIC_NAME } else { "mern-deployments" }

Write-Host "==> Creating SNS topic: $TopicName"
$TopicArn = aws sns create-topic `
  --name $TopicName `
  --region $AwsRegion `
  --query 'TopicArn' --output text

Write-Host "==> Topic ARN: $TopicArn"
Write-Host ""
Write-Host "Optional: subscribe an email endpoint for quick testing:"
Write-Host "  aws sns subscribe --region $AwsRegion --topic-arn $TopicArn ``"
Write-Host "    --protocol email --notification-endpoint you@example.com"
Write-Host ""
Write-Host "Export this for the Jenkins pipeline / alarm scripts:"
Write-Host "  `$env:SNS_TOPIC_ARN = `"$TopicArn`""

<#
.SYNOPSIS
  Package and deploy the SNS->Slack Lambda, then subscribe it to the SNS topic
  (Windows/PowerShell equivalent of deploy-slack-notifier.sh).

.DESCRIPTION
  Requires an existing Slack (or Teams) incoming webhook URL in SLACK_WEBHOOK_URL.
  Creates the Lambda IAM role (idempotent), zips the function, creates or updates
  it, allows SNS to invoke it, and subscribes it to the topic.

.EXAMPLE
  $env:SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
  ./chatops/deploy-slack-notifier.ps1
#>
$ErrorActionPreference = "Stop"

$AwsRegion    = if ($env:AWS_REGION)    { $env:AWS_REGION }    else { "ap-south-1" }
$TopicName    = if ($env:TOPIC_NAME)    { $env:TOPIC_NAME }    else { "mern-deployments" }
$FunctionName = if ($env:FUNCTION_NAME) { $env:FUNCTION_NAME } else { "mern-sns-to-slack" }
$RoleName     = if ($env:ROLE_NAME)     { $env:ROLE_NAME }     else { "mern-sns-to-slack-role" }

if (-not $env:SLACK_WEBHOOK_URL) {
    throw "Set SLACK_WEBHOOK_URL to your Slack/Teams incoming webhook"
}
$SlackWebhookUrl = $env:SLACK_WEBHOOK_URL

$AwsAccountId = (aws sts get-caller-identity --query Account --output text)
$TopicArn     = "arn:aws:sns:${AwsRegion}:${AwsAccountId}:${TopicName}"

# Work from the script's directory (where the Lambda source lives).
Set-Location $PSScriptRoot

Write-Host "==> Creating IAM role for Lambda (idempotent)"
$trustPolicy = @'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
'@
Set-Content -Path "trust-policy.json" -Value $trustPolicy -Encoding ascii

aws iam get-role --role-name $RoleName *> $null
if ($LASTEXITCODE -ne 0) {
    aws iam create-role --role-name $RoleName `
        --assume-role-policy-document file://trust-policy.json
    aws iam attach-role-policy --role-name $RoleName `
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    Write-Host "    waiting for role propagation..."
    Start-Sleep -Seconds 10
}
$RoleArn = "arn:aws:iam::${AwsAccountId}:role/${RoleName}"

Write-Host "==> Packaging Lambda"
# -j equivalent: place the file at the zip root with no directory structure.
if (Test-Path "function.zip") { Remove-Item "function.zip" -Force }
Compress-Archive -Path "sns-to-slack-lambda.py" -DestinationPath "function.zip" -Force

Write-Host "==> Creating or updating the Lambda function"
aws lambda get-function --function-name $FunctionName --region $AwsRegion *> $null
if ($LASTEXITCODE -eq 0) {
    aws lambda update-function-code `
        --function-name $FunctionName --zip-file fileb://function.zip --region $AwsRegion
    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --environment "Variables={SLACK_WEBHOOK_URL=$SlackWebhookUrl}" --region $AwsRegion
} else {
    aws lambda create-function `
        --function-name $FunctionName `
        --runtime python3.12 `
        --handler sns-to-slack-lambda.handler `
        --role $RoleArn `
        --zip-file fileb://function.zip `
        --timeout 15 `
        --environment "Variables={SLACK_WEBHOOK_URL=$SlackWebhookUrl}" `
        --region $AwsRegion
}

$FunctionArn = (aws lambda get-function --function-name $FunctionName `
    --region $AwsRegion --query 'Configuration.FunctionArn' --output text)

Write-Host "==> Allowing SNS to invoke the Lambda"
aws lambda add-permission `
    --function-name $FunctionName `
    --statement-id sns-invoke `
    --action lambda:InvokeFunction `
    --principal sns.amazonaws.com `
    --source-arn $TopicArn `
    --region $AwsRegion *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "    permission already exists" }

Write-Host "==> Subscribing the Lambda to the SNS topic"
aws sns subscribe `
    --topic-arn $TopicArn `
    --protocol lambda `
    --notification-endpoint $FunctionArn `
    --region $AwsRegion

Remove-Item -Force "function.zip", "trust-policy.json" -ErrorAction SilentlyContinue
Write-Host "==> Done. Test with:"
Write-Host "    aws sns publish --region $AwsRegion --topic-arn $TopicArn --subject 'Test' --message 'Hello from SNS'"

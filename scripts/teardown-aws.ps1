<#
.SYNOPSIS
  Tear down all AWS resources created by this project, in safe order
  (Windows/PowerShell equivalent of teardown-aws.sh).

.DESCRIPTION
  Order matters: Helm/ALB first, then CloudWatch, ChatOps, cluster, IAM, ECR.
  This is destructive. It deletes the EKS cluster, ECR images, alarms, SNS topic,
  and Lambda. It does NOT terminate the Jenkins EC2 instance (do that manually -
  see docs/TEARDOWN.md).

.PARAMETER Force
  Skip all confirmation prompts.

.EXAMPLE
  ./scripts/teardown-aws.ps1
  ./scripts/teardown-aws.ps1 -Force
#>
param(
    [switch]$Force
)
# Continue past already-deleted resources (mirrors the sh set -uo, not -e).
$ErrorActionPreference = "Continue"

$AwsRegion   = if ($env:AWS_REGION)   { $env:AWS_REGION }   else { "ap-south-1" }
$ClusterName = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "mern-eks-cluster" }
$Namespace   = if ($env:NAMESPACE)    { $env:NAMESPACE }    else { "mern" }
$HelmRelease = if ($env:HELM_RELEASE) { $env:HELM_RELEASE } else { "mern" }
$TopicName   = if ($env:TOPIC_NAME)   { $env:TOPIC_NAME }   else { "mern-deployments" }
$LambdaName  = if ($env:LAMBDA_NAME)  { $env:LAMBDA_NAME }  else { "mern-sns-to-slack" }
$LambdaRole  = if ($env:LAMBDA_ROLE)  { $env:LAMBDA_ROLE }  else { "mern-sns-to-slack-role" }

$AccountId = (aws sts get-caller-identity --query Account --output text)

function Confirm-Step {
    param([string]$Message)
    if ($Force) { return $true }
    $ans = Read-Host "$Message [y/N]"
    return ($ans -eq "y" -or $ans -eq "Y")
}

Write-Host "==> Target account $AccountId, region $AwsRegion"
if (-not (Confirm-Step "Proceed with teardown of all MERN project resources?")) {
    Write-Host "Aborted."
    return
}

# ---- 1. Helm release + ALB ----
Write-Host "==> [1/6] Uninstalling Helm release and app (removes the ALB)"
aws eks update-kubeconfig --name $ClusterName --region $AwsRegion *> $null
if ($LASTEXITCODE -eq 0) {
    helm -n $Namespace uninstall $HelmRelease 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "    (release not found)" }
    Write-Host "    waiting 60s for the ALB controller to delete the load balancer..."
    Start-Sleep -Seconds 60
    kubectl delete namespace $Namespace --ignore-not-found 2>$null
} else {
    Write-Host "    (cluster not reachable; skipping Helm uninstall)"
}

# ---- 2. CloudWatch alarms, dashboard, log groups ----
Write-Host "==> [2/6] Deleting CloudWatch alarms, dashboard, and log groups"
aws cloudwatch delete-alarms --region $AwsRegion --alarm-names `
    mern-frontend-high-cpu mern-frontend-high-mem `
    mern-hello-service-high-cpu mern-hello-service-high-mem `
    mern-profile-service-high-cpu mern-profile-service-high-mem `
    mern-node-high-cpu 2>$null
aws cloudwatch delete-dashboards --region $AwsRegion --dashboard-names mern-stack 2>$null
foreach ($grp in @("application", "dataplane", "host", "performance")) {
    aws logs delete-log-group --region $AwsRegion `
        --log-group-name "/aws/containerinsights/$ClusterName/$grp" 2>$null
}
aws logs delete-log-group --region $AwsRegion `
    --log-group-name "/aws/eks/$ClusterName/cluster" 2>$null

# ---- 3. ChatOps: SNS, Lambda, IAM role ----
Write-Host "==> [3/6] Deleting SNS topic, Lambda, and its IAM role"
aws sns delete-topic --region $AwsRegion `
    --topic-arn "arn:aws:sns:${AwsRegion}:${AccountId}:${TopicName}" 2>$null
aws lambda delete-function --region $AwsRegion --function-name $LambdaName 2>$null
aws logs delete-log-group --region $AwsRegion `
    --log-group-name "/aws/lambda/$LambdaName" 2>$null
aws iam detach-role-policy --role-name $LambdaRole `
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>$null
aws iam delete-role --role-name $LambdaRole 2>$null

# ---- 4. EKS cluster ----
Write-Host "==> [4/6] Deleting the EKS cluster (~10-15 min)"
if (Confirm-Step "Delete EKS cluster $ClusterName?") {
    eksctl delete cluster --name $ClusterName --region $AwsRegion --wait
} else {
    Write-Host "    skipped cluster delete."
}

# ---- 5. IAM policy from cluster setup ----
Write-Host "==> [5/6] Deleting AWSLoadBalancerControllerIAMPolicy (if unused)"
aws iam delete-policy `
    --policy-arn "arn:aws:iam::${AccountId}:policy/AWSLoadBalancerControllerIAMPolicy" 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "    (policy in use or already gone)" }

# ---- 6. ECR repositories ----
Write-Host "==> [6/6] Deleting ECR repositories and images"
foreach ($repo in @("mern-frontend", "mern-hello-service", "mern-profile-service")) {
    aws ecr delete-repository --region $AwsRegion --repository-name $repo --force 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host "    deleted $repo" } else { Write-Host "    $repo already gone" }
}

Write-Host ""
Write-Host "==> AWS teardown complete."
Write-Host "    NOTE: the Jenkins EC2 instance is NOT terminated by this script."
Write-Host "    Terminate it manually (see docs/TEARDOWN.md section 7)."

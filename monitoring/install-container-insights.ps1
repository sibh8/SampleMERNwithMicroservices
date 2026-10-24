<#
.SYNOPSIS
  Enable Amazon CloudWatch Container Insights on the EKS cluster
  (Windows/PowerShell equivalent of install-container-insights.sh).

.DESCRIPTION
  Attaches CloudWatchAgentServerPolicy to the node role and installs the
  amazon-cloudwatch-observability EKS add-on (CloudWatch agent + Fluent Bit).

.EXAMPLE
  ./monitoring/install-container-insights.ps1
#>
$ErrorActionPreference = "Stop"

$AwsRegion   = if ($env:AWS_REGION)   { $env:AWS_REGION }   else { "ap-south-1" }
$ClusterName = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "mern-eks-cluster" }

Write-Host "==> Attaching CloudWatchAgentServerPolicy to the node instance role"
# Finds the node group role ARN and keeps only the role name (part after the last '/').
$NodeRoleArn = (aws eks describe-nodegroup `
    --cluster-name $ClusterName `
    --nodegroup-name mern-ng `
    --region $AwsRegion `
    --query 'nodegroup.nodeRole' --output text)
$NodeRole = ($NodeRoleArn -split '/')[-1]

# Non-fatal: continue even if the attach fails (e.g. already attached).
aws iam attach-role-policy `
    --role-name $NodeRole `
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
if ($LASTEXITCODE -ne 0) { Write-Host "    (attach failed or already attached, continuing)" }

Write-Host "==> Deploying the CloudWatch Observability EKS add-on (Container Insights)"
aws eks create-addon `
    --cluster-name $ClusterName `
    --addon-name amazon-cloudwatch-observability `
    --region $AwsRegion
if ($LASTEXITCODE -ne 0) { Write-Host "    (add-on may already exist, continuing)" }

Write-Host "==> Waiting for the add-on to become ACTIVE"
aws eks wait addon-active `
    --cluster-name $ClusterName `
    --addon-name amazon-cloudwatch-observability `
    --region $AwsRegion
if ($LASTEXITCODE -ne 0) { Write-Host "    (wait returned non-zero, continuing)" }

Write-Host "==> Container Insights enabled. View in CloudWatch console:"
Write-Host "    CloudWatch > Insights > Container Insights  (cluster: $ClusterName)"
Write-Host "    Application logs: log group /aws/containerinsights/$ClusterName/application"

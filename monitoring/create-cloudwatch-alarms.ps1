<#
.SYNOPSIS
  Create CloudWatch alarms for the MERN workloads on EKS (Windows/PowerShell
  equivalent of create-cloudwatch-alarms.sh).

.DESCRIPTION
  Creates per-service CPU and memory alarms plus a node CPU alarm. All alarms
  publish to the SNS topic used for ChatOps.

.EXAMPLE
  ./monitoring/create-cloudwatch-alarms.ps1
#>
$ErrorActionPreference = "Stop"

$AwsRegion    = if ($env:AWS_REGION)    { $env:AWS_REGION }    else { "ap-south-1" }
$ClusterName  = if ($env:CLUSTER_NAME)  { $env:CLUSTER_NAME }  else { "mern-eks-cluster" }
$Namespace    = if ($env:NAMESPACE)     { $env:NAMESPACE }     else { "mern" }
$AwsAccountId = (aws sts get-caller-identity --query Account --output text)
$SnsTopicArn  = if ($env:SNS_TOPIC_ARN) { $env:SNS_TOPIC_ARN } else { "arn:aws:sns:${AwsRegion}:${AwsAccountId}:mern-deployments" }

# Container Insights publishes pod metrics under the ContainerInsights namespace.
function New-CpuAlarm {
    param([string]$Service)
    Write-Host "==> Creating high-CPU alarm for $Service"
    aws cloudwatch put-metric-alarm `
        --region $AwsRegion `
        --alarm-name "mern-$Service-high-cpu" `
        --alarm-description "Avg pod CPU > 80% for $Service" `
        --namespace "ContainerInsights" `
        --metric-name "pod_cpu_utilization" `
        --dimensions "Name=ClusterName,Value=$ClusterName" "Name=Namespace,Value=$Namespace" "Name=Service,Value=$Service" `
        --statistic Average `
        --period 60 `
        --evaluation-periods 3 `
        --threshold 80 `
        --comparison-operator GreaterThanThreshold `
        --treat-missing-data notBreaching `
        --alarm-actions $SnsTopicArn
}

function New-MemAlarm {
    param([string]$Service)
    Write-Host "==> Creating high-memory alarm for $Service"
    aws cloudwatch put-metric-alarm `
        --region $AwsRegion `
        --alarm-name "mern-$Service-high-mem" `
        --alarm-description "Avg pod memory > 80% for $Service" `
        --namespace "ContainerInsights" `
        --metric-name "pod_memory_utilization" `
        --dimensions "Name=ClusterName,Value=$ClusterName" "Name=Namespace,Value=$Namespace" "Name=Service,Value=$Service" `
        --statistic Average `
        --period 60 `
        --evaluation-periods 3 `
        --threshold 80 `
        --comparison-operator GreaterThanThreshold `
        --treat-missing-data notBreaching `
        --alarm-actions $SnsTopicArn
}

foreach ($svc in @("mern-frontend", "mern-hello-service", "mern-profile-service")) {
    New-CpuAlarm -Service $svc
    New-MemAlarm -Service $svc
}

# Node-level alarm: any node running hot.
Write-Host "==> Creating node high-CPU alarm"
aws cloudwatch put-metric-alarm `
    --region $AwsRegion `
    --alarm-name "mern-node-high-cpu" `
    --alarm-description "Node CPU utilization > 85%" `
    --namespace "ContainerInsights" `
    --metric-name "node_cpu_utilization" `
    --dimensions "Name=ClusterName,Value=$ClusterName" `
    --statistic Average `
    --period 60 `
    --evaluation-periods 3 `
    --threshold 85 `
    --comparison-operator GreaterThanThreshold `
    --treat-missing-data notBreaching `
    --alarm-actions $SnsTopicArn

Write-Host "==> Alarms created. They publish to: $SnsTopicArn"

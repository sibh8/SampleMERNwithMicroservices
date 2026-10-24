<#
.SYNOPSIS
  Create the EKS cluster and install the AWS Load Balancer Controller
  (Windows/PowerShell equivalent of create-cluster.sh).

.DESCRIPTION
  Creates the cluster from cluster.yaml, updates kubeconfig, sets up the IAM
  policy + IRSA service account for the ALB controller, installs it via Helm,
  and installs metrics-server (required for HPA).

.EXAMPLE
  ./eks/create-cluster.ps1
#>
$ErrorActionPreference = "Stop"

$AwsRegion   = if ($env:AWS_REGION)   { $env:AWS_REGION }   else { "ap-south-1" }
$ClusterName = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "mern-eks-cluster" }
$AwsAccountId = (aws sts get-caller-identity --query Account --output text)

# Work from the script's directory (where cluster.yaml lives).
Set-Location $PSScriptRoot

Write-Host "==> Creating EKS cluster (this takes ~15-20 minutes)"
eksctl create cluster -f cluster.yaml
if ($LASTEXITCODE -ne 0) {
    throw "eksctl create cluster failed (exit $LASTEXITCODE). Fix the error above (e.g. unsupported Kubernetes version in cluster.yaml) and re-run. No later steps were executed."
}

Write-Host "==> Updating kubeconfig"
aws eks update-kubeconfig --name $ClusterName --region $AwsRegion

Write-Host "==> Creating IAM policy for AWS Load Balancer Controller (idempotent)"
$PolicyArn = "arn:aws:iam::${AwsAccountId}:policy/AWSLoadBalancerControllerIAMPolicy"
aws iam get-policy --policy-arn $PolicyArn *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json" `
        -OutFile "iam-policy.json"
    aws iam create-policy `
        --policy-name AWSLoadBalancerControllerIAMPolicy `
        --policy-document file://iam-policy.json
    Remove-Item -Force "iam-policy.json" -ErrorAction SilentlyContinue
}

Write-Host "==> Creating IRSA service account for the LB controller"
eksctl create iamserviceaccount `
    --cluster $ClusterName `
    --region $AwsRegion `
    --namespace kube-system `
    --name aws-load-balancer-controller `
    --attach-policy-arn $PolicyArn `
    --approve --override-existing-serviceaccounts

Write-Host "==> Installing AWS Load Balancer Controller via Helm"
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
    -n kube-system `
    --set clusterName=$ClusterName `
    --set serviceAccount.create=false `
    --set serviceAccount.name=aws-load-balancer-controller

Write-Host "==> Installing metrics-server (required for HPA)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

Write-Host "==> Cluster ready. Nodes:"
kubectl get nodes

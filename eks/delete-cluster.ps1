<#
.SYNOPSIS
  Tear down the EKS cluster to avoid ongoing charges (Windows/PowerShell).

.DESCRIPTION
  PowerShell equivalent of delete-cluster.sh.

.EXAMPLE
  ./eks/delete-cluster.ps1
#>
$ErrorActionPreference = "Stop"

$AwsRegion   = if ($env:AWS_REGION)   { $env:AWS_REGION }   else { "ap-south-1" }
$ClusterName = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "mern-eks-cluster" }

Write-Host "==> Deleting EKS cluster $ClusterName (this can take ~10-15 minutes)"
eksctl delete cluster --name $ClusterName --region $AwsRegion --wait
Write-Host "==> Done."

<#
.SYNOPSIS
  One-time creation of the ECR repositories used by this project (Windows/PowerShell).

.DESCRIPTION
  PowerShell equivalent of create-ecr-repos.sh.

.EXAMPLE
  ./scripts/create-ecr-repos.ps1
  $env:AWS_REGION="us-east-1"; ./scripts/create-ecr-repos.ps1
#>
$ErrorActionPreference = "Continue"

$AwsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { "ap-south-1" }

foreach ($repo in @("mern-frontend", "mern-hello-service", "mern-profile-service")) {
    Write-Host "==> Creating ECR repository: $repo"
    aws ecr create-repository `
        --repository-name $repo `
        --image-scanning-configuration scanOnPush=true `
        --image-tag-mutability MUTABLE `
        --region $AwsRegion
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    (repository '$repo' already exists, skipping)"
    }
}

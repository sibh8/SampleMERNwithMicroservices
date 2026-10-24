<#
.SYNOPSIS
  Build the three MERN images and push them to Amazon ECR (Windows/PowerShell).

.DESCRIPTION
  Creates the ECR repositories if they don't exist, authenticates Docker,
  then builds, tags and pushes frontend, helloService and profileService.

.EXAMPLE
  $env:AWS_REGION="ap-south-1"; $env:IMAGE_TAG="v1"; ./scripts/ecr-build-push.ps1
#>

$ErrorActionPreference = "Stop"

# ----- Configuration (override via environment variables) -----
$AwsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { "ap-south-1" }
$ImageTag  = if ($env:IMAGE_TAG)  { $env:IMAGE_TAG }  else { "latest" }

$AwsAccountId = if ($env:AWS_ACCOUNT_ID) {
    $env:AWS_ACCOUNT_ID
} else {
    (aws sts get-caller-identity --query Account --output text)
}
$EcrRegistry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"

# repo name -> build context
$Repos = @(
    @{ Name = "mern-frontend";        Context = "./frontend" },
    @{ Name = "mern-hello-service";   Context = "./backend/helloService" },
    @{ Name = "mern-profile-service"; Context = "./backend/profileService" }
)

# Move to repo root (this script lives in ./scripts)
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "==> Account: $AwsAccountId  Region: $AwsRegion  Tag: $ImageTag"

# ----- Authenticate Docker to ECR -----
Write-Host "==> Logging in to ECR registry $EcrRegistry"
aws ecr get-login-password --region $AwsRegion |
    docker login --username AWS --password-stdin $EcrRegistry

# ----- Build, create repo, tag and push each image -----
foreach ($r in $Repos) {
    $repo    = $r.Name
    $context = $r.Context
    $image   = "$EcrRegistry/$repo"

    Write-Host "==> Ensuring ECR repository '$repo' exists"
    aws ecr describe-repositories --repository-names $repo --region $AwsRegion *> $null
    if ($LASTEXITCODE -ne 0) {
        aws ecr create-repository `
            --repository-name $repo `
            --image-scanning-configuration scanOnPush=true `
            --region $AwsRegion | Out-Null
    }

    Write-Host "==> Building $repo from $context"
    docker build -t "${repo}:${ImageTag}" $context

    Write-Host "==> Tagging and pushing ${image}:${ImageTag}"
    docker tag "${repo}:${ImageTag}" "${image}:${ImageTag}"
    docker tag "${repo}:${ImageTag}" "${image}:latest"
    docker push "${image}:${ImageTag}"
    docker push "${image}:latest"
}

Write-Host "==> Done. Pushed images:"
foreach ($r in $Repos) {
    Write-Host "    $EcrRegistry/$($r.Name):$ImageTag"
}

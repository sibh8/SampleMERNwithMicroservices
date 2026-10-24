<#
.SYNOPSIS
  Install and configure AWS CLI v2 on Windows (PowerShell equivalent of
  configure-aws-cli.sh - Step 3 of the project).

.DESCRIPTION
  Installs the AWS CLI v2 MSI if the 'aws' command is missing, then runs
  'aws configure' and verifies the credentials.

.EXAMPLE
  ./scripts/configure-aws-cli.ps1
#>
$ErrorActionPreference = "Stop"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "==> Installing AWS CLI v2 (MSI)"
    $msi = Join-Path $env:TEMP "AWSCLIV2.msi"
    Invoke-WebRequest -UseBasicParsing `
        -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" `
        -OutFile $msi
    Start-Process msiexec.exe -ArgumentList "/i", "`"$msi`"", "/qn" -Wait
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    Write-Host "    AWS CLI installed. You may need to open a new terminal so PATH refreshes."
}

Write-Host "==> AWS CLI version:"
aws --version

# Interactive configuration (prompts for Access Key, Secret, region, output).
# Skip this on EC2 if you attached an IAM role to the instance.
Write-Host "==> Running 'aws configure' (press enter to skip fields if using an IAM role)"
aws configure

Write-Host "==> Verifying credentials:"
aws sts get-caller-identity

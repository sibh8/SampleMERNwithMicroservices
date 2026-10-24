<#
.SYNOPSIS
  Helper for running the Jenkins EC2 provisioning from a Windows machine.

.DESCRIPTION
  install-jenkins-ec2.sh provisions Jenkins + tooling on an Amazon Linux /
  Ubuntu EC2 instance. It uses Linux package managers (dnf/apt) and systemctl,
  so it MUST run ON the EC2 instance itself - it cannot be reimplemented to run
  on your local Windows machine.

  This PowerShell helper does one of two things:
    - With -SshTarget and -KeyFile: copies install-jenkins-ec2.sh to the
      instance over SCP and runs it there via SSH.
    - Without parameters: prints the manual steps.

  Note: this is a launcher/wrapper, NOT a Windows port of the installation.

.PARAMETER SshTarget
  user@host of the EC2 instance, e.g. ec2-user@203.0.113.10

.PARAMETER KeyFile
  Path to the .pem private key for SSH.

.EXAMPLE
  ./scripts/install-jenkins-ec2.ps1
  ./scripts/install-jenkins-ec2.ps1 -SshTarget ec2-user@203.0.113.10 -KeyFile C:\keys\jenkins.pem
#>
param(
    [string]$SshTarget,
    [string]$KeyFile
)
$ErrorActionPreference = "Stop"

$shScript = Join-Path $PSScriptRoot "install-jenkins-ec2.sh"

if (-not $SshTarget -or -not $KeyFile) {
    Write-Host @"
This script provisions Jenkins on a LINUX EC2 instance and must run there.

Option A - paste at launch:
  Copy the contents of install-jenkins-ec2.sh into the EC2 'User data' field
  when launching the instance. It runs automatically on first boot.

Option B - run after SSHing in:
  scp -i <key.pem> scripts/install-jenkins-ec2.sh <user>@<host>:~
  ssh -i <key.pem> <user>@<host> 'bash ~/install-jenkins-ec2.sh'

Option C - let this helper do Option B for you:
  ./scripts/install-jenkins-ec2.ps1 -SshTarget <user>@<host> -KeyFile <key.pem>

After install, get the initial admin password on the instance with:
  sudo cat /var/lib/jenkins/secrets/initialAdminPassword
Then open http://<EC2_PUBLIC_IP>:8080
"@
    return
}

if (-not (Test-Path $shScript)) {
    throw "Cannot find $shScript"
}
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw "OpenSSH client not found. Install it via: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
}

Write-Host "==> Copying install-jenkins-ec2.sh to $SshTarget"
scp -i $KeyFile $shScript "${SshTarget}:~/install-jenkins-ec2.sh"

Write-Host "==> Running the installer on the instance (this takes a few minutes)"
ssh -i $KeyFile $SshTarget "bash ~/install-jenkins-ec2.sh"

Write-Host "==> Done. Retrieve the initial admin password with:"
Write-Host "    ssh -i $KeyFile $SshTarget 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"

<#
.SYNOPSIS
  Remove the local MERN stack created with Podman (containers, network, volume).

.DESCRIPTION
  Mirrors Task 9 of docs/PODMAN_RUNBOOK.md. Safe to run repeatedly; missing
  resources are ignored. Use -RemoveImages to also delete the built images,
  and -KeepData to preserve the MongoDB volume.

.EXAMPLE
  ./scripts/teardown-podman.ps1
  ./scripts/teardown-podman.ps1 -RemoveImages
  ./scripts/teardown-podman.ps1 -KeepData
#>
param(
  [switch]$RemoveImages,
  [switch]$KeepData
)

$ErrorActionPreference = "Continue"

# Use podman if present, otherwise fall back to docker.
$engine = if (Get-Command podman -ErrorAction SilentlyContinue) { "podman" }
          elseif (Get-Command docker -ErrorAction SilentlyContinue) { "docker" }
          else { throw "Neither podman nor docker found on PATH." }
Write-Host "==> Using container engine: $engine"

$containers = @("mern-frontend", "mern-profile-service", "mern-hello-service", "mern-mongo")
Write-Host "==> Removing containers"
& $engine rm -f $containers 2>$null

Write-Host "==> Removing network mern-net"
& $engine network rm mern-net 2>$null

if ($KeepData) {
  Write-Host "==> Keeping volume mongo-data (per -KeepData)"
} else {
  Write-Host "==> Removing volume mongo-data"
  & $engine volume rm mongo-data 2>$null
}

if ($RemoveImages) {
  Write-Host "==> Removing images"
  & $engine rmi mern-frontend:local mern-hello-service:local mern-profile-service:local 2>$null
  & $engine rmi docker.io/library/mongo:7 2>$null
}

Write-Host "==> Local teardown complete. Remaining containers:"
& $engine ps -a --filter "name=mern-" 2>$null

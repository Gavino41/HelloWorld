#Requires -Version 5.1
[CmdletBinding()]
param (
    [string]$Image            = "ghcr.io/gavino41/helloworld:latest",
    [string]$ContainerName    = "helloworld",
    [int]$HostPort            = 8080,
    [int]$HealthTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($args -join ' ') failed (exit code $LASTEXITCODE)"
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI not found. Install Docker first."
}
Invoke-Docker info | Out-Null

Invoke-Docker pull $Image

$existing = docker ps -a --filter "name=^/${ContainerName}$" --format "{{.ID}}"
if ($existing) {
    Write-Output "Removing existing container '$ContainerName'..."
    Invoke-Docker rm -f $ContainerName | Out-Null
}
Invoke-Docker run -d `
    --name $ContainerName `
    --restart unless-stopped `
    -p "${HostPort}:8080" `
    $Image | Out-Null

$url      = "http://localhost:$HostPort/"
$deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
$healthy  = $false

while ((Get-Date) -lt $deadline) {
    try {
        $response = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) { $healthy = $true; break }
    }
    catch { } 
    Start-Sleep -Seconds 2
}

if (-not $healthy) {
    docker logs --tail 20 $ContainerName
    throw "Container did not return HTTP 200 at $url within $HealthTimeoutSeconds seconds."
}

Write-Output "Deployed: $url returned HTTP 200 (container '$ContainerName', image '$Image')."
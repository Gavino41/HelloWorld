#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [ValidateNotNullOrEmpty()][string]$SiteName    = "HelloWorldSite",
    [ValidateNotNullOrEmpty()][string]$AppPoolName = "HelloWorldAppPool",
    [ValidateNotNullOrEmpty()][string]$AppName     = "HelloWorldApp",
    [ValidateNotNullOrEmpty()][string]$TargetGroup = "AppDeploymentGroup",
    [string]$SitePath = "C:\inetpub\HelloWorldSite",
    [string]$AppPath  = "C:\inetpub\HelloWorldSite\HelloWorldApp",
    [string]$LogPath  = "C:\IISLogs\HelloWorld",
    [string]$SourcePath,
    [Parameter(Mandatory)][pscredential]$ServiceCredential
)

$ErrorActionPreference = 'Stop'

if ((Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue) -and -not (Get-WindowsFeature Web-Server).Installed) {
    Install-WindowsFeature Web-Server -IncludeManagementTools | Out-Null
}

Import-Module WebAdministration

if (-not (Get-WebGlobalModule -Name AspNetCoreModuleV2 -ErrorAction SilentlyContinue)) {
    throw "ASP.NET Core Module not found. Install the .NET 10 Hosting Bundle, then run iisreset."
}

try {
    $user = $ServiceCredential.UserName

    foreach ($p in $SitePath, $AppPath, $LogPath) {
        if (-not (Test-Path $p)) { New-Item $p -ItemType Directory | Out-Null }
    }

    $pool = "IIS:\AppPools\$AppPoolName"
    if (Test-Path $pool) {
        Stop-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue
    }

    if ($SourcePath) { Copy-Item "$SourcePath\*" $AppPath -Recurse -Force }

    if (-not (Get-LocalUser $user -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $user -Password $ServiceCredential.Password -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    }

    if (-not (Get-LocalGroup $TargetGroup -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $TargetGroup | Out-Null
    }

    foreach ($g in $TargetGroup, 'IIS_IUSRS') {
        if (-not (Get-LocalGroupMember $g -Member $user -ErrorAction SilentlyContinue)) {
            Add-LocalGroupMember -Group $g -Member $user
        }
    }

    icacls $SitePath /grant "${TargetGroup}:(OI)(CI)RX" | Out-Null
    icacls $LogPath  /grant "${TargetGroup}:(OI)(CI)M"  | Out-Null

    if (-not (Test-Path $pool)) { New-WebAppPool -Name $AppPoolName | Out-Null }

    Set-ItemProperty $pool -Name processModel -Value @{
        identityType = 'SpecificUser'
        userName     = $user
        password     = $ServiceCredential.GetNetworkCredential().Password
    }
    Set-ItemProperty $pool -Name managedRuntimeVersion -Value ''

    $site = "IIS:\Sites\$SiteName"
    if (-not (Test-Path $site)) {
        New-Website -Name $SiteName -PhysicalPath $SitePath -ApplicationPool $AppPoolName -Port 80 -HostHeader "localhost" | Out-Null
    }

    if (-not (Get-WebBinding -Name $SiteName -Protocol https)) {
        $cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation Cert:\LocalMachine\My
        New-WebBinding -Name $SiteName -Protocol https -Port 443 -HostHeader "localhost" -SslFlags 1
        (Get-WebBinding -Name $SiteName -Protocol https).AddSslCertificate($cert.Thumbprint, "My")
    }

    Set-ItemProperty $site -Name logFile.directory -Value $LogPath

    if (-not (Get-WebApplication -Site $SiteName -Name $AppName)) {
        New-WebApplication -Name $AppName -Site $SiteName -PhysicalPath $AppPath -ApplicationPool $AppPoolName | Out-Null
    }

    Start-WebAppPool -Name $AppPoolName -ErrorAction SilentlyContinue

    $url = "http://localhost/$AppName/"
    $resp = Invoke-WebRequest $url -UseBasicParsing
    Write-Output "Deployed. $url returned HTTP $($resp.StatusCode)."
}
catch {
    Write-Error "Deployment failed: $_"
    exit 1
}
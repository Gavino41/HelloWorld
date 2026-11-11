#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [string]$ServiceName = "HelloWorldStatusMonitor",
    [Parameter(Mandatory)][string]$ExePath,
    [Parameter(Mandatory)][pscredential]$ServiceCredential
)

$ErrorActionPreference = 'Stop'


function Grant-LogonAsService {
    param ([string]$Account)
    $sid = ([System.Security.Principal.NTAccount]$Account).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $inf = Join-Path $env:TEMP "rights.inf"
    $db  = Join-Path $env:TEMP "rights.sdb"
    secedit /export /cfg $inf /areas USER_RIGHTS | Out-Null
    $lines = Get-Content $inf
    $current = $lines | Where-Object { $_ -like 'SeServiceLogonRight*' }
    if ($current -notmatch [regex]::Escape($sid)) {
        $lines = $lines -replace [regex]::Escape($current), "$current,*$sid"
        $lines | Set-Content $inf -Encoding Unicode
        secedit /configure /db $db /cfg $inf /areas USER_RIGHTS | Out-Null
    }
    Remove-Item $inf, $db -ErrorAction SilentlyContinue
}

if (-not (Test-Path $ExePath)) { throw "Executable not found: $ExePath" }

$account = if ($ServiceCredential.UserName -like '*\*') { $ServiceCredential.UserName }
           else { ".\$($ServiceCredential.UserName)" }

Grant-LogonAsService -Account $account
icacls (Split-Path $ExePath) /grant "${account}:(OI)(CI)M" | Out-Null

$existing = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
if (-not $existing) {
    New-Service -Name $ServiceName `
        -BinaryPathName "`"$ExePath`"" `
        -DisplayName "HelloWorld Status Monitor" `
        -Description "Checks the HelloWorld site every 60 seconds" `
        -StartupType Automatic `
        -Credential $ServiceCredential | Out-Null
}
else {
    Invoke-CimMethod -InputObject $existing -MethodName Change -Arguments @{
        PathName      = "`"$ExePath`""
        StartName     = $account
        StartPassword = $ServiceCredential.GetNetworkCredential().Password
        StartMode     = 'Automatic'
    } | Out-Null
}

sc.exe failure $ServiceName reset= 86400 actions= restart/300000/restart/300000/restart/300000 | Out-Null
sc.exe failureflag $ServiceName 1 | Out-Null

if ((Get-Service $ServiceName).Status -ne 'Running') { Start-Service $ServiceName }
Get-Service $ServiceName | Format-Table Name, Status, StartType
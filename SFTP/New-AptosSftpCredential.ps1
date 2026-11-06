<#
.SYNOPSIS
    One-time setup: saves the Aptos SFTP user/password to a DPAPI-encrypted file
    and restricts the folder to the current user (+ Administrators).

.NOTES
    RUN THIS LOGGED ON AS THE ACCOUNT THAT RUNS THE SQL AGENT STEP (or its proxy),
    on the same server that runs Export-AptosStyleDims.ps1. DPAPI files can only
    be decrypted by the same user on the same machine.
    Example: runas /user:DOMAIN\sqlagent_svc "powershell.exe -NoProfile -File New-AptosSftpCredential.ps1"
#>
param(
    [string]$CredFile = 'D:\Jobs\AptosStyleDims\Secrets\aptos_sftp.cred'
)
$ErrorActionPreference = 'Stop'

$dir = Split-Path -Parent $CredFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# Lock the folder: remove inherited rights, grant only current user + Administrators
$me = "$env:USERDOMAIN\$env:USERNAME"
& icacls.exe $dir /inheritance:r /grant:r "${me}:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" | Out-Null

$cred = Get-Credential -Message 'Aptos SFTP username and password'
$cred | Export-Clixml -LiteralPath $CredFile

Write-Host "Saved: $CredFile (readable only by $me on $env:COMPUTERNAME)"

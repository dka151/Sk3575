<#
.SYNOPSIS
    Creates the two DPAPI-encrypted credential files used by Sync-BlueYonder-Aptos.ps1:
      - Blue Yonder (64.26.254.72)
      - Aptos       (10.252.16.100)

.DESCRIPTION
    Saves each credential as an Export-Clixml file.

    CRITICAL: Each file can ONLY be decrypted by the SAME Windows account on the
    SAME machine that created it. Because the transfer runs as a scheduled task
    under a service account on vwpsftp01, you MUST run this script AS THAT SERVICE
    ACCOUNT ON vwpsftp01. Running it under your own login produces files the
    service account cannot read, and the scheduled job will fail to authenticate.

    Run as the service account via, e.g.:
        runas /user:DOMAIN\svc-account powershell.exe
        psexec -u DOMAIN\svc-account powershell.exe

.PARAMETER OutputFolder
    Folder for the credential files (default D:\sftp\creds). Lock it down so only
    the service account and admins can read it.

.EXAMPLE
    .\New-BlueYonderAptosCreds.ps1 -OutputFolder 'D:\sftp\creds'
#>

[CmdletBinding()]
param(
    [string]$OutputFolder = 'D:\sftp\creds'
)

$ErrorActionPreference = 'Stop'

Write-Host "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor Cyan
Write-Host "Machine   : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "These files will ONLY be readable by THIS account on THIS machine.`n" -ForegroundColor Yellow

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Host "Created folder: $OutputFolder"
}

$byePath   = Join-Path $OutputFolder 'blueyonder.cred.xml'
$aptosPath = Join-Path $OutputFolder 'aptos.cred.xml'

Write-Host "`n--- Blue Yonder (PRODB2BGW02.jdadelivers.com) ---" -ForegroundColor Cyan
Write-Host "Username should be: eurorpatprdv2"
$byeCred = Get-Credential -UserName 'eurorpatprdv2' -Message 'Blue Yonder SFTP password for eurorpatprdv2'
$byeCred | Export-Clixml -Path $byePath
Write-Host "Saved -> $byePath" -ForegroundColor Green

Write-Host "`n--- Aptos (10.252.16.100) ---" -ForegroundColor Cyan
$aptosCred = Get-Credential -UserName 'WSsftpuser' -Message 'Aptos SFTP password for WSsftpuser'
$aptosCred | Export-Clixml -Path $aptosPath
Write-Host "Saved -> $aptosPath" -ForegroundColor Green

Write-Host "`nDone. Both credential files are ready in $OutputFolder." -ForegroundColor Cyan
Write-Host "Reference folder in the scheduled task: -CredentialFolder '$OutputFolder'"

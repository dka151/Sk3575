<#
.SYNOPSIS
    One-time migration: moves existing WinSCP session logs from D:\sftp\logs
    into the new D:\sftp\logs\winscp_log subfolder.

    Sync-BlueYonder-Aptos.ps1 now writes WinSCP session logs to winscp_log.
    This script relocates logs left in the old location by earlier runs. The
    main script log (blueyonder-aptos_*.log) stays in D:\sftp\logs and is NOT
    moved.

.PARAMETER LogRoot
    Folder that currently holds the WinSCP logs. Default D:\sftp\logs.

.PARAMETER WhatIf
    Preview what would move without moving anything:
        .\Move-WinScpLogs.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$LogRoot = 'D:\sftp\logs'
)

$ErrorActionPreference = 'Stop'

$dest = Join-Path $LogRoot 'winscp_log'

if (-not (Test-Path -LiteralPath $LogRoot)) {
    throw "Log root not found: $LogRoot"
}

# Ensure the destination exists.
if (-not (Test-Path -LiteralPath $dest)) {
    if ($PSCmdlet.ShouldProcess($dest, 'Create folder')) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Write-Host "Created $dest"
    }
}

# WinSCP session logs only (e.g. winscp-session.BlueYonder_20261024-020003.log).
# -File + top-level only, so we never recurse into winscp_log itself.
$files = Get-ChildItem -LiteralPath $LogRoot -Filter 'winscp-session.*' -File -ErrorAction SilentlyContinue

if (-not $files) {
    Write-Host "No WinSCP session logs to move in $LogRoot."
    return
}

$moved = 0
$skipped = 0
foreach ($f in $files) {
    $target = Join-Path $dest $f.Name

    # Don't overwrite an existing file in the destination.
    if (Test-Path -LiteralPath $target) {
        Write-Warning "Skipping (already exists at destination): $($f.Name)"
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($f.FullName, "Move to $dest")) {
        Move-Item -LiteralPath $f.FullName -Destination $target
        Write-Host "Moved $($f.Name)"
        $moved++
    }
}

Write-Host ("Done. Moved {0} file(s), skipped {1}." -f $moved, $skipped)

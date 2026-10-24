<#
.SYNOPSIS
    Registers the Windows Scheduled Task that runs Sync-BlueYonder-Aptos.ps1 on
    vwpsftp01 under a service account, whether or not the user is logged on.

.DESCRIPTION
    Creates a daily (and optionally repeating) scheduled task. The task runs
    PowerShell non-interactively, executing the transfer script with the
    production flags (both flows, -DeleteSourceAfter => legacy .TMP/.RN MOVE).

    Run this ON vwpsftp01, as an administrator. You will be prompted for the
    service account password (used by Task Scheduler to launch the task).

.PARAMETER TaskName
    Name for the scheduled task.

.PARAMETER ServiceAccount
    The service account the task runs as, e.g. 'DOMAIN\svc-sftp'.

.PARAMETER ScriptPath
    Full path to Sync-BlueYonder-Aptos.ps1 on vwpsftp01.

.PARAMETER StartTime
    First daily run time (e.g. '02:00').

.PARAMETER RepeatMinutes
    If greater than 0, repeat the task every N minutes across the day
    (e.g. 30 for every half hour). 0 = run once daily at StartTime.

.EXAMPLE
    .\Register-BlueYonderAptosTask.ps1 -ServiceAccount 'DOMAIN\svc-sftp' `
        -ScriptPath 'D:\sftp\Sync-BlueYonder-Aptos.ps1' -StartTime '02:00' -RepeatMinutes 30
#>

[CmdletBinding()]
param(
    [string]$TaskName       = 'BlueYonder-Aptos SFTP Transfer',
    [Parameter(Mandatory)] [string]$ServiceAccount,
    [string]$ScriptPath     = 'D:\sftp\Sync-BlueYonder-Aptos.ps1',
    [string]$StartTime      = '02:00',
    [int]$RepeatMinutes     = 0
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath. Copy it to vwpsftp01 first."
}

# Production arguments: run both flows as a MOVE (legacy .TMP/.RN pattern).
# -DeleteSourceAfter deletes the claimed source (.RN) after a verified delivery.
# Remove it to run in test/safety mode (claimed source left in place).
$scriptArgs = @(
    '-NoProfile'
    '-NonInteractive'
    '-ExecutionPolicy', 'Bypass'
    '-File', "`"$ScriptPath`""
    '-Mode', 'Both'
    '-DeleteSourceAfter'
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $scriptArgs -WorkingDirectory (Split-Path $ScriptPath)

# Trigger: daily at StartTime, optionally repeating through the day.
$trigger = New-ScheduledTaskTrigger -Daily -At $StartTime
if ($RepeatMinutes -gt 0) {
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At $StartTime `
        -RepetitionInterval (New-TimeSpan -Minutes $RepeatMinutes) `
        -RepetitionDuration (New-TimeSpan -Hours 24)).Repetition
}

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -MultipleInstances IgnoreNew

# Prompt for the service account password Task Scheduler will store to launch the task.
$cred = Get-Credential -UserName $ServiceAccount -Message "Windows password for the task's run-as account ($ServiceAccount)"

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -User      $cred.UserName `
    -Password  $cred.GetNetworkCredential().Password `
    -RunLevel  Highest `
    -Description 'Transfers invoices Blue Yonder->Aptos and purchase orders Aptos->Blue Yonder via vwpsftp01 (WinSCP). Replaces legacy DataExchange/JDA job.' `
    -Force

Write-Host "`nScheduled task '$TaskName' registered to run as $($cred.UserName)." -ForegroundColor Green
Write-Host "It runs whether the user is logged on or not." -ForegroundColor Green
Write-Host "`nVerify / inspect with:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Host "Run it on demand with:" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"

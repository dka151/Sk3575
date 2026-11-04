<#
.SYNOPSIS
    Replaces the legacy DataExchange/JDA SFTP job. Moves files between Blue Yonder
    and Aptos SFTP servers, brokered through vwpsftp01 using the WinSCP .NET assembly.

        Blue Yonder SFTP  <-->  vwpsftp01 (staging)  <-->  Aptos SFTP

    Flows per run (mirroring the original job):
      INVOICES -> APTOS : Blue Yonder /home/eurorpatprdv2/outbox (STSIMATIN*.go)
                          -> Aptos /IN/Merch/Invoices/Company1
      ASN      -> APTOS : Blue Yonder /home/eurorpatprdv2/outbox (STSIMASN*.go)
                          -> Aptos '/IN/Merch/EDI ASN'
      POS      -> BY    : Aptos /Out/Merch/PurchaseOrder
                          -> Blue Yonder /home/eurorpatprdv2/inbox

    Outbound (Blue Yonder -> Aptos) routing is table-driven via $OutboundRoutes:
    add a row to route another filename pattern from the same outbox to its own
    Aptos destination.

.DESCRIPTION
    SFTP cannot stream directly between two remote servers, so vwpsftp01 is the
    broker. Each file follows the legacy DataExchange/JDA transfer pattern:
      PICKUP (source):  download to a local .TMP, rename the remote source to .RN
                        (claim it), rename the local .TMP to its final name, then
                        delete the remote .RN.
      DELIVERY (dest):  upload to a remote .TMP, then rename the remote .TMP to the
                        final name so the receiving app never sees a partial file.
    The final delete of the claimed source (.RN) is gated behind -DeleteSourceAfter
    as a safety measure. With the switch it is a true MOVE (source consumed);
    without it, delivery still completes but the claimed .RN is left on the source.
    The local staging copy is always cleaned up.

    Authentication is username + password for both servers, read from
    DPAPI-encrypted credential files (Export-Clixml) so the script runs unattended
    as a scheduled task under a service account. Create those files with
    New-BlueYonderAptosCreds.ps1 WHILE RUNNING AS THE SERVICE ACCOUNT ON vwpsftp01
    (DPAPI ties each file to the creating user + machine).

    SSH host keys are pinned via fingerprints. Capture them once with the WinSCP
    .NET assembly, e.g.:
        Add-Type -Path 'C:\Program Files (x86)\WinSCP\WinSCPnet.dll'
        $o = New-Object WinSCP.SessionOptions -Property @{ Protocol=[WinSCP.Protocol]::Sftp; HostName='<host>'; PortNumber=22 }
        (New-Object WinSCP.Session).ScanFingerprint($o, 'SHA-256')

.PARAMETER Mode
    Which flow(s) to run: Both (default), InvoicesOnly, or PosOnly.

.PARAMETER DeleteSourceAfter
    Safety switch. When supplied, the claimed source (.RN) is deleted after a
    verified delivery (a true MOVE). When omitted (default), delivery completes
    but the claimed source .RN is left in place -- nothing is deleted.
    Keeping the .RN is recommended: it is the "already picked up" marker that
    prevents the same file being pushed to the destination twice.

.PARAMETER SqlServer
.PARAMETER SqlDatabase
    SQL Server audit database. Every file gets a row in
    dbo.BlueYonderAptos_TransferAudit and one row per step in
    dbo.BlueYonderAptos_TransferAuditStepDetail. The audit is mandatory: if SQL
    is unreachable, or any audit write fails, the run HALTS (no file fallback).
    File outcomes: Success | Warning (delivered, .RN delete failed) |
    Failed (before claim; source untouched, retried next run) |
    Stranded (claimed, not delivered; .RN KEPT, manual review needed).
    The script exits 1 if any file is Failed or Stranded.

.PARAMETER WhatIf
    Dry run: logs what each flow WOULD transfer without moving anything.

.EXAMPLE
    .\Sync-BlueYonder-Aptos.ps1 -WhatIf                  # safe first run, nothing moves
    .\Sync-BlueYonder-Aptos.ps1                          # both flows, deliver; leave claimed source (.RN)
    .\Sync-BlueYonder-Aptos.ps1 -DeleteSourceAfter       # both flows, MOVE (delete source after verified delivery)

.NOTES
    Requires WinSCP installed on vwpsftp01 (WinSCPnet.dll). Adjust $WinScpDllPath
    if WinSCP is not at the default location.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Both', 'InvoicesOnly', 'PosOnly')]
    [string]$Mode = 'Both',

    [string]$CredentialFolder = 'D:\sftp\creds',
    [string]$StagingPath      = 'D:\sftp\staging',
    [string]$LogPath          = 'D:\sftp\logs\blueyonder-aptos.log',
    [string]$WinScpLogPath    = 'D:\sftp\logs\winscp_log\winscp-session.log',

    # SQL Server audit database (Windows auth as the service account).
    # The audit is a HARD dependency: if SQL is unreachable the run aborts
    # before any file is transferred. There is NO file fallback.
    # Tables: dbo.BlueYonderAptos_TransferAudit and
    #         dbo.BlueYonderAptos_TransferAuditStepDetail
    #         (create with Create_BlueYonderAptos_TransferAudit.sql).
    # Defaults to the machine running this script (SQL Agent and the audit DB are
    # on the same server). For a named instance pass e.g. -SqlServer "$env:COMPUTERNAME\INST01".
    [string]$SqlServer   = $env:COMPUTERNAME,
    [string]$SqlDatabase = 'DBA',

    # Safety switch. When supplied, the claimed source file (renamed to .RN during
    # pickup) is DELETED after a verified delivery -- a true MOVE, matching the
    # legacy job. When omitted (default), delivery still completes but the claimed
    # source .RN file is LEFT in place on the source server, so nothing is deleted.
    [switch]$DeleteSourceAfter
)

$ErrorActionPreference = 'Stop'

# ===========================================================================
# PER-RUN TIMESTAMPED LOG FILES  --  every run writes to its OWN log files, so
# nothing is ever overwritten or appended. The $LogPath / $WinScpLogPath params
# above are treated as BASE names; a run timestamp (yyyyMMdd-HHmmss) is inserted
# before the extension, e.g.:
#   D:\sftp\logs\blueyonder-aptos.log
#     -> D:\sftp\logs\blueyonder-aptos_20261024-020003.log
#   D:\sftp\logs\winscp_log\winscp-session.log
#     -> D:\sftp\logs\winscp_log\winscp-session.BlueYonder_20261024-020003.log
# ===========================================================================
$script:RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Add-RunStamp {
    # Inserts the run timestamp before the file extension of a base path.
    param([string]$BasePath)
    $dir  = Split-Path -Parent $BasePath
    $base = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
    $ext  = [System.IO.Path]::GetExtension($BasePath)
    return (Join-Path $dir ("{0}_{1}{2}" -f $base, $script:RunStamp, $ext))
}

# Resolve the script log to a timestamped file for this run.
$LogPath = Add-RunStamp -BasePath $LogPath

# ===========================================================================
# CONFIGURATION  --  values from the legacy DataExchange/JDA job
# ===========================================================================

# WinSCP .NET assembly location on vwpsftp01:
$WinScpDllPath = 'C:\Program Files (x86)\WinSCP\WinSCPnet.dll'   # TODO: confirm path

# --- Blue Yonder (JDA) SFTP endpoint ---
# Host PRODB2BGW02.jdadelivers.com (formerly reached by IP 64.26.254.72).
# NOTE: username/password are NOT stored here. They live in the DPAPI-encrypted
# credential file (blueyonder.cred.xml) created by New-BlueYonderAptosCreds.ps1.
$BlueYonder = @{
    HostName       = 'PRODB2BGW02.jdadelivers.com'
    PortNumber     = 22
    CredFile       = Join-Path $CredentialFolder 'blueyonder.cred.xml'
    SshHostKey     = 'ssh-rsa 2048 7UaHQyXXDmku5LJPXpSWKT0uDBI7SkvTde1GPW3CdTU='   # scan with WinSCP ScanFingerprint (see header) for PRODB2BGW02.jdadelivers.com
    OutboxPath     = '/home/eurorpatprdv2/outbox'   # invoices come FROM here (absolute, uses login-user home)
    InboxPath      = '/home/eurorpatprdv2/inbox'    # POs go TO here (absolute, uses login-user home)
}

# --- Aptos SFTP endpoint ---
$Aptos = @{
    HostName        = '10.252.16.100'
    PortNumber      = 22
    CredFile        = Join-Path $CredentialFolder 'aptos.cred.xml'
    SshHostKey      = 'ssh-rsa 2048 XUxWwtGxrm0TQQThOq1HeVHxlZIsVKNzQgjNZQtc/es='       # scan with WinSCP ScanFingerprint (see header) for 10.252.16.100
    InvoicesInPath  = '/IN/Merch/Invoices/Company1'      # invoices (STSIMATIN*.go) go TO here
    AsnInPath       = '/IN/Merch/EDI ASN'               # ASNs (STSIMASN*.go) go TO here (note the space)
    PurchaseOutPath = '/Out/Merch/PurchaseOrder'         # POs come FROM here
}

# Blue Yonder outbox -> Aptos routing. Each entry maps a filename pattern in the
# Blue Yonder outbox to its Aptos destination folder. Add more rows here to route
# additional document types from the same outbox.
$OutboundRoutes = @(
    @{ Label = 'INVOICES'; Tag = 'ATIN'; Pattern = 'STSIMATIN*.go'; DestPath = $Aptos.InvoicesInPath }
    @{ Label = 'ASN';      Tag = 'ASN';  Pattern = 'STSIMASN*.go';  DestPath = $Aptos.AsnInPath }
)

# Aptos -> Blue Yonder purchase orders.
$PoPattern = 'ExportPO-Co1*.xml'   # purchase orders from Aptos

# ===========================================================================
# IMPLEMENTATION  --  no edits needed below
# ===========================================================================

# Current flow tag (e.g. INVOICES / ASN / EXPORTPO) used in the log prefix, and
# the OS process id, to mirror the legacy FD/FILEMOVER log format:
#   HH:mm:ss:fff  <TAG>  (<pid>) : <message>
$script:FlowTag = 'STARTUP'
$script:ProcId  = $PID

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'HH:mm:ss:fff'
    $tag  = $script:FlowTag.PadRight(10)
    $line = "{0} {1} ({2}) : {3}" -f $ts, $tag, $script:ProcId, $Message
    if ($Level -eq 'ERROR') { $line = "{0} {1} ({2}) : ERROR: {3}" -f $ts, $tag, $script:ProcId, $Message }
    Write-Host $line
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch { }
}

# ---------------------------------------------------------------------------
# SQL audit helpers. Any failure here sets $script:AuditFatal and THROWS; the
# per-file catch re-throws it so the whole run halts. By design no file may be
# moved without its audit trail.
# ---------------------------------------------------------------------------
$script:RunId          = [guid]::NewGuid()
$script:AuditConn      = $null
$script:AuditFatal     = $false
$script:FailedCount    = 0    # files that failed BEFORE the source was claimed
$script:StrandedCount  = 0    # files claimed (.RN kept) but not delivered

function Stop-OnAuditError {
    param([string]$Message)
    $script:AuditFatal = $true
    throw "AUDIT: $Message"
}

function Open-AuditConnection {
    if ($SqlServer -like 'TODO*' -or $SqlDatabase -like 'TODO*') {
        throw "SqlServer/SqlDatabase are not configured. Set -SqlServer and -SqlDatabase. Transfers are halted without an audit database."
    }
    $cs = "Server=$SqlServer;Database=$SqlDatabase;Integrated Security=SSPI;Connect Timeout=15;Application Name=Sync-BlueYonder-Aptos"
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    try {
        $conn.Open()
        foreach ($t in 'dbo.BlueYonderAptos_TransferAudit', 'dbo.BlueYonderAptos_TransferAuditStepDetail') {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT TOP (0) 1 FROM $t"
            [void]$cmd.ExecuteScalar()
        }
    }
    catch {
        $conn.Dispose()
        throw "Audit database unavailable ($SqlServer/$SqlDatabase). Transfers halted. Error: $($_.Exception.Message)"
    }
    $script:AuditConn = $conn
    Write-Log "Audit database connected: $SqlServer/$SqlDatabase (RunId $($script:RunId))"
}

function Start-AuditRecord {
    param(
        [string]$Direction, [string]$FlowName, [string]$FileName, $SizeBytes,
        [string]$SourceHost, [string]$SourcePath, [string]$DestHost, [string]$DestPath
    )
    $cmd = $script:AuditConn.CreateCommand()
    $cmd.CommandTimeout = 30
    $cmd.CommandText = @'
INSERT INTO dbo.BlueYonderAptos_TransferAudit
    (RunId, Direction, FlowName, FileName, SizeBytes, SourceHost, SourcePath, DestHost, DestPath,
     Status, TransferStartUtc, RunHost, RunUser)
OUTPUT INSERTED.AuditId
VALUES
    (@RunId, @Direction, @FlowName, @FileName, @SizeBytes, @SourceHost, @SourcePath, @DestHost, @DestPath,
     'InProgress', SYSUTCDATETIME(), @RunHost, @RunUser)
'@
    [void]$cmd.Parameters.AddWithValue('@RunId',      $script:RunId)
    [void]$cmd.Parameters.AddWithValue('@Direction',  $Direction)
    [void]$cmd.Parameters.AddWithValue('@FlowName',   $FlowName)
    [void]$cmd.Parameters.AddWithValue('@FileName',   $FileName)
    [void]$cmd.Parameters.AddWithValue('@SizeBytes',  $(if ($null -ne $SizeBytes) { [int64]$SizeBytes } else { [DBNull]::Value }))
    [void]$cmd.Parameters.AddWithValue('@SourceHost', $SourceHost)
    [void]$cmd.Parameters.AddWithValue('@SourcePath', $SourcePath)
    [void]$cmd.Parameters.AddWithValue('@DestHost',   $DestHost)
    [void]$cmd.Parameters.AddWithValue('@DestPath',   $DestPath)
    [void]$cmd.Parameters.AddWithValue('@RunHost',    $env:COMPUTERNAME)
    [void]$cmd.Parameters.AddWithValue('@RunUser',    "$env:USERDOMAIN\$env:USERNAME")
    try { return [int64]$cmd.ExecuteScalar() }
    catch { Stop-OnAuditError "insert failed for '$FileName'; run halted before transfer. $($_.Exception.Message)" }
}

function Complete-AuditRecord {
    param([int64]$AuditId, [string]$Status, [string]$ErrorMessage, [int]$DurationMs)
    $cmd = $script:AuditConn.CreateCommand()
    $cmd.CommandTimeout = 30
    $cmd.CommandText = @'
UPDATE dbo.BlueYonderAptos_TransferAudit
   SET Status = @Status, ErrorMessage = @ErrorMessage, DurationMs = @DurationMs,
       TransferEndUtc = SYSUTCDATETIME()
 WHERE AuditId = @AuditId
'@
    [void]$cmd.Parameters.AddWithValue('@Status',       $Status)
    [void]$cmd.Parameters.AddWithValue('@ErrorMessage', $(if ($ErrorMessage) { $ErrorMessage } else { [DBNull]::Value }))
    [void]$cmd.Parameters.AddWithValue('@DurationMs',   $DurationMs)
    [void]$cmd.Parameters.AddWithValue('@AuditId',      $AuditId)
    try { [void]$cmd.ExecuteNonQuery() }
    catch { Stop-OnAuditError "update failed for AuditId $AuditId (status '$Status'); run halted. $($_.Exception.Message)" }
}

function Add-StepRecord {
    # Inserts a step row. Status 'InProgress' (updated later by Complete-StepRecord)
    # or a final status such as 'Skipped' (written complete in one shot).
    param(
        [int64]$AuditId, [int]$StepNo, [string]$StepName, [string]$StepHost,
        [string]$FromPath, [string]$ToPath, [string]$Status = 'InProgress'
    )
    $cmd = $script:AuditConn.CreateCommand()
    $cmd.CommandTimeout = 30
    $cmd.CommandText = @'
INSERT INTO dbo.BlueYonderAptos_TransferAuditStepDetail
    (AuditId, StepNo, StepName, Host, FromPath, ToPath, Status, StepStartUtc, StepEndUtc, DurationMs)
OUTPUT INSERTED.StepId
VALUES
    (@AuditId, @StepNo, @StepName, @Host, @FromPath, @ToPath, @Status, SYSUTCDATETIME(),
     CASE WHEN @Status = 'InProgress' THEN NULL ELSE SYSUTCDATETIME() END,
     CASE WHEN @Status = 'InProgress' THEN NULL ELSE 0 END)
'@
    [void]$cmd.Parameters.AddWithValue('@AuditId',  $AuditId)
    [void]$cmd.Parameters.AddWithValue('@StepNo',   [byte]$StepNo)
    [void]$cmd.Parameters.AddWithValue('@StepName', $StepName)
    [void]$cmd.Parameters.AddWithValue('@Host',     $(if ($StepHost) { $StepHost } else { [DBNull]::Value }))
    [void]$cmd.Parameters.AddWithValue('@FromPath', $(if ($FromPath) { $FromPath } else { [DBNull]::Value }))
    [void]$cmd.Parameters.AddWithValue('@ToPath',   $(if ($ToPath)   { $ToPath }   else { [DBNull]::Value }))
    [void]$cmd.Parameters.AddWithValue('@Status',   $Status)
    try { return [int64]$cmd.ExecuteScalar() }
    catch { Stop-OnAuditError "step insert failed (AuditId $AuditId, $StepName); run halted. $($_.Exception.Message)" }
}

function Complete-StepRecord {
    param([int64]$StepId, [string]$Status, [string]$ErrorMessage, [int]$DurationMs)
    $cmd = $script:AuditConn.CreateCommand()
    $cmd.CommandTimeout = 30
    $cmd.CommandText = @'
UPDATE dbo.BlueYonderAptos_TransferAuditStepDetail
   SET Status = @Status, ErrorMessage = @ErrorMessage, DurationMs = @DurationMs,
       StepEndUtc = SYSUTCDATETIME()
 WHERE StepId = @StepId
'@
    [void]$cmd.Parameters.AddWithValue('@Status',       $Status)
    [void]$cmd.Parameters.AddWithValue('@ErrorMessage', $(if ($ErrorMessage) { $ErrorMessage } else { [DBNull]::Value }))
    [void]$cmd.Parameters.AddWithValue('@DurationMs',   $DurationMs)
    [void]$cmd.Parameters.AddWithValue('@StepId',       $StepId)
    try { [void]$cmd.ExecuteNonQuery() }
    catch { Stop-OnAuditError "step update failed (StepId $StepId, '$Status'); run halted. $($_.Exception.Message)" }
}

function Invoke-AuditedStep {
    # Runs one step of the file journey with a write-ahead step record:
    #   InProgress row -> run $Action -> Success/Failed update.
    # Audit errors halt the run (fatal); a failing $Action is re-thrown to the caller.
    param(
        [int64]$AuditId, [int]$StepNo, [string]$StepName, [string]$StepHost,
        [string]$FromPath, [string]$ToPath, [scriptblock]$Action
    )
    $stepId  = Add-StepRecord -AuditId $AuditId -StepNo $StepNo -StepName $StepName `
                              -StepHost $StepHost -FromPath $FromPath -ToPath $ToPath
    $stepSw  = [System.Diagnostics.Stopwatch]::StartNew()
    $stepErr = $null
    try { & $Action | Out-Null } catch { $stepErr = $_.Exception.Message }
    $stepSw.Stop()
    Complete-StepRecord -StepId $stepId -Status $(if ($stepErr) { 'Failed' } else { 'Success' }) `
                        -ErrorMessage $stepErr -DurationMs ([int]$stepSw.ElapsedMilliseconds)
    if ($stepErr) { throw $stepErr }
}

function Get-StoredCredential {
    param([string]$Path, [string]$Role)
    if (-not (Test-Path $Path)) {
        throw "$Role credential file not found: $Path. Create it as the service account with New-BlueYonderAptosCreds.ps1."
    }
    try { $c = Import-Clixml -Path $Path }
    catch {
        throw "$Role credential file '$Path' could not be decrypted. DPAPI files are tied to the creating user+machine; re-create it as the service account on vwpsftp01. Error: $($_.Exception.Message)"
    }
    if ($c -isnot [System.Management.Automation.PSCredential]) {
        throw "$Role credential file '$Path' did not contain a PSCredential."
    }
    return $c
}

function New-WinScpSession {
    param([hashtable]$Endpoint, [string]$Role)

    $cred = Get-StoredCredential -Path $Endpoint.CredFile -Role $Role

    if ($Endpoint.SshHostKey -like 'TODO*') {
        throw "$Role SSH host key fingerprint is not set. Capture it with WinSCP ScanFingerprint for $($Endpoint.HostName) (see script header), then paste it into the config."
    }

    $opts = New-Object WinSCP.SessionOptions -Property @{
        Protocol              = [WinSCP.Protocol]::Sftp
        HostName              = $Endpoint.HostName
        PortNumber            = $Endpoint.PortNumber
        UserName              = $cred.UserName
        Password              = $cred.GetNetworkCredential().Password
        SshHostKeyFingerprint = $Endpoint.SshHostKey
    }

    $session = New-Object WinSCP.Session
    # Each endpoint gets its OWN session log file so one session never appends to
    # another's log. Every log name carries the run timestamp, so each file is
    # written fresh, once, per run.
    if ($WinScpLogPath) {
        $session.SessionLogPath = Get-EndpointWinScpLogPath -Role $Role
    }
    Write-Log "openConnection(): connecting to $Role $($Endpoint.HostName):$($Endpoint.PortNumber) as $($cred.UserName) ..."
    $session.Open($opts)
    Write-Log "openConnection(): Connection establish to $($Endpoint.HostName)."
    return $session
}

function Get-EndpointWinScpLogPath {
    # Builds a per-endpoint, per-run WinSCP session log path from $WinScpLogPath, e.g.
    #   D:\sftp\logs\winscp_log\winscp-session.log
    #     -> D:\sftp\logs\winscp_log\winscp-session.BlueYonder_20261024-020003.log
    param([string]$Role)
    $dir  = Split-Path -Parent $WinScpLogPath
    $base = [System.IO.Path]::GetFileNameWithoutExtension($WinScpLogPath)
    $ext  = [System.IO.Path]::GetExtension($WinScpLogPath)
    $safeRole = ($Role -replace '\s', '')   # "Blue Yonder" -> "BlueYonder"
    return (Join-Path $dir ("{0}.{1}_{2}{3}" -f $base, $safeRole, $script:RunStamp, $ext))
}

function Invoke-TransferFlow {
    param(
        [string]$Name,
        [string]$Tag,             # short label for the log prefix (INVOICES / ASN / EXPORTPO)
        [WinSCP.Session]$SourceSession, [string]$SourceDir, [string]$SourceHost,
        [WinSCP.Session]$DestSession,   [string]$DestDir,   [string]$DestHost,
        [string]$Pattern,
        [string]$Direction        # BY_TO_APTOS | APTOS_TO_BY (audit column)
    )

    $script:FlowTag = $Tag
    Write-Log "Entering process."
    Write-Log "Flow: $Name"

    $remoteMask = ($SourceDir.TrimEnd('/')) + '/' + $Pattern
    Write-Log "Using remote mask '$remoteMask'."

    # List the source directory. A failure here (e.g. source folder missing or
    # inaccessible) is logged and ends the flow cleanly rather than aborting the run.
    try {
        $remoteItems = $SourceSession.ListDirectory($SourceDir).Files |
            Where-Object { -not $_.IsDirectory -and $_.Name -like $Pattern }
    }
    catch {
        Write-Log "listDirectory(): FAILED to list '$SourceDir': $($_.Exception.Message)" 'ERROR'
        $script:FailedCount++   # makes the run exit non-zero
        return
    }

    if (-not $remoteItems) {
        Write-Log "No files matching '$Pattern' in $SourceDir. Nothing to transfer."
        return
    }
    Write-Log "Found $($remoteItems.Count) file(s) matching '$Pattern' in $SourceDir."

    $transferOpts = New-Object WinSCP.TransferOptions
    $transferOpts.TransferMode = [WinSCP.TransferMode]::Binary

    $count = 0
    $localHost = $env:COMPUTERNAME

    foreach ($file in $remoteItems) {
        $fileName      = $file.Name   # NB: not $name -- PowerShell is case-insensitive and would clobber the $Name parameter
        $remoteSrcPath = ($SourceDir.TrimEnd('/')) + '/' + $fileName
        $localPath     = Join-Path $StagingPath $fileName
        $remoteDstPath = ($DestDir.TrimEnd('/')) + '/' + $fileName

        if (-not $PSCmdlet.ShouldProcess($fileName, "Transfer ($Name)")) {
            Write-Log "[WhatIf] Would transfer $remoteSrcPath -> $remoteDstPath"
            continue
        }

        # Legacy DataExchange/JDA transfer pattern (from the original job logs):
        #
        #  PICKUP (source):  download to local .TMP, rename remote source to .RN
        #                    (claim it), rename local .TMP to final.
        #  DELIVERY (dest):  upload to remote .TMP, then rename remote .TMP to the
        #                    final name so the receiving app never sees a partial file.
        #
        # The claimed source (.RN) is KEPT on the source server and is NEVER renamed
        # back: it is the "already picked up" marker that guarantees the same file is
        # not pushed to the destination twice. If anything fails after the claim the
        # file is recorded as 'Stranded' and must be reviewed/reprocessed manually.
        $localTmp     = $localPath + '.TMP'
        $remoteSrcRN  = $remoteSrcPath + '.RN'    # claimed/renamed source on the source server
        $remoteDstTmp = $remoteDstPath + '.TMP'   # in-progress upload name on the destination

        # Write-ahead audit header. If this throws (SQL down) it is NOT swallowed:
        # the run halts and this file has not been touched.
        $auditId = Start-AuditRecord -Direction $Direction -FlowName $Name -FileName $fileName `
            -SizeBytes $file.Length -SourceHost $SourceHost -SourcePath $remoteSrcPath `
            -DestHost $DestHost -DestPath $remoteDstPath

        $fileSw      = [System.Diagnostics.Stopwatch]::StartNew()
        $status      = 'Failed'
        $errMsg      = $null
        $currentStep = ''
        $claimed     = $false   # source renamed to .RN
        $delivered   = $false   # final file verified on destination

        try {
            # 1. Download source -> local .TMP.
            $currentStep = 'DownloadToLocalTmp'
            Invoke-AuditedStep -AuditId $auditId -StepNo 1 -StepName $currentStep -StepHost $SourceHost `
                -FromPath $remoteSrcPath -ToPath $localTmp -Action {
                $SourceSession.GetFiles($remoteSrcPath, $localTmp, $false, $transferOpts).Check()
                if (-not (Test-Path $localTmp)) { throw "download produced no local file: $localTmp" }
                Write-Log "getFile(): Successfully received file from $remoteSrcPath to $localTmp on machine $SourceHost"
            }

            # 2. Claim the source by renaming it to .RN on the source server.
            $currentStep = 'ClaimSourceRN'
            Invoke-AuditedStep -AuditId $auditId -StepNo 2 -StepName $currentStep -StepHost $SourceHost `
                -FromPath $remoteSrcPath -ToPath $remoteSrcRN -Action {
                $SourceSession.MoveFile($remoteSrcPath, $remoteSrcRN)
                Write-Log "renameRemoteFile(): Successfully renamed $remoteSrcPath to $remoteSrcRN"
            }
            $claimed = $true   # from here on the .RN stays on the source no matter what

            # 3. Rename local .TMP to its final name (download now complete).
            $currentStep = 'RenameLocalTmpToFinal'
            Invoke-AuditedStep -AuditId $auditId -StepNo 3 -StepName $currentStep -StepHost $localHost `
                -FromPath $localTmp -ToPath $localPath -Action {
                if (Test-Path $localPath) { Remove-Item $localPath -Force }
                Rename-Item -Path $localTmp -NewName $fileName
                Write-Log "Successfully renamed local file from $localTmp to $localPath"
            }

            # 4. Upload local file to a remote .TMP name on the destination.
            $currentStep = 'UploadToRemoteTmp'
            Invoke-AuditedStep -AuditId $auditId -StepNo 4 -StepName $currentStep -StepHost $DestHost `
                -FromPath $localPath -ToPath $remoteDstTmp -Action {
                $DestSession.PutFiles($localPath, $remoteDstTmp, $false, $transferOpts).Check()
                Write-Log "sendFile(): Successfully sent file from $localPath to $remoteDstTmp on machine $DestHost"
            }

            # 5. Rename remote .TMP to the final name (atomic reveal).
            $currentStep = 'RenameRemoteTmpToFinal'
            Invoke-AuditedStep -AuditId $auditId -StepNo 5 -StepName $currentStep -StepHost $DestHost `
                -FromPath $remoteDstTmp -ToPath $remoteDstPath -Action {
                $DestSession.MoveFile($remoteDstTmp, $remoteDstPath)
                Write-Log "renameRemoteFile(): Successfully renamed $remoteDstTmp to $remoteDstPath on machine $DestHost"
            }

            # 6. Verify the final file exists on the destination.
            $currentStep = 'VerifyDestination'
            Invoke-AuditedStep -AuditId $auditId -StepNo 6 -StepName $currentStep -StepHost $DestHost `
                -FromPath $remoteDstPath -ToPath $remoteDstPath -Action {
                if (-not $DestSession.FileExists($remoteDstPath)) {
                    throw "delivery verification failed: $remoteDstPath not found on destination $DestHost"
                }
                Write-Log "Delivered to destination: $remoteDstPath on machine $DestHost"
            }
            $delivered = $true
            $status    = 'Success'

            # 7. Delete the claimed source (.RN) -- ONLY with -DeleteSourceAfter.
            #    Default: keep it, so the file can never be pushed twice.
            if ($DeleteSourceAfter) {
                $currentStep = 'DeleteSourceRN'
                try {
                    Invoke-AuditedStep -AuditId $auditId -StepNo 7 -StepName $currentStep -StepHost $SourceHost `
                        -FromPath $remoteSrcRN -ToPath $null -Action {
                        $SourceSession.RemoveFiles($remoteSrcRN).Check()
                        Write-Log "removeRemoteFile(): Successfully deleted file $remoteSrcRN"
                    }
                }
                catch {
                    if ($script:AuditFatal) { throw }
                    $status = 'Warning'
                    $errMsg = "Delivered, but delete of $remoteSrcRN failed: $($_.Exception.Message)"
                    Write-Log "removeRemoteFile(): FAILED to delete $remoteSrcRN on machine ${SourceHost}: $($_.Exception.Message)" 'ERROR'
                }
            }
            else {
                [void](Add-StepRecord -AuditId $auditId -StepNo 7 -StepName 'DeleteSourceRN' -StepHost $SourceHost `
                    -FromPath $remoteSrcRN -ToPath $null -Status 'Skipped')
                Write-Log "DeleteSourceAfter not set; keeping claimed source on the source server: $remoteSrcRN"
            }
        }
        catch {
            # An audit (SQL) failure must halt the whole run, not just this file.
            if ($script:AuditFatal) { throw }

            $errMsg = "Step $currentStep failed: $($_.Exception.Message)"
            if ($claimed) {
                # Source is claimed but delivery did not complete. Keep the .RN (no rollback).
                $status = 'Stranded'
                $errMsg += " | Source kept as $remoteSrcRN (no rollback, to avoid duplicate delivery). Check '$DestDir' on $DestHost for $fileName / $fileName.TMP before reprocessing manually."
                Write-Log "STRANDED '$fileName': $errMsg" 'ERROR'
            }
            else {
                $status = 'Failed'
                Write-Log "FAILED '$fileName' (source untouched, will be retried next run): $errMsg" 'ERROR'
            }
        }
        finally {
            # Always clean up any local staging copies (.TMP and final).
            if (Test-Path $localTmp)  { Remove-Item $localTmp  -Force -ErrorAction SilentlyContinue }
            if (Test-Path $localPath) { Remove-Item $localPath -Force -ErrorAction SilentlyContinue }
        }

        $fileSw.Stop()
        # Outside the try/catch on purpose: an audit failure here must halt the run.
        Complete-AuditRecord -AuditId $auditId -Status $status -ErrorMessage $errMsg -DurationMs ([int]$fileSw.ElapsedMilliseconds)

        switch ($status) {
            'Success'  { $count++ }
            'Warning'  { $count++ }
            'Stranded' { $script:StrandedCount++ }
            'Failed'   { $script:FailedCount++ }
        }
    }

    Write-Log "$count of $($remoteItems.Count) file(s) transferred."
    Write-Log "Exiting process."
}

# --- Preflight -------------------------------------------------------------
foreach ($dir in @($StagingPath, (Split-Path $LogPath), (Split-Path $WinScpLogPath))) {
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# NOTE: no log deletion here. Each run writes to its OWN timestamped log files
# ($RunStamp), so nothing is ever overwritten or appended. Previous runs' logs
# are preserved for history. (See the optional retention cleanup below if you
# want to cap how many old logs are kept.)

if (-not (Test-Path $WinScpDllPath)) {
    throw "WinSCP .NET assembly not found at '$WinScpDllPath'. Install WinSCP or correct the path."
}
Add-Type -Path $WinScpDllPath
Write-Log "Loaded WinSCP assembly from $WinScpDllPath"

$byeSession   = $null
$aptosSession = $null

try {
    # Audit DB first: if SQL is down, halt before any SFTP connection or transfer.
    Open-AuditConnection

    $byeSession   = New-WinScpSession -Endpoint $BlueYonder -Role 'Blue Yonder'
    $aptosSession = New-WinScpSession -Endpoint $Aptos      -Role 'Aptos'

    if ($Mode -in @('Both', 'InvoicesOnly')) {
        # One flow per routing rule: same Blue Yonder outbox, different Aptos
        # destination per filename pattern (invoices, ASN, ...).
        foreach ($route in $OutboundRoutes) {
            Invoke-TransferFlow -Name "$($route.Label) Blue Yonder -> Aptos" -Tag $route.Tag `
                -SourceSession $byeSession   -SourceDir $BlueYonder.OutboxPath -SourceHost $BlueYonder.HostName `
                -DestSession   $aptosSession -DestDir   $route.DestPath        -DestHost   $Aptos.HostName `
                -Pattern $route.Pattern -Direction 'BY_TO_APTOS'
        }
    }

    if ($Mode -in @('Both', 'PosOnly')) {
        Invoke-TransferFlow -Name 'PURCHASE ORDERS Aptos -> Blue Yonder' -Tag 'EXPORTPO' `
            -SourceSession $aptosSession -SourceDir $Aptos.PurchaseOutPath -SourceHost $Aptos.HostName `
            -DestSession   $byeSession   -DestDir   $BlueYonder.InboxPath  -DestHost   $BlueYonder.HostName `
            -Pattern $PoPattern -Direction 'APTOS_TO_BY'
    }

    Write-Log "All requested flows completed."
}
catch {
    Write-Log "Run failed: $($_.Exception.Message)" 'ERROR'
    # Exit with a non-zero code so SQL Agent (CmdExec) marks the job step as FAILED.
    exit 1
}
finally {
    if ($byeSession)   { $byeSession.Dispose();   Write-Log "Closed Blue Yonder session." }
    if ($aptosSession) { $aptosSession.Dispose(); Write-Log "Closed Aptos session." }
    if ($script:AuditConn) { $script:AuditConn.Dispose(); Write-Log "Closed audit database connection." }
}

# Per-file problems must not look like success to SQL Agent / Task Scheduler.
if ($script:FailedCount -gt 0 -or $script:StrandedCount -gt 0) {
    $script:FlowTag = 'SUMMARY'
    Write-Log "Run finished WITH ERRORS: $($script:FailedCount) failed (will retry), $($script:StrandedCount) stranded (.RN kept on source, manual review needed)." 'ERROR'
    exit 1
}
exit 0

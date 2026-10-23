<#
.SYNOPSIS
    Replaces the legacy DataExchange/JDA SFTP job. Moves files between Blue Yonder
    and Aptos SFTP servers, brokered through vwpsftp01 using the WinSCP .NET assembly.

        Blue Yonder SFTP  <-->  vwpsftp01 (staging)  <-->  Aptos SFTP

    Two flows per run (mirroring the original job):
      INVOICES-TO-APTOS : Blue Yonder /home/europatprdv2/outbox (STSIMATIN*.go)
                          -> Aptos /Transfer/IN/Merch/Invoices/Company1
      POS-TO-BY         : Aptos /Transfer/Out/Merch/PurchaseOrder
                          -> Blue Yonder /home/europatprdv2/inbox

.DESCRIPTION
    SFTP cannot stream directly between two remote servers, so vwpsftp01 is the
    broker: each file is downloaded from the source into a local staging folder,
    uploaded to the destination, verified, and then ARCHIVED on the source server
    (moved into the source's archive folder) rather than deleted. The local
    staging copy is always cleaned up.

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

.PARAMETER ArchiveSource
    After a verified upload, archive each source file by moving it into the source
    server's ArchivePath (see config), instead of leaving it in the source folder.
    Defaults to $true (required production behaviour). Pass -ArchiveSource:$false
    for a pure non-destructive copy during early testing.

.PARAMETER ArchiveDestination
    Also place an archive COPY of each file in the destination server's
    DestArchivePath (see config). The delivered file stays in the destination
    folder for the receiving application; this just adds a second copy under the
    archive folder. OFF by default; enable only if the application team confirms
    destination archiving is required.

.PARAMETER WhatIf
    Dry run: logs what each flow WOULD transfer without moving anything.

.EXAMPLE
    .\Sync-BlueYonder-Aptos.ps1 -WhatIf                     # safe first run, nothing moves
    .\Sync-BlueYonder-Aptos.ps1 -ArchiveSource:$false       # both flows, copy only (no archive)
    .\Sync-BlueYonder-Aptos.ps1                             # both flows, copy + archive source (production)

.NOTES
    Requires WinSCP installed on vwpsftp01 (WinSCPnet.dll). Adjust $WinScpDllPath
    if WinSCP is not at the default location.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Both', 'InvoicesOnly', 'PosOnly')]
    [string]$Mode = 'Both',

    [string]$CredentialFolder = 'C:\sftp\creds',
    [string]$StagingPath      = 'C:\sftp\staging',
    [string]$LogPath          = 'C:\sftp\logs\blueyonder-aptos.log',
    [string]$WinScpLogPath    = 'C:\sftp\logs\winscp-session.log',

    # After a verified upload, archive each source file into the source server's
    # ArchivePath (a MOVE within the source server) instead of leaving it in place.
    # On by default: this is the required production behaviour. Use -ArchiveSource:$false
    # for a pure non-destructive copy during early testing.
    [bool]$ArchiveSource = $true,

    # Also keep an archive copy of each file on the DESTINATION server, placed in
    # the destination's ArchivePath. This is a COPY (the delivered file stays in
    # the destination folder for the receiving application). OFF by default; enable
    # only if the application team confirms destination archiving is required.
    [switch]$ArchiveDestination
)

$ErrorActionPreference = 'Stop'

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
    SshHostKey     = 'TODO-PASTE-BLUEYONDER-HOSTKEY-FINGERPRINT'   # scan with WinSCP ScanFingerprint (see header) for PRODB2BGW02.jdadelivers.com
    OutboxPath     = '/home/eurorpatprdv2/outbox'   # invoices come FROM here (absolute, uses login-user home)
    InboxPath      = '/home/eurorpatprdv2/inbox'    # POs go TO here (absolute, uses login-user home)
    # Archive folder on Blue Yonder for SOURCE files picked up from OutboxPath.
    # TODO: confirm the exact absolute archive path with the application team.
    ArchivePath    = '/home/eurorpatprdv2/outbox/archive'
    # Archive folder on Blue Yonder for DESTINATION files delivered to InboxPath
    # (only used when -ArchiveDestination is supplied). TODO: confirm with app team.
    DestArchivePath = '/home/eurorpatprdv2/inbox/archive'
}

# --- Aptos SFTP endpoint ---
$Aptos = @{
    HostName        = '10.252.16.100'
    PortNumber      = 22
    CredFile        = Join-Path $CredentialFolder 'aptos.cred.xml'
    SshHostKey      = 'TODO-PASTE-APTOS-HOSTKEY-FINGERPRINT'       # scan with WinSCP ScanFingerprint (see header) for 10.252.16.100
    InvoicesInPath  = '/Transfer/IN/Merch/Invoices/Company1'      # invoices go TO here
    PurchaseOutPath = '/Transfer/Out/Merch/PurchaseOrder'         # POs come FROM here
    # Archive folder on Aptos for SOURCE files picked up from PurchaseOutPath.
    # TODO: confirm the exact absolute archive path with the application team.
    ArchivePath     = '/Transfer/Out/Merch/PurchaseOrder/archive'
    # Archive folder on Aptos for DESTINATION files delivered to InvoicesInPath
    # (only used when -ArchiveDestination is supplied). TODO: confirm with app team.
    DestArchivePath = '/Transfer/IN/Merch/Invoices/Company1/archive'
}

# File patterns per flow (from the legacy job):
$InvoicePattern = 'STSIMATIN*.go'   # invoices from Blue Yonder outbox
$PoPattern      = '*'               # purchase orders from Aptos

# ===========================================================================
# IMPLEMENTATION  --  no edits needed below
# ===========================================================================

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch { }
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
    if ($WinScpLogPath) { $session.SessionLogPath = $WinScpLogPath }
    Write-Log "Connecting to $Role $($Endpoint.HostName):$($Endpoint.PortNumber) as $($cred.UserName) ..."
    $session.Open($opts)
    Write-Log "$Role session opened."
    return $session
}

function Invoke-TransferFlow {
    param(
        [string]$Name,
        [WinSCP.Session]$SourceSession, [string]$SourceDir,
        [WinSCP.Session]$DestSession,   [string]$DestDir,
        [string]$Pattern,
        [string]$ArchiveDir,      # folder on the SOURCE server to move files into after a verified upload
        [string]$DestArchiveDir   # folder on the DESTINATION server to copy delivered files into (optional)
    )

    Write-Log "=== FLOW: $Name ==="

    # Ensure the source-server archive folder exists (idempotent).
    if ($ArchiveSource -and $ArchiveDir) {
        if (-not $SourceSession.FileExists($ArchiveDir)) {
            Write-Log "Creating archive folder on source: $ArchiveDir"
            $SourceSession.CreateDirectory($ArchiveDir)
        }
    }

    # Ensure the destination-server archive folder exists (idempotent), only when enabled.
    if ($ArchiveDestination -and $DestArchiveDir) {
        if (-not $DestSession.FileExists($DestArchiveDir)) {
            Write-Log "Creating archive folder on destination: $DestArchiveDir"
            $DestSession.CreateDirectory($DestArchiveDir)
        }
    }

    $remoteItems = $SourceSession.ListDirectory($SourceDir).Files |
        Where-Object { -not $_.IsDirectory -and $_.Name -like $Pattern }

    if (-not $remoteItems) {
        Write-Log "No files matching '$Pattern' in $SourceDir. Nothing to transfer." 'WARN'
        return
    }
    Write-Log "Found $($remoteItems.Count) file(s) matching '$Pattern' in $SourceDir."

    $transferOpts = New-Object WinSCP.TransferOptions
    $transferOpts.TransferMode = [WinSCP.TransferMode]::Binary

    $count = 0
    foreach ($file in $remoteItems) {
        $name          = $file.Name
        $remoteSrcPath = ($SourceDir.TrimEnd('/')) + '/' + $name
        $localPath     = Join-Path $StagingPath $name
        $remoteDstPath = ($DestDir.TrimEnd('/')) + '/' + $name
        $remoteArchivePath = if ($ArchiveDir) { ($ArchiveDir.TrimEnd('/')) + '/' + $name } else { $null }
        $remoteDestArchivePath = if ($DestArchiveDir) { ($DestArchiveDir.TrimEnd('/')) + '/' + $name } else { $null }

        if (-not $PSCmdlet.ShouldProcess($name, "Transfer ($Name)")) {
            Write-Log "[WhatIf] Would transfer $remoteSrcPath -> $remoteDstPath"
            continue
        }

        try {
            # 1. Download source -> staging
            Write-Log "Download $remoteSrcPath -> $localPath"
            $SourceSession.GetFiles($remoteSrcPath, $localPath, $false, $transferOpts).Check()

            if (-not (Test-Path $localPath)) {
                Write-Log "Download produced no local file: $localPath" 'ERROR'
                continue
            }

            # 2. Upload staging -> destination
            Write-Log "Upload $localPath -> $remoteDstPath"
            $DestSession.PutFiles($localPath, $remoteDstPath, $false, $transferOpts).Check()

            # 3. Verify on destination
            if (-not $DestSession.FileExists($remoteDstPath)) {
                Write-Log "Upload verification failed: $remoteDstPath not found on destination." 'ERROR'
                continue
            }
            Write-Log "Verified on destination: $remoteDstPath"

            # 4. Archive the source file (move within the source server) after a
            #    verified upload. This replaces deletion: the original is preserved
            #    under the source server's archive folder.
            if ($ArchiveSource -and $remoteArchivePath) {
                Write-Log "Archiving source $remoteSrcPath -> $remoteArchivePath"
                # MoveFile(sourcePath, targetPath). WinSCP overwrites if the target
                # already exists; the target name matches the original file name.
                $SourceSession.MoveFile($remoteSrcPath, $remoteArchivePath)
                if (-not $SourceSession.FileExists($remoteArchivePath)) {
                    Write-Log "Archive verification failed: $remoteArchivePath not found after move." 'ERROR'
                    continue
                }
                Write-Log "Archived on source: $remoteArchivePath"
            }

            # 4b. Optionally keep an archive COPY on the destination server. The
            #     delivered file in $DestDir is left in place for the receiving
            #     application; a second copy is placed in the destination archive
            #     folder. Re-uploads the already-verified local staging copy.
            if ($ArchiveDestination -and $remoteDestArchivePath) {
                Write-Log "Archiving on destination (copy) $localPath -> $remoteDestArchivePath"
                $DestSession.PutFiles($localPath, $remoteDestArchivePath, $false, $transferOpts).Check()
                if (-not $DestSession.FileExists($remoteDestArchivePath)) {
                    Write-Log "Destination archive verification failed: $remoteDestArchivePath not found." 'ERROR'
                    continue
                }
                Write-Log "Archived on destination: $remoteDestArchivePath"
            }

            $count++
        }
        catch {
            Write-Log "Error transferring '$name': $($_.Exception.Message)" 'ERROR'
        }
        finally {
            # 5. Always clean up staging copy
            if (Test-Path $localPath) { Remove-Item $localPath -Force -ErrorAction SilentlyContinue }
        }
    }

    Write-Log "FLOW '$Name' complete: $count of $($remoteItems.Count) file(s) transferred."
}

# --- Preflight -------------------------------------------------------------
foreach ($dir in @($StagingPath, (Split-Path $LogPath), (Split-Path $WinScpLogPath))) {
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

if (-not (Test-Path $WinScpDllPath)) {
    throw "WinSCP .NET assembly not found at '$WinScpDllPath'. Install WinSCP or correct the path."
}
Add-Type -Path $WinScpDllPath
Write-Log "Loaded WinSCP assembly from $WinScpDllPath"

$byeSession   = $null
$aptosSession = $null

try {
    $byeSession   = New-WinScpSession -Endpoint $BlueYonder -Role 'Blue Yonder'
    $aptosSession = New-WinScpSession -Endpoint $Aptos      -Role 'Aptos'

    if ($Mode -in @('Both', 'InvoicesOnly')) {
        Invoke-TransferFlow -Name 'INVOICES Blue Yonder -> Aptos' `
            -SourceSession $byeSession   -SourceDir $BlueYonder.OutboxPath `
            -DestSession   $aptosSession -DestDir   $Aptos.InvoicesInPath `
            -Pattern $InvoicePattern `
            -ArchiveDir $BlueYonder.ArchivePath `
            -DestArchiveDir $Aptos.DestArchivePath
    }

    if ($Mode -in @('Both', 'PosOnly')) {
        Invoke-TransferFlow -Name 'PURCHASE ORDERS Aptos -> Blue Yonder' `
            -SourceSession $aptosSession -SourceDir $Aptos.PurchaseOutPath `
            -DestSession   $byeSession   -DestDir   $BlueYonder.InboxPath `
            -Pattern $PoPattern `
            -ArchiveDir $Aptos.ArchivePath `
            -DestArchiveDir $BlueYonder.DestArchivePath
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
}

exit 0

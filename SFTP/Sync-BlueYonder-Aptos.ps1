<#
.SYNOPSIS
    Replaces the legacy DataExchange/JDA SFTP job. Moves files between Blue Yonder
    and Aptos SFTP servers, brokered through vwpsftp01 using the WinSCP .NET assembly.

        Blue Yonder SFTP  <-->  vwpsftp01 (staging)  <-->  Aptos SFTP

    Flows per run (mirroring the original job):
      INVOICES -> APTOS : Blue Yonder /home/eurorpatprdv2/outbox (STSIMATIN*.go)
                          -> Aptos /Transfer/IN/Merch/Invoices/Company1
      ASN      -> APTOS : Blue Yonder /home/eurorpatprdv2/outbox (STSIMASN*.go)
                          -> Aptos '/Transfer/IN/Merch/EDI ASN'
      POS      -> BY    : Aptos /Transfer/Out/Merch/PurchaseOrder
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

    [string]$CredentialFolder = 'C:\sftp\creds',
    [string]$StagingPath      = 'C:\sftp\staging',
    [string]$LogPath          = 'C:\sftp\logs\blueyonder-aptos.log',
    [string]$WinScpLogPath    = 'C:\sftp\logs\winscp-session.log',

    # Safety switch. When supplied, the claimed source file (renamed to .RN during
    # pickup) is DELETED after a verified delivery -- a true MOVE, matching the
    # legacy job. When omitted (default), delivery still completes but the claimed
    # source .RN file is LEFT in place on the source server, so nothing is deleted.
    [switch]$DeleteSourceAfter
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
}

# --- Aptos SFTP endpoint ---
$Aptos = @{
    HostName        = '10.252.16.100'
    PortNumber      = 22
    CredFile        = Join-Path $CredentialFolder 'aptos.cred.xml'
    SshHostKey      = 'TODO-PASTE-APTOS-HOSTKEY-FINGERPRINT'       # scan with WinSCP ScanFingerprint (see header) for 10.252.16.100
    InvoicesInPath  = '/Transfer/IN/Merch/Invoices/Company1'      # invoices (STSIMATIN*.go) go TO here
    AsnInPath       = '/Transfer/IN/Merch/EDI ASN'               # ASNs (STSIMASN*.go) go TO here (note the space)
    PurchaseOutPath = '/Transfer/Out/Merch/PurchaseOrder'         # POs come FROM here
}

# Blue Yonder outbox -> Aptos routing. Each entry maps a filename pattern in the
# Blue Yonder outbox to its Aptos destination folder. Add more rows here to route
# additional document types from the same outbox.
$OutboundRoutes = @(
    @{ Label = 'INVOICES'; Pattern = 'STSIMATIN*.go'; DestPath = $Aptos.InvoicesInPath }
    @{ Label = 'ASN';      Pattern = 'STSIMASN*.go';  DestPath = $Aptos.AsnInPath }
)

# Aptos -> Blue Yonder purchase orders.
$PoPattern = '*'   # purchase orders from Aptos

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
        [string]$Pattern
    )

    Write-Log "=== FLOW: $Name ==="

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

        if (-not $PSCmdlet.ShouldProcess($name, "Transfer ($Name)")) {
            Write-Log "[WhatIf] Would transfer $remoteSrcPath -> $remoteDstPath"
            continue
        }

        # Legacy DataExchange/JDA transfer pattern (from the original job logs):
        #
        #  PICKUP (source):  download to local .TMP, rename remote source to .RN
        #                    (claim it), rename local .TMP to final, delete .RN.
        #  DELIVERY (dest):  upload to remote .TMP, then rename remote .TMP to the
        #                    final name so the receiving app never sees a partial file.
        #
        # Both directions are a MOVE: the source file is consumed after success.
        $localTmp       = $localPath + '.TMP'
        $remoteSrcRN    = $remoteSrcPath + '.RN'    # claimed/renamed source on the source server
        $remoteDstTmp   = $remoteDstPath + '.TMP'   # in-progress upload name on the destination

        try {
            # 1. Download source -> local .TMP (partial downloads are not mistaken
            #    for complete files).
            Write-Log "getFile(): $remoteSrcPath -> $localTmp"
            $SourceSession.GetFiles($remoteSrcPath, $localTmp, $false, $transferOpts).Check()

            if (-not (Test-Path $localTmp)) {
                Write-Log "Download produced no local file: $localTmp" 'ERROR'
                continue
            }

            # 2. Claim the source by renaming it to .RN on the source server.
            Write-Log "renameRemoteFile(): $remoteSrcPath -> $remoteSrcRN"
            $SourceSession.MoveFile($remoteSrcPath, $remoteSrcRN)

            # 3. Rename local .TMP to its final name (download now complete).
            if (Test-Path $localPath) { Remove-Item $localPath -Force -ErrorAction SilentlyContinue }
            Rename-Item -Path $localTmp -NewName $name
            Write-Log "Renamed local $localTmp -> $localPath"

            # 4. Upload local file to a remote .TMP name on the destination.
            Write-Log "sendFile(): $localPath -> $remoteDstTmp"
            $DestSession.PutFiles($localPath, $remoteDstTmp, $false, $transferOpts).Check()

            # 5. Rename remote .TMP to the final name so the receiving app only
            #    ever sees a complete file (atomic reveal).
            Write-Log "renameRemoteFile(): $remoteDstTmp -> $remoteDstPath"
            $DestSession.MoveFile($remoteDstTmp, $remoteDstPath)

            if (-not $DestSession.FileExists($remoteDstPath)) {
                Write-Log "Delivery verification failed: $remoteDstPath not found on destination." 'ERROR'
                continue
            }
            Write-Log "Delivered to destination: $remoteDstPath"

            # 6. Remove the claimed source file (.RN) from the source server.
            #    Gated behind -DeleteSourceAfter as a safety measure: without it,
            #    the claimed .RN file is left in place and nothing is deleted.
            if ($DeleteSourceAfter) {
                Write-Log "removeRemoteFile(): $remoteSrcRN"
                $SourceSession.RemoveFiles($remoteSrcRN).Check()
            }
            else {
                Write-Log "DeleteSourceAfter not set; leaving claimed source in place: $remoteSrcRN"
            }

            $count++
        }
        catch {
            Write-Log "Error transferring '$name': $($_.Exception.Message)" 'ERROR'
        }
        finally {
            # Always clean up any local staging copies (.TMP and final).
            if (Test-Path $localTmp)  { Remove-Item $localTmp  -Force -ErrorAction SilentlyContinue }
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
        # One flow per routing rule: same Blue Yonder outbox, different Aptos
        # destination per filename pattern (invoices, ASN, ...).
        foreach ($route in $OutboundRoutes) {
            Invoke-TransferFlow -Name "$($route.Label) Blue Yonder -> Aptos" `
                -SourceSession $byeSession   -SourceDir $BlueYonder.OutboxPath `
                -DestSession   $aptosSession -DestDir   $route.DestPath `
                -Pattern $route.Pattern
        }
    }

    if ($Mode -in @('Both', 'PosOnly')) {
        Invoke-TransferFlow -Name 'PURCHASE ORDERS Aptos -> Blue Yonder' `
            -SourceSession $aptosSession -SourceDir $Aptos.PurchaseOutPath `
            -DestSession   $byeSession   -DestDir   $BlueYonder.InboxPath `
            -Pattern $PoPattern
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

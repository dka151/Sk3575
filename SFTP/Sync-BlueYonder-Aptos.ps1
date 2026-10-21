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
    uploaded to the destination, verified, and (optionally) removed from the
    source after a verified upload. The staging copy is always cleaned up.

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
    Delete each source file after a verified upload (a MOVE, matching the original
    job's behaviour of consuming files from the outbox/outbound folders). Off by
    default so your first runs are non-destructive copies.

.PARAMETER WhatIf
    Dry run: logs what each flow WOULD transfer without moving anything.

.EXAMPLE
    .\Sync-BlueYonder-Aptos.ps1 -WhatIf                 # safe first run
    .\Sync-BlueYonder-Aptos.ps1                         # both flows, copy
    .\Sync-BlueYonder-Aptos.ps1 -DeleteSourceAfter      # both flows, move (production)

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
    OutboxPath     = '/home/europatprdv2/outbox'   # invoices come FROM here
    InboxPath      = '/home/europatprdv2/inbox'    # POs go TO here
}

# --- Aptos SFTP endpoint ---
$Aptos = @{
    HostName        = '10.252.16.100'
    PortNumber      = 22
    CredFile        = Join-Path $CredentialFolder 'aptos.cred.xml'
    SshHostKey      = 'TODO-PASTE-APTOS-HOSTKEY-FINGERPRINT'       # scan with WinSCP ScanFingerprint (see header) for 10.252.16.100
    InvoicesInPath  = '/Transfer/IN/Merch/Invoices/Company1'      # invoices go TO here
    PurchaseOutPath = '/Transfer/Out/Merch/PurchaseOrder'         # POs come FROM here
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

            # 4. Optional: delete source after verified upload
            if ($DeleteSourceAfter) {
                Write-Log "Deleting source $remoteSrcPath"
                $SourceSession.RemoveFiles($remoteSrcPath).Check()
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
            -Pattern $InvoicePattern
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
    throw
}
finally {
    if ($byeSession)   { $byeSession.Dispose();   Write-Log "Closed Blue Yonder session." }
    if ($aptosSession) { $aptosSession.Dispose(); Write-Log "Closed Aptos session." }
}

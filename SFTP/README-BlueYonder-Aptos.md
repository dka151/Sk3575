# Blue Yonder ↔ Aptos SFTP Transfer — Runbook

Replacement for the legacy DataExchange/JDA SFTP job. Moves files between the
Blue Yonder and Aptos SFTP servers, brokered through **vwpsftp01** (which has
WinSCP installed and network access to both endpoints).

```
Blue Yonder SFTP  <-->  vwpsftp01 (staging, WinSCP)  <-->  Aptos SFTP
```

SFTP cannot stream directly between two remote servers, so vwpsftp01 downloads
each file to a local staging folder, uploads it to the other server, verifies
it, and (in production) deletes the source copy after a verified upload.

## Flows

| Flow | Source | Pattern | Destination |
|------|--------|---------|-------------|
| Invoices | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/europatprdv2/outbox` | `STSIMATIN*.go` | Aptos `10.252.16.100:/Transfer/IN/Merch/Invoices/Company1` |
| Purchase Orders | Aptos `10.252.16.100:/Transfer/Out/Merch/PurchaseOrder` | `*` | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/europatprdv2/inbox` |

## Endpoints

| | Blue Yonder | Aptos |
|---|-------------|-------|
| Host | `PRODB2BGW02.jdadelivers.com` | `10.252.16.100` |
| Port | 22 | 22 |
| User | `eurorpatprdv2` (CONFIRM spelling vs path `europatprdv2`) | `WSsftpuser` |

> Passwords are never stored in the scripts. They live in DPAPI-encrypted
> credential files created in step 3.

## Files (deploy these to `C:\sftp\` on vwpsftp01)

- `Sync-BlueYonder-Aptos.ps1` — the transfer job
- `New-BlueYonderAptosCreds.ps1` — one-time credential file creator
- `Register-BlueYonderAptosTask.ps1` — registers the scheduled task

Suggested layout on vwpsftp01:

```
C:\sftp\
  Sync-BlueYonder-Aptos.ps1
  New-BlueYonderAptosCreds.ps1
  Register-BlueYonderAptosTask.ps1
  creds\      <- credential files (step 3)
  staging\    <- transient; files pass through here
  logs\       <- transfer + WinSCP session logs
```

## One-time setup on vwpsftp01

### 1. Prerequisites
- WinSCP installed (default: `C:\Program Files (x86)\WinSCP\WinSCPnet.dll`).
  If installed elsewhere, edit `$WinScpDllPath` in `Sync-BlueYonder-Aptos.ps1`.
- A service account to run the task (e.g. `DOMAIN\svc-sftp`) with "Log on as a batch job" right.

### 2. Confirm connectivity (corrected Aptos IP)
```powershell
Test-NetConnection -ComputerName 10.252.16.100           -Port 22
Test-NetConnection -ComputerName PRODB2BGW02.jdadelivers.com -Port 22
```
Both must show `TcpTestSucceeded : True`. If Aptos fails, raise a firewall
request: source = vwpsftp01 IP, destination = `10.252.16.100`, port 22/TCP.

### 3. Capture SSH host key fingerprints, then paste into the script
Use the WinSCP .NET assembly's `ScanFingerprint` (no credentials needed, works
on all recent versions):
```powershell
Add-Type -Path "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
foreach ($h in 'PRODB2BGW02.jdadelivers.com', '10.252.16.100') {
    $opts = New-Object WinSCP.SessionOptions -Property @{
        Protocol = [WinSCP.Protocol]::Sftp; HostName = $h; PortNumber = 22
    }
    $session = New-Object WinSCP.Session
    try { Write-Host "$h  ->  $($session.ScanFingerprint($opts, 'SHA-256'))" }
    finally { $session.Dispose() }
}
```
Alternatively, with the WinSCP command-line client (prints the fingerprint in
its output; `-hostkey=*` accepts any key just for the scan):
```powershell
& "C:\Program Files (x86)\WinSCP\WinSCP.com" /command `
  "open sftp://PRODB2BGW02.jdadelivers.com/ -hostkey=*" "exit"
& "C:\Program Files (x86)\WinSCP\WinSCP.com" /command `
  "open sftp://10.252.16.100/ -hostkey=*" "exit"
```
Put each returned fingerprint into the matching `SshHostKey` field in
`Sync-BlueYonder-Aptos.ps1`. This pins the server identity and prevents
man-in-the-middle connections.

> Note: `/keygen /scanhostkey` is NOT valid — `/keygen` only converts key files.
> Scanning requires TCP reachability, so scan Aptos only after step 2 passes.

### 4. Create encrypted credential files AS THE SERVICE ACCOUNT
DPAPI ties each file to the creating user + machine, so this MUST run as the
service account on vwpsftp01:
```powershell
runas /user:DOMAIN\svc-sftp powershell.exe
# in the new window:
cd C:\sftp
.\New-BlueYonderAptosCreds.ps1 -OutputFolder 'C:\sftp\creds'
```
Produces `C:\sftp\creds\blueyonder.cred.xml` and `aptos.cred.xml`.
Lock down `C:\sftp\creds` so only the service account and admins can read it.

### 5. Test before scheduling
Run as the service account:
```powershell
cd C:\sftp
.\Sync-BlueYonder-Aptos.ps1 -WhatIf              # lists what WOULD move, moves nothing
.\Sync-BlueYonder-Aptos.ps1                      # real run, COPY (non-destructive)
.\Sync-BlueYonder-Aptos.ps1 -DeleteSourceAfter   # real run, MOVE (deletes source after verified upload)
```
Check `C:\sftp\logs\blueyonder-aptos.log` and confirm files landed on both sides.
Run the `-DeleteSourceAfter` (move) command only once you are satisfied the copy
runs are landing correctly — this matches the production/scheduled behaviour.

### 6. Register the scheduled task (as administrator)
```powershell
cd C:\sftp
.\Register-BlueYonderAptosTask.ps1 -ServiceAccount 'DOMAIN\svc-sftp' `
    -ScriptPath 'C:\sftp\Sync-BlueYonder-Aptos.ps1' `
    -StartTime '02:00' -RepeatMinutes 30
```
The task runs with `-DeleteSourceAfter` (move mode), both flows, whether or not
the user is logged on. Edit the script's `$scriptArgs` to change behaviour.

## Operations

```powershell
# Inspect
Get-ScheduledTask -TaskName 'BlueYonder-Aptos SFTP Transfer' | Get-ScheduledTaskInfo
# Run on demand
Start-ScheduledTask -TaskName 'BlueYonder-Aptos SFTP Transfer'
# Logs
Get-Content C:\sftp\logs\blueyonder-aptos.log -Tail 50
Get-Content C:\sftp\logs\winscp-session.log  -Tail 50
```

### Run modes
```powershell
.\Sync-BlueYonder-Aptos.ps1 -Mode InvoicesOnly    # Blue Yonder -> Aptos only
.\Sync-BlueYonder-Aptos.ps1 -Mode PosOnly         # Aptos -> Blue Yonder only
.\Sync-BlueYonder-Aptos.ps1 -Mode Both            # default
```

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `could not be decrypted` on a cred file | Files created under a different account/machine. Re-run step 4 as the service account on vwpsftp01. |
| `SSH host key ... not set` | Step 3 not done; paste fingerprints into the script. |
| `TcpTestSucceeded : False` to Aptos | Firewall/routing; raise a request for vwpsftp01 -> 10.252.16.100:22. |
| Host key mismatch at connect | Server key changed or wrong fingerprint pinned. Re-scan (step 3) and confirm with the server owner. |
| No files transferred, "No files matching" | Pattern or folder mismatch. Confirm `STSIMATIN*.go` and the remote paths. |

## Outstanding items to confirm
- **Username spelling:** `eurorpatprdv2` (given) vs `europatprdv2` (in the paths). One likely has a typo.
- **Rotate the Blue Yonder password** after go-live, since it was shared during setup.
- **Schedule cadence:** confirm desired run time / frequency (defaults: 02:00, every 30 min).
- **Move vs copy:** production default is move (`-DeleteSourceAfter`), matching the legacy job consuming the outbox.

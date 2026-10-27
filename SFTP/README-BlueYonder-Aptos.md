# Blue Yonder ↔ Aptos SFTP Transfer — Runbook

Replacement for the legacy DataExchange/JDA SFTP job. Moves files between the
Blue Yonder and Aptos SFTP servers, brokered through **vwpsftp01** (which has
WinSCP installed and network access to both endpoints).

```
Blue Yonder SFTP  <-->  vwpsftp01 (staging, WinSCP)  <-->  Aptos SFTP
```

SFTP cannot stream directly between two remote servers, so vwpsftp01 is the
broker. Each file follows the legacy DataExchange/JDA transfer pattern:
download to a local `.TMP`, rename the remote source to `.RN` (claim it), rename
the local `.TMP` to its final name, upload to a remote `.TMP` on the destination,
then rename that remote `.TMP` to the final name (atomic reveal — the receiving
app never sees a partial file). In production the claimed source (`.RN`) is then
deleted, making it a MOVE.

## Flows

| Flow | Source | Pattern | Destination |
|------|--------|---------|-------------|
| Invoices | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/eurorpatprdv2/outbox` | `STSIMATIN*.go` | Aptos `10.252.16.100:/IN/Merch/Invoices/Company1` |
| ASN | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/eurorpatprdv2/outbox` | `STSIMASN*.go` | Aptos `10.252.16.100:/IN/Merch/EDI ASN` |
| Purchase Orders | Aptos `10.252.16.100:/Out/Merch/PurchaseOrder` | `*` | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/eurorpatprdv2/inbox` |

Invoices and ASN share the same Blue Yonder outbox and are routed to different
Aptos folders by filename pattern. The routing is table-driven in the script
(`$OutboundRoutes`) — add a row there to route another document type from the
same outbox. (Note: the ASN destination folder name contains a space: `EDI ASN`.)

**Transfer pattern (per file, matching the legacy job logs):**
1. `getFile()` — download source to a local `.TMP`
2. `renameRemoteFile()` — rename remote source to `.RN` (claim it)
3. rename local `.TMP` to its final name
4. `sendFile()` — upload to a remote `.TMP` on the destination
5. `renameRemoteFile()` — rename remote `.TMP` to the final name (atomic reveal)
6. `removeRemoteFile()` — delete the claimed source `.RN` **(only when `-DeleteSourceAfter` is passed)**

`-DeleteSourceAfter` is a safety switch: with it, step 6 runs (true MOVE);
without it, delivery still completes but the claimed `.RN` is left on the source.

## Endpoints

| | Blue Yonder | Aptos |
|---|-------------|-------|
| Host | `PRODB2BGW02.jdadelivers.com` | `10.252.16.100` |
| Port | 22 | 22 |
| User | `eurorpatprdv2` | `WSsftpuser` |

> Passwords are never stored in the scripts. They live in DPAPI-encrypted
> credential files created in step 3.

## Files (deploy these to `D:\sftp\` on vwpsftp01)

- `Sync-BlueYonder-Aptos.ps1` — the transfer job
- `New-BlueYonderAptosCreds.ps1` — one-time credential file creator
- `Deploy-BlueYonderAptosJob.sql` — creates the SQL Agent job (chosen scheduler)
- `Register-BlueYonderAptosTask.ps1` — registers a Windows scheduled task (alternative scheduler)

Suggested layout on vwpsftp01:

```
D:\sftp\
  Sync-BlueYonder-Aptos.ps1
  New-BlueYonderAptosCreds.ps1
  Deploy-BlueYonderAptosJob.sql
  Register-BlueYonderAptosTask.ps1
  creds\      <- credential files (step 3)
  staging\    <- transient; files pass through here
  logs\       <- timestamped per-run logs (pruned by the job's retention step)
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
Use the WinSCP .NET assembly's `ScanFingerprint` (no credentials needed).
Run ONE HOST AT A TIME so pasted line breaks can't merge statements — keep each
`New-Object` on its own line (merging them onto one line causes
"A positional parameter cannot be found" errors).

Blue Yonder:
```powershell
Add-Type -Path "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
$opts = New-Object WinSCP.SessionOptions -Property @{ Protocol = [WinSCP.Protocol]::Sftp; HostName = 'PRODB2BGW02.jdadelivers.com'; PortNumber = 22 }
$session = New-Object WinSCP.Session
$session.ScanFingerprint($opts, 'SHA-256')
$session.Dispose()
```

Aptos (only after the step 2 port test passes):
```powershell
$opts = New-Object WinSCP.SessionOptions -Property @{ Protocol = [WinSCP.Protocol]::Sftp; HostName = '10.252.16.100'; PortNumber = 22 }
$session = New-Object WinSCP.Session
$session.ScanFingerprint($opts, 'SHA-256')
$session.Dispose()
```

If you prefer a single pasteable line, separate statements with `;`:
```powershell
Add-Type -Path "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"; $opts = New-Object WinSCP.SessionOptions -Property @{ Protocol=[WinSCP.Protocol]::Sftp; HostName='PRODB2BGW02.jdadelivers.com'; PortNumber=22 }; $session = New-Object WinSCP.Session; $session.ScanFingerprint($opts,'SHA-256'); $session.Dispose()
```

Or capture it from the WinSCP GUI: connect to the host, and on the
"unknown server" dialog click **Copy key fingerprints to clipboard**
(or afterwards via **Session > Server/Protocol Information**).

Put each returned fingerprint into the matching `SshHostKey` field in
`Sync-BlueYonder-Aptos.ps1`. This pins the server identity and prevents
man-in-the-middle connections.

> Note: `/keygen /scanhostkey` is NOT valid — `/keygen` only converts key files.
> Scanning requires TCP reachability, so scan Aptos only after step 2 passes.

### 4. Create encrypted credential files AS THE SERVICE ACCOUNT
DPAPI ties each file to the creating user + machine, so this MUST run as the
service account on vwpsftp01:
Since the SQL Agent service runs as `WSS\vwpsftp01sql`, create the files AS THAT
ACCOUNT on vwpsftp01 (the job step will run as the same account, so DPAPI
decryption works). Use PsExec if `runas` is blocked for the service account:
```powershell
C:\Tools\PSTools\PsExec.exe -accepteula -u WSS\vwpsftp01sql -i powershell.exe
# in the new window:
cd D:\sftp
.\New-BlueYonderAptosCreds.ps1 -OutputFolder 'D:\sftp\creds'
```
Produces `D:\sftp\creds\blueyonder.cred.xml` and `aptos.cred.xml`.
Lock down `D:\sftp\creds` so only the service account and admins can read it.

### 5. Test before scheduling
Run as the service account (`WSS\vwpsftp01sql`):
```powershell
cd D:\sftp
.\Sync-BlueYonder-Aptos.ps1 -WhatIf              # lists what WOULD transfer, moves nothing
.\Sync-BlueYonder-Aptos.ps1                      # deliver; leave claimed source (.RN) in place (safety mode)
.\Sync-BlueYonder-Aptos.ps1 -DeleteSourceAfter   # full MOVE: delete claimed source after verified delivery
```
Check the latest run log (each run writes its own timestamped file,
`D:\sftp\logs\blueyonder-aptos_<yyyyMMdd-HHmmss>.log`) and confirm files landed
on both sides:
```powershell
Get-Content (Get-ChildItem D:\sftp\logs\blueyonder-aptos_*.log | Sort-Object LastWriteTime | Select-Object -Last 1) -Tail 50
```
Run `-DeleteSourceAfter` (the production behaviour) only once you are satisfied
delivery is working. Note: every run claims the source by renaming it to `.RN`;
without `-DeleteSourceAfter` those `.RN` files stay on the source until a run
with the switch cleans them up.

### 6. Schedule it — SQL Agent job (chosen method)
The SQL Server Agent service runs as `WSS\vwpsftp01sql` — the same account that
owns the credential files — so a CmdExec step runs as that account automatically
(no proxy needed), provided the job is owned by a sysadmin login (`sa`).

Deploy the job by running the included `Deploy-BlueYonderAptosJob.sql` on the SQL
instance on vwpsftp01:
```powershell
sqlcmd -S vwpsftp01 -E -i "D:\sftp\Deploy-BlueYonderAptosJob.sql"
```
(or open it in SSMS and execute). The script is re-runnable — it drops and
recreates the job — and creates a two-step job plus an every-15-minutes schedule.

What the script sets up:
- Job owned by `sa` (sysadmin) so the CmdExec steps run as the Agent service
  account `WSS\vwpsftp01sql`. No proxy/SQL credential needed. (If the job must be
  owned by a non-sysadmin, create a CmdExec proxy bound to a `WSS\vwpsftp01sql`
  credential instead.)
- **Step 1 — Run transfer (both flows):** legacy `.TMP`/`.RN` pattern,
  `-DeleteSourceAfter` passed (true MOVE — claimed source deleted after a
  verified delivery). `exit $LASTEXITCODE` plus the script's `exit 1` on failure
  make SQL Agent mark the step FAILED when a transfer errors.
- **Step 2 — Log retention cleanup:** deletes timestamped log files older than
  `@RetentionDays` (default 30) from `D:\sftp\logs`.

Step flow: on Step 1 success the job proceeds to Step 2; on Step 1 failure the
job quits reporting failure (so a transfer error is visible and cleanup is
skipped that run — the next successful run prunes logs). Step 2 never fails the
job, so a cleanup hiccup won't raise a false failure.

To tweak behaviour, edit `Deploy-BlueYonderAptosJob.sql` before running:
- **Retention policy:** change `DECLARE @RetentionDays int = 30;` in Step 2.
- **Test/safety mode:** remove `-DeleteSourceAfter` from the Step 1 `@command` to
  leave claimed `.RN` source files in place (nothing deleted).
- **Schedule cadence:** the active schedule runs every 15 minutes. Change
  `@freq_subday_interval` in the `sp_add_schedule` block (e.g. 30 for every 30
  minutes), or swap in the commented daily-once block at the bottom of the SQL
  file. Note: a 15-minute cadence produces many log files, so consider a shorter
  `@RetentionDays` (e.g. 7).

### Alternative: Windows Task Scheduler
If you prefer Task Scheduler over SQL Agent, use the included script:
```powershell
cd D:\sftp
.\Register-BlueYonderAptosTask.ps1 -ServiceAccount 'WSS\vwpsftp01sql' `
    -ScriptPath 'D:\sftp\Sync-BlueYonder-Aptos.ps1' `
    -StartTime '00:00' -RepeatMinutes 15
```

## Operations

```sql
-- Run the SQL Agent job on demand
EXEC msdb.dbo.sp_start_job @job_name = N'BlueYonder-Aptos SFTP Transfer';
-- Check last run outcome
SELECT j.name, h.run_date, h.run_time, h.run_status, h.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON h.job_id = j.job_id
WHERE j.name = N'BlueYonder-Aptos SFTP Transfer'
ORDER BY h.run_date DESC, h.run_time DESC;
```
Each run writes its OWN timestamped log files (never overwritten), named:
```
D:\sftp\logs\blueyonder-aptos_<yyyyMMdd-HHmmss>.log
D:\sftp\logs\winscp-session.BlueYonder_<yyyyMMdd-HHmmss>.log
D:\sftp\logs\winscp-session.Aptos_<yyyyMMdd-HHmmss>.log
```
Tail the most recent of each (same regardless of scheduler):
```powershell
# Latest script log
Get-Content (Get-ChildItem D:\sftp\logs\blueyonder-aptos_*.log          | Sort-Object LastWriteTime | Select-Object -Last 1) -Tail 50
# Latest WinSCP session logs
Get-Content (Get-ChildItem D:\sftp\logs\winscp-session.BlueYonder_*.log | Sort-Object LastWriteTime | Select-Object -Last 1) -Tail 50
Get-Content (Get-ChildItem D:\sftp\logs\winscp-session.Aptos_*.log      | Sort-Object LastWriteTime | Select-Object -Last 1) -Tail 50
```
Old log files are pruned automatically by the job's Step 2 (retention policy,
default 30 days).

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
- **Rotate the Blue Yonder password** after go-live, since it was shared during setup.
- **Schedule cadence:** currently every 15 minutes. Confirm this frequency is
  desired (and that overlapping runs can't occur — see note below).
- **Transfer behaviour:** production uses the legacy `.TMP`/`.RN` move pattern with
  `-DeleteSourceAfter` (claimed source deleted after a verified delivery). Omitting
  the switch is test/safety mode and leaves `.RN` files on the source.

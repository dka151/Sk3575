# Blue Yonder ↔ Aptos SFTP Transfer — Runbook

Replacement for the legacy DataExchange/JDA SFTP job. Moves files between the
Blue Yonder and Aptos SFTP servers, brokered through **vwpsftp01** (which has
WinSCP installed and network access to both endpoints).

```
Blue Yonder SFTP  <-->  vwpsftp01 (staging, WinSCP)  <-->  Aptos SFTP
```

SFTP cannot stream directly between two remote servers, so vwpsftp01 downloads
each file to a local staging folder, uploads it to the other server, verifies
it, and (optionally) deletes the source copy after a verified delivery.

Every file transfer is audited to **SQL Server** (one row per file plus one row
per step). The audit is a **hard dependency**: if SQL Server is unreachable the
run aborts before any file is moved — there is no file-based fallback.

## Transfer pattern (per file)

Each file follows the legacy DataExchange/JDA pattern so a receiving app never
sees a partial file, and the same file is never delivered twice:

1. **DownloadToLocalTmp** — download source → local `<file>.TMP`
2. **ClaimSourceRN** — rename the remote source to `<file>.RN` (the "claim")
3. **RenameLocalTmpToFinal** — rename local `<file>.TMP` → `<file>`
4. **UploadToRemoteTmp** — upload local file → remote `<file>.TMP`
5. **RenameRemoteTmpToFinal** — rename remote `<file>.TMP` → `<file>` (atomic reveal)
6. **VerifyDestination** — confirm the final file exists on the destination
7. **DeleteSourceRN** — delete `<file>.RN` on the source — **only** with `-DeleteSourceAfter`

> **The claimed source (`.RN`) is KEPT by default and is never renamed back.**
> It is the "already picked up" marker that guarantees a file is not pushed to
> the destination twice. If a failure happens *after* the claim, the file is
> recorded as **Stranded** and must be reviewed and reprocessed manually.

## Flows

Blue Yonder → Aptos is **table-driven** via `$OutboundRoutes` in the script —
add a row to route another filename pattern from the same outbox to its own
Aptos destination.

| Flow | Direction | Source | Pattern | Destination |
|------|-----------|--------|---------|-------------|
| Invoices | BY → Aptos | Blue Yonder `.../outbox` | `STSIMATIN*.go` | Aptos `/IN/Merch/Invoices/Company1` |
| ASN | BY → Aptos | Blue Yonder `.../outbox` | `STSIMASN*.go` | Aptos `/IN/Merch/EDI ASN` |
| Purchase Orders | Aptos → BY | Aptos `/Out/Merch/PurchaseOrder` | `ExportPO-Co1*.xml` | Blue Yonder `.../inbox` |

`-Mode InvoicesOnly` runs **all** Blue Yonder → Aptos routes (invoices *and*
ASN); `-Mode PosOnly` runs the Aptos → Blue Yonder flow; `-Mode Both` (default)
runs everything.

## Endpoints

| | Blue Yonder | Aptos |
|---|-------------|-------|
| Host | `PRODB2BGW02.jdadelivers.com` | `10.252.16.100` |
| Port | 22 | 22 |
| User | `eurorpatprdv2` (CONFIRM spelling vs path `europatprdv2`) | `WSsftpuser` |
| Outbox / PO source | `/home/eurorpatprdv2/outbox` | `/Out/Merch/PurchaseOrder` |
| Inbox / invoice dest | `/home/eurorpatprdv2/inbox` | `/IN/Merch/Invoices/Company1`, `/IN/Merch/EDI ASN` |

> Passwords are never stored in the scripts. They live in DPAPI-encrypted
> credential files created in step 4.

## Files

Deploy the PowerShell to `D:\sftp\` on vwpsftp01; run the SQL on the audit server.

**PowerShell (vwpsftp01):**
- `Sync-BlueYonder-Aptos.ps1` — the transfer job (audits to SQL)
- `New-BlueYonderAptosCreds.ps1` — one-time credential file creator
- `Register-BlueYonderAptosTask.ps1` — registers the scheduled task
- `Move-WinScpLogs.ps1` — one-time migration of old WinSCP logs into `winscp_log\`

**SQL (audit server — database `DBA`):**
- `Create_BlueYonderAptos_TransferAudit.sql` — creates the two audit tables
- `Create_usp_BlueYonderAptos_TransferReport.sql` — HTML email report stored procedure

Suggested layout on vwpsftp01:

```
D:\sftp\
  Sync-BlueYonder-Aptos.ps1
  New-BlueYonderAptosCreds.ps1
  Register-BlueYonderAptosTask.ps1
  Move-WinScpLogs.ps1
  creds\                 <- DPAPI credential files (step 4)
  staging\               <- transient; files pass through here
  logs\                  <- per-run script logs (blueyonder-aptos_<timestamp>.log)
    winscp_log\          <- per-run, per-endpoint WinSCP session logs
```

### Logging

Every run writes its **own timestamped** log files — nothing is overwritten or
appended, so each run is preserved:

- Script log: `D:\sftp\logs\blueyonder-aptos_<yyyyMMdd-HHmmss>.log`
- WinSCP session logs: `D:\sftp\logs\winscp_log\winscp-session.<Endpoint>_<yyyyMMdd-HHmmss>.log`

There is no automatic retention — add a cleanup job to cap how many old logs are
kept (see **Operations → Log retention**).

## SQL Server audit

Two tables in the `DBA` database (created by
`Create_BlueYonderAptos_TransferAudit.sql`):

- **`dbo.BlueYonderAptos_TransferAudit`** — one row per file per attempt.
- **`dbo.BlueYonderAptos_TransferAuditStepDetail`** — one row per step per file.

File status values:

| Status | Meaning |
|--------|---------|
| `InProgress` | Row written, transfer underway. Lingers only if the run crashed mid-file — investigate. |
| `Success` | Delivered and verified on the destination. |
| `Warning` | Delivered, but the `.RN` delete failed (only possible with `-DeleteSourceAfter`). |
| `Failed` | Failed **before** the source was claimed. Source untouched; the next run retries it. |
| `Stranded` | Claimed (`.RN` kept) but delivery did not complete. **Not** retried automatically — review and reprocess manually. Alert on this. |

The script **exits 1** if any file ends `Failed` or `Stranded`, so SQL Agent /
Task Scheduler marks the run as failed.

## One-time setup

### 1. Prerequisites
- WinSCP installed (default: `C:\Program Files (x86)\WinSCP\WinSCPnet.dll`).
  If installed elsewhere, edit `$WinScpDllPath` in `Sync-BlueYonder-Aptos.ps1`.
- A service account to run the task (e.g. `DOMAIN\svc-sftp`) with "Log on as a batch job" right.
- SQL Server reachable from vwpsftp01, with the `DBA` database and the audit
  tables created. The service account needs a SQL login + DB user in `DBA` with
  `INSERT`, `UPDATE`, `SELECT` on both audit tables.

### 2. Create the audit tables
On the audit SQL Server, with `DBA` as the current database:
```sql
-- run Create_BlueYonderAptos_TransferAudit.sql
```
Then grant the service account (example):
```sql
USE DBA;
CREATE USER [DOMAIN\svc-sftp] FOR LOGIN [DOMAIN\svc-sftp];
GRANT INSERT, UPDATE, SELECT ON dbo.BlueYonderAptos_TransferAudit           TO [DOMAIN\svc-sftp];
GRANT INSERT, UPDATE, SELECT ON dbo.BlueYonderAptos_TransferAuditStepDetail TO [DOMAIN\svc-sftp];
```

### 3. Confirm connectivity
```powershell
Test-NetConnection -ComputerName 10.252.16.100              -Port 22
Test-NetConnection -ComputerName PRODB2BGW02.jdadelivers.com -Port 22
```
Both must show `TcpTestSucceeded : True`. If Aptos fails, raise a firewall
request: source = vwpsftp01 IP, destination = `10.252.16.100`, port 22/TCP.

### 4. Capture SSH host key fingerprints, then paste into the script
Use the WinSCP .NET assembly's `ScanFingerprint` (no credentials needed).
Run ONE HOST AT A TIME so pasted line breaks can't merge statements.

Blue Yonder:
```powershell
Add-Type -Path "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
$opts = New-Object WinSCP.SessionOptions -Property @{ Protocol = [WinSCP.Protocol]::Sftp; HostName = 'PRODB2BGW02.jdadelivers.com'; PortNumber = 22 }
$session = New-Object WinSCP.Session
$session.ScanFingerprint($opts, 'SHA-256')
$session.Dispose()
```

Aptos (only after the step 3 port test passes):
```powershell
$opts = New-Object WinSCP.SessionOptions -Property @{ Protocol = [WinSCP.Protocol]::Sftp; HostName = '10.252.16.100'; PortNumber = 22 }
$session = New-Object WinSCP.Session
$session.ScanFingerprint($opts, 'SHA-256')
$session.Dispose()
```

Put each returned fingerprint into the matching `SshHostKey` field in
`Sync-BlueYonder-Aptos.ps1`. This pins the server identity and prevents
man-in-the-middle connections.

> Note: `/keygen /scanhostkey` is NOT valid — `/keygen` only converts key files.
> Scanning requires TCP reachability, so scan Aptos only after step 3 passes.

### 5. Create encrypted credential files AS THE SERVICE ACCOUNT
DPAPI ties each file to the creating user + machine, so this MUST run as the
service account on vwpsftp01:
```powershell
runas /user:DOMAIN\svc-sftp powershell.exe
# in the new window:
cd D:\sftp
.\New-BlueYonderAptosCreds.ps1 -OutputFolder 'D:\sftp\creds'
```
Produces `D:\sftp\creds\blueyonder.cred.xml` and `aptos.cred.xml`.
Lock down `D:\sftp\creds` so only the service account and admins can read it.

### 6. Test before scheduling
Run as the service account. `-WhatIf` still checks the SQL connection (it will
abort if SQL is down) but writes no audit rows and moves no files:
```powershell
cd D:\sftp
.\Sync-BlueYonder-Aptos.ps1 -WhatIf              # lists what WOULD move, moves nothing
.\Sync-BlueYonder-Aptos.ps1                      # real run, delivers; keeps claimed source (.RN)
.\Sync-BlueYonder-Aptos.ps1 -DeleteSourceAfter   # real run, MOVE (deletes source .RN after verified delivery)
```
Check the latest `D:\sftp\logs\blueyonder-aptos_*.log`, confirm files landed on
both sides, and confirm rows appear in `dbo.BlueYonderAptos_TransferAudit`.

> Keeping the `.RN` (default, no `-DeleteSourceAfter`) is the recommended mode:
> it prevents duplicate delivery. Only use `-DeleteSourceAfter` if the source
> folder must be emptied and you accept that behaviour.

### 7. Register the scheduled task (as administrator)
```powershell
cd D:\sftp
.\Register-BlueYonderAptosTask.ps1 -ServiceAccount 'DOMAIN\svc-sftp' `
    -ScriptPath 'D:\sftp\Sync-BlueYonder-Aptos.ps1' `
    -StartTime '02:00' -RepeatMinutes 15
```
Edit the script's `$scriptArgs` to change mode / delete behaviour.

### 8. (If upgrading) migrate old WinSCP logs
If earlier runs wrote WinSCP logs directly into `D:\sftp\logs`, move them into
the new `winscp_log` subfolder once:
```powershell
cd D:\sftp
.\Move-WinScpLogs.ps1 -WhatIf     # preview
.\Move-WinScpLogs.ps1             # move
```

### 9. Email reporting (optional but recommended)
On the audit SQL Server, create the report stored procedure:
```sql
-- run Create_usp_BlueYonderAptos_TransferReport.sql  (in the DBA database)
```
It emails an HTML audit report via Database Mail (profile **`DBAAlert`** by
default) for files whose transfer started in the last N hours.
```sql
-- last 8 hours
EXEC dbo.usp_BlueYonderAptos_SendTransferReport @LookbackHours = 8,  @Recipients = N'dba-team@yourco.com';
-- last 24 hours, preview only (prints HTML, sends nothing)
EXEC dbo.usp_BlueYonderAptos_SendTransferReport @LookbackHours = 24, @Recipients = N'dba-team@yourco.com', @Debug = 1;
```
The report lookback is measured against **`TransferStartUtc`** (when each
transfer began). Common schedules: one SQL Agent job per window (8 / 12 / 24h).
Requirements: Database Mail configured, the `DBAAlert` profile accessible to the
job account, and that account in the msdb `DatabaseMailUserRole`.

## Operations

```powershell
# Inspect the scheduled task
Get-ScheduledTask -TaskName 'BlueYonder-Aptos SFTP Transfer' | Get-ScheduledTaskInfo
# Run on demand
Start-ScheduledTask -TaskName 'BlueYonder-Aptos SFTP Transfer'
# Latest logs (per-run timestamped files)
Get-ChildItem D:\sftp\logs\blueyonder-aptos_*.log        | Sort LastWriteTime | Select -Last 1 | Get-Content -Tail 50
Get-ChildItem D:\sftp\logs\winscp_log\winscp-session.*   | Sort LastWriteTime | Select -Last 1 | Get-Content -Tail 50
```

### Run modes
```powershell
.\Sync-BlueYonder-Aptos.ps1 -Mode InvoicesOnly    # all Blue Yonder -> Aptos routes (invoices + ASN)
.\Sync-BlueYonder-Aptos.ps1 -Mode PosOnly         # Aptos -> Blue Yonder only
.\Sync-BlueYonder-Aptos.ps1 -Mode Both            # default
```

### Audit / reporting queries
```sql
-- recent files
SELECT TOP 100 TransferStartUtc, Direction, FileName, Status, DurationMs, ErrorMessage
FROM dbo.BlueYonderAptos_TransferAudit ORDER BY TransferStartUtc DESC;

-- anything needing attention
SELECT * FROM dbo.BlueYonderAptos_TransferAudit
WHERE Status IN ('Failed','Stranded','InProgress') ORDER BY TransferStartUtc DESC;

-- full step journey for one file
SELECT s.StepNo, s.StepName, s.Status, s.Host, s.FromPath, s.ToPath, s.DurationMs, s.ErrorMessage
FROM dbo.BlueYonderAptos_TransferAuditStepDetail s
JOIN dbo.BlueYonderAptos_TransferAudit a ON a.AuditId = s.AuditId
WHERE a.FileName = N'STSIMATIN12345.go' ORDER BY s.StepNo;
```

### Log retention
No retention is built in. Schedule a cleanup (e.g. keep 7 days). Example
SQL Agent CmdExec step — note the two folders are listed explicitly:
```bat
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ret=7; $cut=(Get-Date).AddDays(-$ret); $dirs=@('D:\sftp\logs','D:\sftp\logs\winscp_log'); $patterns=@('blueyonder-aptos_*.log','winscp-session.*_*.log'); foreach($d in $dirs){ foreach($p in $patterns){ Get-ChildItem -Path $d -Filter $p -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object { Write-Host ('Deleting ' + $_.FullName); Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue } } }; exit 0"
```

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Run aborts immediately, "Audit database unavailable" | SQL Server down/unreachable, or the audit tables/permissions are missing. By design no files move until the audit DB is reachable. |
| File shows `Stranded` | Delivery failed after the source was claimed. The `.RN` is kept on the source. Check the destination for `<file>` / `<file>.TMP`, then reprocess manually. |
| File shows `Failed` | Failed before the claim; source untouched. The next run retries it automatically. |
| Rows stuck at `InProgress` | Run crashed mid-file (or SQL went down mid-file). Confirm the file's real state on both servers before acting. |
| `could not be decrypted` on a cred file | Files created under a different account/machine. Re-run step 5 as the service account on vwpsftp01. |
| `SSH host key ... not set` | Step 4 not done; paste fingerprints into the script. |
| `TcpTestSucceeded : False` to Aptos | Firewall/routing; raise a request for vwpsftp01 -> 10.252.16.100:22. |
| Host key mismatch at connect | Server key changed or wrong fingerprint pinned. Re-scan (step 4) and confirm with the server owner. |
| No files transferred, "No files matching" | Normal for an empty outbox. Otherwise confirm the pattern and the remote paths. |
| Report email not received | Database Mail not configured, `DBAAlert` profile not accessible to the job account, or account not in msdb `DatabaseMailUserRole`. |

## Outstanding items to confirm
- **Username spelling:** `eurorpatprdv2` (given) vs `europatprdv2` (in some paths). One likely has a typo.
- **Rotate the Blue Yonder password** after go-live, since it was shared during setup.
- **Schedule cadence:** confirm run time / frequency (example: 02:00, every 15 min).
- **Keep vs delete source:** default keeps the claimed `.RN` (prevents duplicates). Use `-DeleteSourceAfter` only if the source must be emptied.
- **Audit server / database:** defaults are the local machine and `DBA`. Override with `-SqlServer` / `-SqlDatabase` if different.
- **Report time zone:** `@DisplayTimeZone` defaults to `GMT Standard Time`; set to your locale.

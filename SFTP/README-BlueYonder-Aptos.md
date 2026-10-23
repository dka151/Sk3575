# Blue Yonder ↔ Aptos SFTP Transfer — Runbook

Replacement for the legacy DataExchange/JDA SFTP job. Moves files between the
Blue Yonder and Aptos SFTP servers, brokered through **vwpsftp01** (which has
WinSCP installed and network access to both endpoints).

```
Blue Yonder SFTP  <-->  vwpsftp01 (staging, WinSCP)  <-->  Aptos SFTP
```

SFTP cannot stream directly between two remote servers, so vwpsftp01 downloads
each file to a local staging folder, uploads it to the other server, verifies
it, and then (in production) **archives** the source copy by moving it into an
archive folder on the same source server — the source file is preserved, not
deleted.

## Flows

| Flow | Source | Pattern | Destination | Source archive |
|------|--------|---------|-------------|----------------|
| Invoices | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/eurorpatprdv2/outbox` | `STSIMATIN*.go` | Aptos `10.252.16.100:/Transfer/IN/Merch/Invoices/Company1` | `/home/eurorpatprdv2/outbox/archive` (TODO: confirm) |
| Purchase Orders | Aptos `10.252.16.100:/Transfer/Out/Merch/PurchaseOrder` | `*` | Blue Yonder `PRODB2BGW02.jdadelivers.com:/home/eurorpatprdv2/inbox` | `/Transfer/Out/Merch/PurchaseOrder/archive` (TODO: confirm) |

After a verified upload, each source file is moved into its "Source archive"
folder on the same server. Archive paths are placeholders in the script
(`ArchivePath` / `DestArchivePath` under each endpoint) pending confirmation from
the application team.

**Destination archiving (optional, OFF by default).** Passing `-ArchiveDestination`
also places a *copy* of each delivered file into the destination server's
`DestArchivePath` — the delivered file stays in its normal folder for the
receiving app, and a second copy lands in the archive folder. Defaults:

| Destination | DestArchivePath (TODO: confirm) |
|-------------|---------------------------------|
| Aptos `/Transfer/IN/Merch/Invoices/Company1` | `/Transfer/IN/Merch/Invoices/Company1/archive` |
| Blue Yonder `/home/eurorpatprdv2/inbox` | `/home/eurorpatprdv2/inbox/archive` |

Source archiving MOVES the file; destination archiving COPIES it.

## Endpoints

| | Blue Yonder | Aptos |
|---|-------------|-------|
| Host | `PRODB2BGW02.jdadelivers.com` | `10.252.16.100` |
| Port | 22 | 22 |
| User | `eurorpatprdv2` | `WSsftpuser` |

> Passwords are never stored in the scripts. They live in DPAPI-encrypted
> credential files created in step 3.

## Files (deploy these to `C:\sftp\` on vwpsftp01)

- `Sync-BlueYonder-Aptos.ps1` — the transfer job
- `New-BlueYonderAptosCreds.ps1` — one-time credential file creator
- `Deploy-BlueYonderAptosJob.sql` — creates the SQL Agent job (chosen scheduler)
- `Register-BlueYonderAptosTask.ps1` — registers a Windows scheduled task (alternative scheduler)

Suggested layout on vwpsftp01:

```
C:\sftp\
  Sync-BlueYonder-Aptos.ps1
  New-BlueYonderAptosCreds.ps1
  Deploy-BlueYonderAptosJob.sql
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
cd C:\sftp
.\New-BlueYonderAptosCreds.ps1 -OutputFolder 'C:\sftp\creds'
```
Produces `C:\sftp\creds\blueyonder.cred.xml` and `aptos.cred.xml`.
Lock down `C:\sftp\creds` so only the service account and admins can read it.

### 5. Test before scheduling
Run as the service account (`WSS\vwpsftp01sql`):
```powershell
cd C:\sftp
.\Sync-BlueYonder-Aptos.ps1 -WhatIf                        # lists what WOULD transfer, moves nothing
.\Sync-BlueYonder-Aptos.ps1 -ArchiveSource:$false          # real run, COPY only (source left in place)
.\Sync-BlueYonder-Aptos.ps1                                # real run, COPY + ARCHIVE source (production default)
.\Sync-BlueYonder-Aptos.ps1 -ArchiveDestination            # also keep a COPY in the destination archive folder
```
Check `C:\sftp\logs\blueyonder-aptos.log` and confirm files landed on both sides.
Run the default (copy + archive) only once you are satisfied the copy-only runs
land correctly. Source archiving MOVES the source file into the source server's
archive folder; `-ArchiveDestination` additionally COPIES the delivered file into
the destination server's archive folder (off unless the app team requires it).

### 6. Schedule it — SQL Agent job (chosen method)
The SQL Server Agent service runs as `WSS\vwpsftp01sql` — the same account that
owns the credential files — so a CmdExec step runs as that account automatically
(no proxy needed), provided the job is owned by a sysadmin login (`sa`).

Deploy the job by running the included `Deploy-BlueYonderAptosJob.sql` on the SQL
instance on vwpsftp01:
```powershell
sqlcmd -S vwpsftp01 -E -i "C:\sftp\Deploy-BlueYonderAptosJob.sql"
```
(or open it in SSMS and execute). The script is re-runnable — it drops and
recreates the job — and creates a CmdExec step plus a daily 02:00 schedule.

What the script sets up:
- Job owned by `sa` (sysadmin) so the CmdExec step runs as the Agent service
  account `WSS\vwpsftp01sql`. No proxy/SQL credential needed. (If the job must be
  owned by a non-sysadmin, create a CmdExec proxy bound to a `WSS\vwpsftp01sql`
  credential instead.)
- Production behaviour: both flows, copy + archive source.
- `exit $LASTEXITCODE` plus the script's `exit 1` on failure make SQL Agent mark
  the step FAILED when a transfer errors (otherwise it could show success).

To tweak behaviour, edit `Deploy-BlueYonderAptosJob.sql` before running:
- **Destination archiving:** add `-ArchiveDestination` to the step `@command`.
- **Every-30-min schedule:** swap in the alternative `sp_add_schedule` block
  included (commented) at the bottom of the SQL file.

### Alternative: Windows Task Scheduler
If you prefer Task Scheduler over SQL Agent, use the included script:
```powershell
cd C:\sftp
.\Register-BlueYonderAptosTask.ps1 -ServiceAccount 'WSS\vwpsftp01sql' `
    -ScriptPath 'C:\sftp\Sync-BlueYonder-Aptos.ps1' `
    -StartTime '02:00' -RepeatMinutes 30
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
```powershell
# Logs (same regardless of scheduler)
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
- **Archive paths:** the `ArchivePath` and `DestArchivePath` values in the script
  are placeholders. Confirm the exact absolute archive paths on each server with
  the application team, and whether BOTH source and destination files need
  archiving or just the source. The script archives the SOURCE by default and can
  also archive the DESTINATION via `-ArchiveDestination` (off by default) — enable
  it and confirm the `DestArchivePath` values if they require destination copies.
- **Rotate the Blue Yonder password** after go-live, since it was shared during setup.
- **Schedule cadence:** confirm desired run time / frequency (default: daily 02:00).
- **Archiving behaviour:** production default is copy + archive source
  (`-ArchiveSource` defaults to `$true`). Source files are moved to the archive
  folder after a verified upload, not deleted.

# Runbook: Aptos Style Dims Export (PROD)

Exports style dimensions from SQL Server to a CSV and uploads it to the Aptos SFTP server.

| Item | Value |
|---|---|
| SQL Server | `AZUSW1APSQL03` |
| Database / proc | `DBA` / `dbo.usp_Aptos_StyleDims_Export` (`@WhId = 282999`) |
| Scripts | `Export-AptosStyleDims.ps1`, `New-AptosSftpCredential.ps1` |
| Run as | `WSS\AzSQLService` (SQL Agent service account) |
| SQL Agent job | `Aptos - Style Dims Export (PROD)` (CmdExec step) |
| SFTP target | `/Transfer/IN/MERCH/Style` |
| Working folder | `D:\Jobs\AptosStyleDims` |
| Credential file | `D:\Jobs\AptosStyleDims\Secrets\aptos_sftp.cred` |

## 1. How it works

1. Runs `dbo.usp_Aptos_StyleDims_Export` on `AZUSW1APSQL03` (Windows authentication).
2. Builds `Aptos_styledims_<yyyyMMdd_HHmmss>.csv` in `Work\`.
   - Header: `Style,Action,EntityAction,Code,Weight,Height,Width,Depth`
   - CRLF line endings, UTF-8 without BOM.
   - Numbers use `.` and drop trailing zeros (`8.00` becomes `8`).
3. Uploads through WinSCP as `<name>.csv.tmp`, then renames to `<name>.csv`, so Aptos never sees a partial file.
4. Moves the CSV to `Archive\`. Files in `Archive\` and `Logs\` older than 30 days are deleted.

If the proc returns zero rows, no file is created, a WARN is logged and the job succeeds (exit 0).

Exit codes: `0` success or no rows, `1` failure.

### Delta logic

The file contains only new codes and codes whose Weight, Height, Width or Depth changed since the last successful delivery. `Style`, `Action` (`update`) and `EntityAction` (blank) are fixed values.

- State is kept in `DBA.dbo.Aptos_StyleDims_Sent` (last values sent per code).
- `usp_Aptos_StyleDims_Export` returns the delta and parks it in `dbo.Aptos_StyleDims_Pending` with a `@BatchId`.
- After the SFTP upload succeeds, the script calls `usp_Aptos_StyleDims_Commit @BatchId`, which moves the pending rows into `Sent`. If the upload fails, nothing is committed and the next run sends the same changes again.
- The first run (empty `Sent` table) sends every code.
- No changes means no file and a successful job.
- Codes are not deleted in Aptos. A code that drops out of the source, or whose four values all become 0, is simply not sent.
- To re-send everything: run the script with `-FullExport $true`, or `TRUNCATE TABLE DBA.dbo.Aptos_StyleDims_Sent`.
- Deploy `usp_Aptos_StyleDims_Export_Delta.sql` on `AZUSW1APSQL03` (database `DBA`) before the first run.

## 2. Prerequisites

- WinSCP installed at `C:\Program Files (x86)\WinSCP\winscp.com`.
- `WSS\AzSQLService` has:
  - Modify rights on `D:\Jobs\AptosStyleDims`.
  - Read and execute rights on the WinSCP folder.
  - `EXECUTE` on `dbo.usp_Aptos_StyleDims_Export` in `DBA`.
- Aptos SFTP host name, port, user and password.
- Server host key pinned in the script (`-HostKey`):
  `ssh-rsa 2048 lp0au9aqsK5yF2hlSef33/6PWNOKEzxxSUuNlN46OJk`

## 3. One-time setup

1. Copy both `.ps1` files to `D:\Jobs\AptosStyleDims\`.
2. Confirm `-SftpHost` is `10.252.17.100` (the script default).
3. Create the credential file as `WSS\AzSQLService` (admin command prompt):
   ```
   runas /user:WSS\AzSQLService "powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\Jobs\AptosStyleDims\New-AptosSftpCredential.ps1"
   ```
   Enter the Aptos SFTP user and password when prompted.
   - The file is DPAPI-encrypted. Only the same account on the same server can decrypt it.
   - The script restricts the `Secrets` folder to that account and Administrators.
   - If `runas` is refused (deny log on locally), use `psexec -i -u WSS\AzSQLService powershell.exe`, or ask for the right to be lifted temporarily.
   - Do not put the SFTP password in a SQL Agent step. It would be stored in plain text.
4. Create the SQL Agent job `Aptos - Style Dims Export (PROD)`:
   - Owner and step run-as: `WSS\AzSQLService` (or a proxy using it).
   - Step type: Operating system (CmdExec).
   - Command:
     ```
     powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Jobs\AptosStyleDims\Export-AptosStyleDims.ps1"
     ```
   - Add the schedule and a failure notification.

## 4. First run checklist

Run once manually as `WSS\AzSQLService`, then start the job.

- [ ] Log shows `Rows returned: N`.
- [ ] Log shows `File delivered: /Transfer/IN/MERCH/Style/Aptos_styledims_....csv`.
- [ ] The file is in `Archive\` and `Work\` is empty.
- [ ] The file is visible in the SFTP folder, with no leftover `.tmp`.
- [ ] Job history shows success.

## 5. Parameters

| Parameter | Default | Notes |
|---|---|---|
| `-SqlServer` | `AZUSW1APSQL03` | |
| `-Database` | `DBA` | |
| `-WhId` | `282999` | Passed to the proc |
| `-SftpHost` | `10.252.17.100` | |
| `-SftpPort` | `22` | |
| `-RemoteDir` | `/Transfer/IN/MERCH/Style` | |
| `-HostKey` | pinned SHA-256 | `''` disables pinning |
| `-CredFile` | `...\Secrets\aptos_sftp.cred` | |
| `-WinScpPath` | `C:\Program Files (x86)\WinSCP\winscp.com` | |
| `-BaseDir` | `D:\Jobs\AptosStyleDims` | |
| `-FilePrefix` | `Aptos_styledims` | |
| `-DateFormat` | `yyyyMMdd_HHmmss` | `yyyyMMdd` for one file per day |
| `-SkipEmptyFile` | `$true` | |
| `-QueryTimeoutSec` | `1800` | |
| `-UploadRetries` | `3` | 30 s between attempts |
| `-RetainDays` | `30` | Archive and log retention |

## 6. Logs and where to look

| Log | Path |
|---|---|
| Script log | `D:\Jobs\AptosStyleDims\Logs\Aptos_styledims_<yyyyMMdd>.log` |
| WinSCP log | `D:\Jobs\AptosStyleDims\Logs\winscp_<yyyyMMdd>.log` |
| Job history | SQL Agent > job > View History (step output) |

The WinSCP log masks the password. The temporary WinSCP script file is deleted after every upload, including failures.

## 7. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `Credential file not found` | Setup step 3 not done | Create the file as `WSS\AzSQLService` |
| Cannot decrypt / `Import-Clixml` error | File created by another account or server | Re-run `New-AptosSftpCredential.ps1` as `WSS\AzSQLService` on this server |
| `WinSCP not found` | Different install path | Pass `-WinScpPath` |
| WinSCP exit code 1 with host key error | Aptos rotated its key | Confirm the new fingerprint with Aptos, update `-HostKey` |
| WinSCP exit code 1, authentication failed | Password changed or expired | Re-run the credential script |
| Permission denied on put/mv | SFTP user lacks write access to the folder | Ask Aptos |
| Login failed / proc permission denied | Service account lacks SQL rights | Grant `EXECUTE` on the proc |
| Timeout from SQL | Proc is slow | Increase `-QueryTimeoutSec` |
| `Rows returned: 0`, no file | Proc returned nothing | Check source data; expected if no changes |
| Leftover `.tmp` on SFTP | Upload interrupted | Delete it; the next run uploads a new file |

## 8. Operations

- **Re-run a failed day:** run the job again. It creates a new timestamped file; tell Aptos if the earlier file was partially processed.
- **Rotate the SFTP password:** run `New-AptosSftpCredential.ps1` again as `WSS\AzSQLService`. No script change is needed.
- **Service account change or server move:** the credential file stops working. Recreate it for the new account.
- **Aptos host key rotation:** update `-HostKey` after verifying the new fingerprint with Aptos.
- **Disable temporarily:** disable the SQL Agent job.

## 9. Security notes

- Credentials are DPAPI-encrypted and the folder ACL is restricted.
- The password never appears on a command line or in logs.
- The host key is pinned. A changed key causes the job to fail instead of connecting.
- Give the SFTP user write access only to `/Transfer/IN/MERCH/Style`.

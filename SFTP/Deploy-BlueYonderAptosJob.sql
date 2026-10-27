/*
================================================================================
  Deploy-BlueYonderAptosJob.sql

  Creates the SQL Server Agent job that runs the Blue Yonder <-> Aptos SFTP
  transfer (Sync-BlueYonder-Aptos.ps1) on vwpsftp01.

  PREREQUISITES
    - SQL Server Agent service runs as WSS\vwpsftp01sql (the same account that
      created the DPAPI credential files). The CmdExec step therefore runs as
      that account automatically -- NO proxy required -- because this job is
      owned by a sysadmin login (sa).
    - Sync-BlueYonder-Aptos.ps1 deployed to D:\sftp on vwpsftp01.
    - Credential files created under D:\sftp\creds by WSS\vwpsftp01sql.
    - SSH host key fingerprints pasted into the script.

  BEHAVIOUR
    - Runs both flows (invoices + purchase orders).
    - Uses the legacy DataExchange/JDA transfer pattern: download to local .TMP,
      rename remote source to .RN (claim), rename local .TMP to final, upload to
      remote .TMP, rename remote .TMP to final (atomic reveal).
    - Production: -DeleteSourceAfter is passed so the claimed source (.RN) is
      deleted after a verified delivery -- a true MOVE, matching the legacy job.
      Remove -DeleteSourceAfter to leave the claimed source in place (test/safety
      mode; .RN files will accumulate until a run with the switch cleans them up).
    - 'exit $LASTEXITCODE' + the script's 'exit 1' on failure make the step
      report FAILURE to SQL Agent when a transfer errors.

  STEPS
    1. Run transfer (both flows)  -- the SFTP move.
    2. Log retention cleanup      -- deletes timestamped log files older than
                                     @RetentionDays from D:\sftp\logs.

  SCHEDULE
    - Every 15 minutes, all day, every day. Adjust @freq_subday_interval below
      for a different cadence (or see the commented daily-once block at the end).

  LOG RETENTION
    - Each run writes its own timestamped log files (never overwritten). Step 2
      prunes files older than @RetentionDays (default 30) so they don't grow
      without bound. Change @RetentionDays below to adjust the policy.

  Run this script on the SQL instance on vwpsftp01 (sqlcmd or SSMS).
  Re-runnable: it drops the job first if it already exists.
================================================================================
*/

USE [msdb];
GO

DECLARE @JobName sysname = N'BlueYonder-Aptos SFTP Transfer';

/* ---- Drop existing job (idempotent redeploy) ---- */
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
    PRINT 'Existing job dropped: ' + @JobName;
END
GO

/* ---- Create the job (owned by sa => sysadmin => CmdExec runs as Agent service account) ---- */
EXEC msdb.dbo.sp_add_job
    @job_name         = N'BlueYonder-Aptos SFTP Transfer',
    @enabled          = 1,
    @owner_login_name = N'sa',
    @description      = N'Transfers invoices Blue Yonder->Aptos and purchase orders Aptos->Blue Yonder via vwpsftp01 (WinSCP). Legacy .TMP/.RN move pattern; deletes source after verified delivery. Step 2 prunes log files older than the retention period. Replaces legacy DataExchange/JDA job.';
GO

/* ---- Step 1: run the PowerShell transfer via CmdExec ---- */
/* NOTE: -DeleteSourceAfter makes this a true MOVE (source consumed after a
         verified delivery). Remove it to run in test/safety mode (claimed .RN
         source left in place, nothing deleted).
   On success -> go to Step 2 (log cleanup). On failure -> quit reporting
   failure (so a transfer error is visible; cleanup is skipped that run and the
   next successful run prunes logs).                                            */
EXEC msdb.dbo.sp_add_jobstep
    @job_name        = N'BlueYonder-Aptos SFTP Transfer',
    @step_name       = N'Run transfer (both flows)',
    @step_id         = 1,
    @subsystem       = N'CmdExec',
    @command         = N'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& ''D:\sftp\Sync-BlueYonder-Aptos.ps1'' -Mode Both -DeleteSourceAfter; exit $LASTEXITCODE"',
    @on_success_action = 3,   -- 3 = Go to the next step
    @on_fail_action    = 2,   -- 2 = Quit the job reporting failure
    @retry_attempts    = 0,
    @retry_interval    = 0;
GO

/* ---- Step 2: log retention cleanup ----
   Deletes timestamped log files older than @RetentionDays from D:\sftp\logs.
   Matches the files the transfer script creates:
     blueyonder-aptos_*.log
     winscp-session.*_*.log
   To change the retention period, edit the -RetentionDays value below.         */
DECLARE @RetentionDays int = 30;   -- <<< retention policy: keep logs this many days

DECLARE @CleanupCmd nvarchar(2000) = N'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command '
    + N'"$ret=' + CAST(@RetentionDays AS nvarchar(10)) + N'; '
    + N'$cut=(Get-Date).AddDays(-$ret); '
    + N'$logs=''D:\sftp\logs''; '
    + N'$patterns=@(''blueyonder-aptos_*.log'',''winscp-session.*_*.log''); '
    + N'foreach($p in $patterns){ '
    + N'Get-ChildItem -Path $logs -Filter $p -File -ErrorAction SilentlyContinue '
    + N'| Where-Object { $_.LastWriteTime -lt $cut } '
    + N'| ForEach-Object { Write-Host (''Deleting '' + $_.FullName); Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue } }; '
    + N'exit 0"';

EXEC msdb.dbo.sp_add_jobstep
    @job_name        = N'BlueYonder-Aptos SFTP Transfer',
    @step_name       = N'Log retention cleanup',
    @step_id         = 2,
    @subsystem       = N'CmdExec',
    @command         = @CleanupCmd,
    @on_success_action = 1,   -- 1 = Quit the job reporting success
    @on_fail_action    = 1,   -- 1 = Quit reporting success (cleanup failure must not fail the job)
    @retry_attempts    = 0,
    @retry_interval    = 0;
GO

/* ---- Schedule: every 15 minutes, all day, every day ---- */
EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'SFTP_BlueYonderAptos_Every15',
    @enabled              = 1,
    @freq_type            = 4,          -- 4 = daily
    @freq_interval        = 1,          -- every 1 day
    @freq_subday_type     = 4,          -- 4 = minutes
    @freq_subday_interval = 15,         -- every 15 minutes
    @active_start_time    = 000000,     -- from 00:00:00
    @active_end_time      = 235959;     -- to 23:59:59  (HHMMSS)
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'BlueYonder-Aptos SFTP Transfer',
    @schedule_name = N'SFTP_BlueYonderAptos_Every15';
GO

/* ---- Target the local server ---- */
EXEC msdb.dbo.sp_add_jobserver
    @job_name   = N'BlueYonder-Aptos SFTP Transfer',
    @server_name = N'(LOCAL)';
GO

PRINT 'Job deployed: BlueYonder-Aptos SFTP Transfer';
GO

/*
--------------------------------------------------------------------------------
  The active schedule above runs every 15 minutes. To change the cadence, edit
  @freq_subday_interval (e.g. 30 for every 30 minutes).

  OPTIONAL: run once daily at 02:00 instead. Replace the sp_add_schedule call
  above with:

  EXEC msdb.dbo.sp_add_schedule
      @schedule_name     = N'SFTP_BlueYonderAptos_Daily_0200',
      @enabled           = 1,
      @freq_type         = 4,        -- daily
      @freq_interval     = 1,
      @freq_subday_type  = 1,        -- 1 = at the specified time (once)
      @active_start_time = 020000;   -- 02:00:00
--------------------------------------------------------------------------------

  USEFUL OPERATIONS

  -- Run on demand:
  EXEC msdb.dbo.sp_start_job @job_name = N'BlueYonder-Aptos SFTP Transfer';

  -- Recent run history:
  SELECT TOP 20 j.name, h.run_date, h.run_time, h.run_status, h.message
  FROM msdb.dbo.sysjobs j
  JOIN msdb.dbo.sysjobhistory h ON h.job_id = j.job_id
  WHERE j.name = N'BlueYonder-Aptos SFTP Transfer'
  ORDER BY h.run_date DESC, h.run_time DESC;
*/

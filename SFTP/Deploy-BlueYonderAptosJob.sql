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
    - Sync-BlueYonder-Aptos.ps1 deployed to C:\sftp on vwpsftp01.
    - Credential files created under C:\sftp\creds by WSS\vwpsftp01sql.
    - SSH host key fingerprints pasted into the script.

  BEHAVIOUR
    - Runs both flows (invoices + purchase orders).
    - Production default: copy + archive source (ArchiveSource defaults to $true
      in the script). To also archive on the destination, append
      -ArchiveDestination to the @command below.
    - 'exit $LASTEXITCODE' + the script's 'exit 1' on failure make the step
      report FAILURE to SQL Agent when a transfer errors.

  SCHEDULE
    - Daily at 02:00. Adjust @active_start_time / add a sub-day repetition if a
      more frequent cadence is required.

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
    @description      = N'Transfers invoices Blue Yonder->Aptos and purchase orders Aptos->Blue Yonder via vwpsftp01 (WinSCP). Copy + archive source. Replaces legacy DataExchange/JDA job.';
GO

/* ---- Job step: run the PowerShell transfer via CmdExec ---- */
/* NOTE: to also archive delivered files on the destination, add
         -ArchiveDestination before the '; exit $LASTEXITCODE' part.            */
EXEC msdb.dbo.sp_add_jobstep
    @job_name        = N'BlueYonder-Aptos SFTP Transfer',
    @step_name       = N'Run transfer (both flows)',
    @step_id         = 1,
    @subsystem       = N'CmdExec',
    @command         = N'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& ''C:\sftp\Sync-BlueYonder-Aptos.ps1'' -Mode Both; exit $LASTEXITCODE"',
    @on_success_action = 1,   -- 1 = Quit the job reporting success
    @on_fail_action    = 2,   -- 2 = Quit the job reporting failure
    @retry_attempts    = 0,
    @retry_interval    = 0;
GO

/* ---- Schedule: daily at 02:00 ---- */
EXEC msdb.dbo.sp_add_schedule
    @schedule_name     = N'SFTP_BlueYonderAptos_Daily_0200',
    @enabled           = 1,
    @freq_type         = 4,          -- 4 = daily
    @freq_interval     = 1,          -- every 1 day
    @freq_subday_type  = 1,          -- 1 = at the specified time (once)
    @active_start_time = 020000;     -- 02:00:00  (HHMMSS)
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'BlueYonder-Aptos SFTP Transfer',
    @schedule_name = N'SFTP_BlueYonderAptos_Daily_0200';
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
  OPTIONAL: run every 30 minutes across the day instead of once at 02:00.
  Replace the sp_add_schedule call above with:

  EXEC msdb.dbo.sp_add_schedule
      @schedule_name        = N'SFTP_BlueYonderAptos_Every30',
      @enabled              = 1,
      @freq_type            = 4,        -- daily
      @freq_interval        = 1,
      @freq_subday_type     = 4,        -- 4 = minutes
      @freq_subday_interval = 30,       -- every 30 minutes
      @active_start_time    = 000000,   -- from 00:00
      @active_end_time      = 235959;   -- to 23:59
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

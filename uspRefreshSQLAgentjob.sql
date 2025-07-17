USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[uspRefreshDatabaseVLF]    Script Date: 7/13/2025 2:01:28 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[uspRefreshSQLAgentjob]
AS

SET NOCOUNT ON;

DECLARE @dbName VARCHAR(255),
        @tblName VARCHAR(255),
        @tName VARCHAR(255),
        @query NVARCHAR(MAX),
        @OPENQUERY NVARCHAR(4000),
        @sid NVARCHAR(10),
        @sname NVARCHAR(100),
        @Date DATETIME = CURRENT_TIMESTAMP;



DECLARE @servers TABLE
(
    servername sysname NULL,
    serverid INT NULL
);

INSERT @servers
(
    [serverid],
    [servername]
)
SELECT 
	   [ServerID],
       [ServerName]
FROM [dbo].[tServer]
WHERE [IsLinked] = 1
      AND [Active] = 1
	  AND [IsSQLServer] = 1

SET @query = N'';

WHILE 1 = 1
BEGIN
    DECLARE @server sysname,
            @serverid INT;

    SELECT TOP (1)
           @server = [servername],
           @serverid = [serverid]
    FROM @servers
    ORDER BY serverid;

    IF @@rowcount = 0
        BREAK;

    SET @query
        = @query
          + N'INSERT INTO [dbo].[tAgentJobSummary]
           ([CaptureDate]
           ,[ServerName]
           ,[JobName]
           ,[ScheduleName]
           ,[LastStartTime]
           ,[RunDurationHHMMSS]
           ,[LastCompletionTime]
           ,[JobStartTime]
           ,[JobEndTime]
           ,[JobFrequency]
           ,[JobFrequencyType]
           ,[JobFrequencyInterval]
           ,[Recurrence]
           ,[LastRunStatus])'       + N'EXEC ' + QUOTENAME(@server) + N'..sys.sp_executesql N' + N''''
          + N'SET NOCOUNT ON;
DECLARE @description sysname;
SELECT  distinct @description = hars.role_desc
FROM    sys.databases d
JOIN    sys.dm_hadr_availability_replica_states hars ON d.replica_id = hars.replica_id
WHERE hars.role_desc=''''PRIMARY'''';
IF ISNULL(@description, ''''PRIMARY'''') = ''''PRIMARY''''
BEGIN
  SELECT  
        getdate() as CaptureDate,
        @@Servername as [ServerName],
        [J].[name] AS [JobName],
        ISNULL([S].[name], ''''Not scheduled'''') AS [ScheduleName], 
		CONVERT(DATETIME, RTRIM([JA].last_executed_step_date)) as [LastStartTime],
		RunDurationHHMMSS = Format(JH.run_duration, ''''00:00:00''''),
        [LastCompletionTime] = dateadd(second,substring(cast(100000000 + JH.run_duration AS NVARCHAR), 2, 4) * 60*60 -- Hours
        + substring(cast(100000000 + JH.run_duration AS NVARCHAR), 6, 2) * 60 -- Minutes
        + substring(cast(100000000 + JH.run_duration AS NVARCHAR), 8, 2), CONVERT(DATETIME, RTRIM([JA].last_executed_step_date))),  -- Seconds,
		Cast(FORMAT([S].[active_start_time], ''''00:00:00'''') as TIME) AS [JobStartTime],
		CAST(FORMAT([S].[active_end_time], ''''00:00:00'''') as TIME) AS [JobEndTime],
        CASE 
            WHEN [S].[freq_type] = 1 THEN ''''Once'''' 
            WHEN [S].[freq_type] = 4 THEN ''''Daily'''' 
            WHEN [S].[freq_type] = 8 THEN ''''Weekly'''' 
            WHEN [S].[freq_type] = 16 THEN ''''Monthly'''' 
            WHEN [S].[freq_type] = 32 THEN ''''Monthly every '''' + CONVERT(varchar, [S].[freq_interval]) + '''' months'''' 
            WHEN [S].[freq_type] = 64 THEN ''''When agent starts''''
            WHEN [S].[freq_type] = 128 THEN ''''Run when Idle'''' 
            WHEN [S].[freq_type] IS NULL THEN ''''Not scheduled''''
            ELSE ''''Unknown'''' 
        END AS [JobFrequency], 
        CASE 
            WHEN [S].[freq_subday_type] = 1 THEN ''''AT_TIME''''
            WHEN [S].[freq_subday_type] = 2 THEN ''''SECOND''''
            WHEN [S].[freq_subday_type] = 4 THEN ''''MINUTE''''
            WHEN [S].[freq_subday_type] = 8 THEN ''''HOUR''''
            WHEN [S].[freq_type] IS NULL THEN ''''Not scheduled''''
            WHEN [S].[freq_type] = 64 THEN ''''ONCE'''' 
        END AS [JobFrequencyType], 
        [S].[freq_subday_interval] AS [JobFrequencyInterval], 
        ISNULL(''''Runs '''' + 
        CASE 
            WHEN [S].[freq_recurrence_factor] > 0 AND [S].[freq_type] = 1 THEN ''''once'''' 
            WHEN [S].[freq_recurrence_factor] > 0 AND [S].[freq_type] = 4 THEN ''''every '''' + CONVERT(varchar, [S].[freq_recurrence_factor]) + '''' day(s) ''''
            WHEN [S].[freq_recurrence_factor] > 0 AND [S].[freq_type] = 8 THEN ''''every '''' + CONVERT(varchar, [S].[freq_recurrence_factor]) + '''' week(s) '''' 
            WHEN [S].[freq_recurrence_factor] > 0 AND [S].[freq_type] = 16 THEN ''''every '''' + CONVERT(varchar, [S].[freq_recurrence_factor]) + '''' month(s) '''' 
            WHEN [S].[freq_recurrence_factor] > 0 AND [S].[freq_type] = 32 THEN ''''monthly every '''' + CONVERT(varchar, [S].[freq_recurrence_factor]) + '''' months '''' 
            WHEN [S].[freq_type] = 64 THEN ''''when agent starts '''' 
            WHEN [S].[freq_recurrence_factor] > 0 AND [S].[freq_type] = 128 THEN ''''when Idle'''' 
            WHEN [S].[freq_recurrence_factor] = 0 THEN '''''''' 
            ELSE ''''Unknown'''' 
        END +
        CASE 
            WHEN [S].[freq_subday_type] = 1 THEN ''''at '''' + FORMAT([S].[active_start_time], ''''00:00:00'''') 
            WHEN [S].[freq_subday_type] = 2 THEN ''''every '''' + CONVERT(varchar, [S].[freq_subday_interval]) + '''' seconds''''
            WHEN [S].[freq_subday_type] = 4 THEN ''''every '''' + CONVERT(varchar, [S].[freq_subday_interval]) + '''' minutes''''
            WHEN [S].[freq_subday_type] = 8 THEN ''''every '''' + CONVERT(varchar, [S].[freq_subday_interval]) + '''' hours''''
            WHEN [S].[freq_type] = 64 THEN '''''''' 
        END, ''''Not scheduled'''') AS [Recurrence],
        CASE [JH].[run_status] WHEN 0 THEN ''''Failed'''' WHEN 1 THEN ''''Succeeded'''' WHEN 2 THEN ''''Retry'''' WHEN 3 THEN ''''Cancelled'''' WHEN 4 THEN ''''In Progress'''' ELSE ''''Unknown'''' END AS [LastRunStatus]
FROM    [msdb].[dbo].[sysjobs] [J]
LEFT JOIN [msdb].[dbo].[sysjobschedules] [JS] ON [JS].[job_id] = [J].[job_id]
LEFT JOIN [msdb].[dbo].[sysschedules] [S] ON [S].[schedule_id] = [JS].[schedule_id]
LEFT JOIN (SELECT [job_id], MAX([instance_id]) AS [instance_id] FROM [dbo].[sysjobhistory] GROUP BY [job_id]) AS [JHM] ON [JHM].[job_id] = [J].[job_id]
LEFT JOIN [msdb].[dbo].[sysjobhistory] [JH] ON [JH].[job_id] = [JHM].[job_id] AND [JH].[instance_id] = [JHM].[instance_id]
LEFT JOIN [msdb].[dbo].[sysjobactivity] [JA] ON [JA].[job_id] = [J].[job_id] AND [JA].[job_history_id] = [JH].[instance_id]
WHERE   [J].[enabled] = 1  AND [S].[enabled] = 1 
ORDER BY [J].[name]
END;

'                + N'''' + CHAR(13) + CHAR(10);


    DELETE FROM @servers
    WHERE [servername] = @server;

END;
--PRINT (@query)
EXEC (@query);




--Execute [dbo].[uspRefreshSQLAgentjob]
GO



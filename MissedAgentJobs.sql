USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[MissedAgentJobs]    Script Date: 7/21/2025 12:16:31 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[MissedAgentJobs]  @ServerIDs INT
AS
BEGIN
IF OBJECT_ID ('tempdb..#Job_Summary','U') IS NOT NULL DROP TABLE #Job_Summary
CREATE TABLE #Job_Summary
  ( 
  Environment nvarchar(128),
    MissedSchedule BIT,
	CaptureDate DateTime,
	ServerName sysname,
	JobName NVARCHAR(128) NOT NULL,
	ScheduleName NVARCHAR(128) NOT NULL,
    LastStartTime datetime NULL, --Job Start/Execution Time on that day
	RunDurationHHMMSS nvarchar(30) null, --Time taken for execution
	LastCompletionTime DATETIME NULL, -- Sum of above two to give job Completion Time
	JobStartTime DATETIME, -- Fixed time (Between x & y in schedule)
	JobEndTime DATETIME, -- Fixed time (Between x & y in schedule)
    JobFrequency VARCHAR(35) NULL, -- ONE-TIME, DAILY, WEEKLY, MONTHLY, MONTHLY-RELATIVE, AGENT_STARTUP, COMPUTER_IDLE
    JobFrequencyType VARCHAR(25)NULL, -- UNUSED, AT_TIME, SECONDS, MINUTES, HOURS
    JobFrequencyInterval INT NULL,
    Recurrence NVARCHAR(240),
    LastRunStatus VARCHAR(25) NULL -- ONE-TIME, DAILY, WEEKLY, MONTHLY, MONTHLY-RELATIVE, AGENT_STARTUP, COMPUTER_IDLE
  )
  INSERT INTO #Job_Summary (Environment, MissedSchedule, CaptureDate, ServerName, JobName, ScheduleName, LastStartTime, RunDurationHHMMSS, 
							LastCompletionTime, JobStartTime, JobEndTime, JobFrequency, JobFrequencyType, JobFrequencyInterval, Recurrence, LastRunStatus) 
  SELECT 
	   JS.ServerName AS Environment,
	   CASE 
	   WHEN (JobFrequency = 'Daily' AND JobFrequencyType = 'SECOND'  ) THEN 
		   CASE WHEN (CaptureDate BETWEEN DATEADD(day, DATEDIFF(day, 0,  DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) and DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AND DATEDIFF(SECOND,LastCompletionTime,CaptureDate)>JobFrequencyInterval) THEN 1 
				WHEN (CaptureDate NOT BETWEEN DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) and DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AND DATEDIFF(SECOND,LastCompletionTime,DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)))>JobFrequencyInterval) THEN 1
				ELSE 0 END
	   WHEN (JobFrequency = 'Daily' AND JobFrequencyType = 'MINUTE') THEN  
	   	   CASE WHEN (CaptureDate BETWEEN DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) and DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AND DATEDIFF(MINUTE,LastCompletionTime,CaptureDate)>JobFrequencyInterval) THEN 1 
				WHEN (CaptureDate NOT BETWEEN DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) and DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AND DATEDIFF(MINUTE,LastCompletionTime,DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)))>JobFrequencyInterval) THEN 1
				ELSE 0 END
       WHEN (JobFrequency = 'Daily' AND JobFrequencyType = 'HOUR' ) THEN  
	   	   CASE WHEN (CaptureDate BETWEEN DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) and DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AND DATEDIFF(HOUR,LastCompletionTime,CaptureDate)>JobFrequencyInterval) THEN 1 
				WHEN (CaptureDate NOT BETWEEN DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) and DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AND DATEDIFF(HOUR,LastCompletionTime,DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)))>JobFrequencyInterval) THEN 1
				ELSE 0 END
       WHEN (JobFrequency = 'Daily' AND JobFrequencyType = 'AT_TIME' AND DATEDIFF(HOUR,LastCompletionTime,CaptureDate)>24)THEN 1
       WHEN (JobFrequency = 'Weekly' AND JobFrequencyType = 'AT_TIME' AND Recurrence like '%every 1 week(s)%' AND DATEDIFF(DAY,LastCompletionTime,CaptureDate)>7) THEN 1
       WHEN (JobFrequency = 'Weekly' AND JobFrequencyType = 'AT_TIME' AND Recurrence like '%every 2 week(s)%' AND DATEDIFF(DAY,LastCompletionTime,CaptureDate)>14) THEN 1
       WHEN (JobFrequency like 'Month%' AND JobFrequencyType = 'AT_TIME' AND DATEDIFF(DAY,LastCompletionTime,CaptureDate)>30) THEN 1
       ELSE 0 END AS MissedSchedule,
	   CaptureDate,
	   js.ServerName,
	   JobName,
	   ScheduleName,
	   LastStartTime, 
	   RunDurationHHMMSS,
	   LastCompletionTime,
	   DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobStartTime)) AS JobStartTime,
	   DATEADD(day, DATEDIFF(day, 0, DATEADD(dd, 0, DATEDIFF(dd, 0, JS.LastStartTime))), CONVERT(DATETIME,JS.JobEndTime)) AS JobEndTime,
	   JobFrequency,
	   JobFrequencyType,
	   JobFrequencyInterval,
	   Recurrence,
	   LastRunStatus
   FROM DBA.DailyChecks.tAgentJobSummary JS 
 LEFT JOIN tserver t ON t.ServerName = SUBSTRING(js.ServerName, 0, CHARINDEX('\', js.ServerName)) OR t.ServerName=js.ServerName
	where day(capturedate) = day(getdate()) and month(capturedate) = month(getdate()) and year(capturedate) = year(getdate())
	AND (@ServerIDs = 9999 OR t.ServerID = @ServerIDs)
	--comment to be removed when sql agent job works and is enabled.
   
SELECT   
   
	 CASE 
	   WHEN LastCompletionTime IS NOT NULL AND JobFrequencyType = 'SECOND'  THEN DATEDIFF(SECOND,LastCompletionTime,CaptureDate) 
	   WHEN LastCompletionTime IS NOT NULL AND JobFrequencyType = 'MINUTE'  THEN DATEDIFF(MINUTE,LastCompletionTime,CaptureDate)
       WHEN LastCompletionTime IS NOT NULL AND JobFrequencyType = 'HOUR'    THEN DATEDIFF(HOUR,LastCompletionTime,CaptureDate)
       WHEN LastCompletionTime IS NOT NULL AND JobFrequencyType = 'AT_TIME' THEN DATEDIFF(HOUR,LastCompletionTime,CaptureDate)
       WHEN (LastCompletionTime IS NOT NULL AND JobFrequencyType = 'AT_TIME' AND Recurrence LIKE '%every 1 week(s)%') THEN DATEDIFF(DAY,LastCompletionTime,CaptureDate) 
       WHEN (LastCompletionTime IS NOT NULL AND JobFrequencyType = 'AT_TIME' AND Recurrence LIKE '%every 2 week(s)%') THEN DATEDIFF(DAY,LastCompletionTime,CaptureDate)
       WHEN LastCompletionTime IS NOT NULL AND JobFrequencyType = 'AT_TIME' THEN DATEDIFF(DAY,LastCompletionTime,CaptureDate)
       ELSE 0 END  AS TimeSinceLastRun,
	Environment, MissedSchedule, CaptureDate, ServerName, JobName, ScheduleName, LastStartTime, RunDurationHHMMSS, 
    LastCompletionTime, JobStartTime, JobEndTime, JobFrequency, JobFrequencyType, JobFrequencyInterval, Recurrence, LastRunStatus
	 FROM #Job_Summary C 
	WHERE 
	(LastRunStatus = 'Failed' OR MissedSchedule = 1) 
    GROUP BY
    Environment, MissedSchedule, CaptureDate, ServerName, JobName, ScheduleName, LastStartTime, RunDurationHHMMSS, 
    LastCompletionTime, JobStartTime, JobEndTime, JobFrequency, JobFrequencyType, JobFrequencyInterval, Recurrence, LastRunStatus
	ORDER BY Environment, ServerName, LastRunStatus, JobName, MissedSchedule DESC  
	
END
GO



USE [DBMonitor]
GO
/****** Object:  StoredProcedure [dbo].[DBDashboard]    Script Date: 7/15/2025 1:47:01 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
    
CREATE OR ALTER PROCEDURE [dbo].[DBDashboard] AS     
       
IF OBJECT_ID ('tempdb..#Dashboard','U') IS NOT NULL DROP TABLE #Dashboard       
CREATE TABLE #Dashboard (ServerID INT NOT NULL, MetricName VARCHAR(50), Severity INT, SubReportName VARCHAR(255), SubReportParameters VARCHAR(4000), Tooltip NVARCHAR(max))       
       
IF OBJECT_ID ('tempdb..#ErrorMetric','U') IS NOT NULL DROP TABLE #ErrorMetric       
CREATE TABLE #ErrorMetric (MetricName VARCHAR(50) NOT NULL,Error INT NOT NULL, PRIMARY KEY CLUSTERED (Error,MetricName))       
     
IF OBJECT_ID ('tempdb..#Mem','U') IS NOT NULL DROP TABLE #Mem     
CREATE TABLE #Mem (     
 ServerID INT PRIMARY KEY     
 ,ServerName NVARCHAR(128) NOT NULL UNIQUE     
 ,ServerServerName NVARCHAR(128) NOT NULL     
 ,PhysName NVARCHAR(128) NOT NULL     
 ,PhysMemMB INT NOT NULL     
 ,MaxMemInstanceMB INT NOT NULL 
 ,MaxMemoryPctg TINYINT NOT NULL
 ,DuplicateCount INT DEFAULT 1 NOT NULL     
 ,UNIQUE CLUSTERED (PhysName, ServerID)     
 )     
  
/***************       
* SQL Agent Job Status *       
***************/     
 ;WITH AJS AS (      

 SELECT
	   t.ServerID, 
	   JS.ServerName,
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
	   JS.JobName,
	   JS.LastRunStatus
   FROM DBA.DailyChecks.tAgentJobSummary JS
  LEFT JOIN tserver t ON REPLACE(t.ServerName,'-','') = SUBSTRING(js.ServerName, 0, CHARINDEX('\', js.ServerName)) OR REPLACE(t.ServerName,'-','')=js.ServerName
	WHERE 
	DAY(capturedate) = day(getdate()) and month(capturedate) = month(getdate()) and year(capturedate) = year(getdate()) AND t.Active = 1
	AND 
   (JS.JobName <> '[MSX-Monitoring] - Start XE depending on CPU Performance' 
   AND JS.JobName <> '[DBA] - XE Start on CPU Performance' 
   AND JS.JobName <> '[DBA] Log Connections for dbs - continuous'
   AND JS.JobName <> '[MSX-Monitoring] - Log User Logins')
 )    
    
INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, SubReportParameters, Tooltip)       
SELECT      
 AJS.ServerID      
 ,'SQL Agent Job Failures' AS MetricName      
 ,CASE WHEN COUNT(AJS.JobName)>0 THEN 1 ELSE 3 END AS Severity      
 ,'SQLAgentMissedJobs' AS SubReportName      
 ,NULL AS SubReportParameters,        
 'Click to View' AS ToolTip    
FROM       
 AJS  
 WHERE
 (AJS.MissedSchedule = 1 OR AJS.LastRunStatus = 'Failed')
  GROUP BY AJS.ServerID, AJS.MissedSchedule, AJS.JobName
   PRINT 'sql agent job status'  


/****************       
* Backup Status *       
****************/       
DECLARE @SQL nvarchar(MAX), @ServerName nvarchar(128), @IsLinked bit;
DECLARE @DatabaseName nvarchar(128), @DatabaseGUID uniqueidentifier;

IF OBJECT_ID ('tempdb..#BackupDate') IS NOT NULL DROP TABLE #BackupDate  
CREATE TABLE #BackupDate (
	ServerID INT NULL,  
	ServerName NVARCHAR(128) NULL,
	AGServerName NVARCHAR(128) NULL, 
	DatabaseName NVARCHAR(128),  
	ServerDatabaseID INT,  
	RecoveryModel NVARCHAR(128),  
	LastBackup SMALLDATETIME,  
	LastDatabaseBackup SMALLDATETIME,  
	LastLogBackup SMALLDATETIME,  
	LastDiffBackup SMALLDATETIME,  
	LastFileBackup SMALLDATETIME,  
	LastDatabaseBackupSize BIGINT,  
	LastLogBackupSize BIGINT,  
	LastDiffBackupSize BIGINT,  
	LastFileBackupSize BIGINT,  
	FullFileName NVARCHAR (MAX),  
	LogFileName NVARCHAR (MAX),  
	DiffFileName NVARCHAR (MAX),  
	FileFileName NVARCHAR (MAX),  
	HighlightColor INT,  
	HighlightColorFull CHAR(1),  
	HighlightColorDiff CHAR(1),  
	HighlightColorLog CHAR(1)	  
)  

IF OBJECT_ID('tempdb..#Server', 'U') IS NOT NULL
    DROP TABLE [#Server];
CREATE TABLE [#Server] (
    [ServerID] int,
    [ServerName] nvarchar(128) NOT NULL UNIQUE,
    [Active] int NOT NULL PRIMARY KEY CLUSTERED ([ServerID]) WITH (IGNORE_DUP_KEY = ON), 
    [IsProduction] bit NOT NULL,
	[ISAG] bit NOT NULL
);

INSERT INTO [#Server] ([ServerID], [ServerName], [Active], [IsProduction], [ISAG])
SELECT  [S].[ServerID], [S].[ServerName], [S].[Active], [S].[IsProduction], [S].[ISAG]
FROM    [dbo].[tServer] AS [S]
WHERE   [S].[IsProduction] = 1 AND [S].[IsSQLServer] = 1
--AND [S].[Active] = 1;

INSERT	#Server (ServerID,ServerName,Active,IsProduction,ISAG)
SELECT	DISTINCT s.ServerID, s.ServerName, s.Active, s.IsProduction,s.ISAG
--SELECT * 
FROM (
	SELECT DISTINCT AG.AGName, s.ServerID FROM #Server s
	JOIN dbo.tAGDatabases AG ON AG.ServerID = s.ServerID
) SAG 
JOIN	dbo.tAGDatabases AG ON AG.AGName = SAG.AGName
JOIN	dbo.tServer S ON S.ServerID = AG.ServerID
EXCEPT
SELECT	ServerID,ServerName,Active,IsProduction,ISAG
FROM	#Server;

;WITH G AS (  
SELECT  [S].[ServerID], [D].[DatabaseGUID], [D].[DatabaseName], [BS].[BackupType], MAX([BS].[BackupFinishDate]) AS [BackupFinishDate]
FROM    [#Server] AS [S]
JOIN    [dbo].[tDatabase] AS [D] ON [D].[ServerID] = [S].[ServerID]
JOIN    [dbo].[tBackupSet] AS [BS] ON [BS].[ServerID] = [S].[ServerID]
                                            AND  [BS].[DatabaseGUID] = [D].[DatabaseGUID]											
										
GROUP BY    [S].[ServerID], [D].[DatabaseGUID], [D].[DatabaseName], [BS].[BackupType]
)

,SD AS (
--gets the latest Database ID to weed out duplicates - DatabaseID is an identity so increases on every new insert
SELECT  [S].[ServerID], [D].[DatabaseName], MAX([D].[DatabaseID]) AS [DatabaseID]
FROM    [#Server] [S]
JOIN    [tDatabase] [D] ON [D].[ServerID] = [S].[ServerID]
WHERE   [D].[DatabaseName] NOT in ('tempdb', 'model', 'master', 'msdb', 'MessagesC')
GROUP BY [S].[ServerID], [D].[DatabaseName]
)

,Summary AS (
SELECT  [AD].[AGListerName],
        ISNULL([AD].[AGListerName], [S].[ServerName]) AS [AGServerName],
        [S].[ServerID], 
        [S].[ServerName],
        [S].[IsProduction], 
        [D].[DatabaseName],
        [D].[ServerDatabaseID],
        [D].[DatabaseID], 
        [D].[DatabaseGUID],
        [BS].[BackupType],
        ([BS].[BackupFinishDate]) AS [LastBackup],
        MAX(([BS].[BackupFinishDate])) OVER (PARTITION BY ISNULL([AD].[AGListerName], [S].[ServerName]), [BS].[BackupType]) AS [MaxBackupStartDateByAGServer],
        (SELECT STUFF((SELECT ','+[BSM].[PhyicalDeviceName] FROM [dbo].[tBackupSetMedia] [BSM] WHERE [BSM].[ServerID] = [BS].[ServerID] AND [BSM].[ServerBackupSetUUID] = [BS].[ServerBackupSetUUID] ORDER BY [BSM].[FamilySequenceNumber], [BSM].[Mirror] FOR XML PATH('')), 1, 1, '')) AS [AllFileNames], 
        [BS].[CompressedBackupSize], 
        [BS].[BackupSize]
FROM    [#Server] AS [S]
JOIN    [dbo].[tDatabase] AS [D] ON [D].[ServerID] = [S].[ServerID]
JOIN    [SD] AS [SD] ON [SD].[ServerID] = [D].[ServerID] AND [SD].[DatabaseID] = [D].[DatabaseID]
LEFT JOIN   [G] AS [G] ON [G].[ServerID] = [D].[ServerID]
                   AND  [G].[DatabaseGUID] = [D].[DatabaseGUID]
LEFT JOIN   [dbo].[tBackupSet] AS [BS] ON [BS].[ServerID] = [G].[ServerID]
                                          AND   [BS].[DatabaseGUID] = [G].[DatabaseGUID]
                                          AND   [BS].[BackupType] = [G].[BackupType]
                                          AND   [BS].[BackupFinishDate] = [G].[BackupFinishDate]
LEFT JOIN   [dbo].[tAGDatabases] AS [AD] ON [AD].[ServerID] = [G].[ServerID]
                                            AND [AD].[DatabaseName] = [G].[DatabaseName]
WHERE [D].[Active] = CASE  WHEN AD.[AGListerName] IS NULL THEN  1 ELSE D.[Active] END --on returns primary replica DBs for AG
AND [S].[Active] = 1
)

INSERT INTO #BackupDate(  
	ServerID,
	AGServerName, 
	ServerName, 
	DatabaseName,  
	ServerDatabaseID,  
	RecoveryModel,  
	LastBackup,  
	LastDatabaseBackup,  
	LastLogBackup,  
	LastDiffBackup,  
	LastFileBackup,  
	LastDatabaseBackupSize,  
	LastLogBackupSize,  
	LastDiffBackupSize,  
	LastFileBackupSize,  
	FullFileName,  
	LogFileName,  
	DiffFileName,  
	FileFileName  
	)  

SELECT  [S].[ServerID],
		[S].[AGServerName],
		[S].[ServerName], 
        [S].[DatabaseName], 
        [S].[ServerDatabaseID], 
        CONVERT(nvarchar(128), [DS3].[ConfigurationValue]) AS [RecoveryModel], 
        MAX([S].[MaxBackupStartDateByAGServer]) AS LastBackup, 
        MAX(CASE WHEN [S].[BackupType] = 'D' THEN [S].[LastBackup] ELSE NULL END) AS LastDatabaseBackup, 
        MAX(CASE WHEN [S].[BackupType] = 'L' THEN [S].[LastBackup] ELSE NULL END) AS LastLogBackup, 
        MAX(CASE WHEN [S].[BackupType] = 'I' THEN [S].[LastBackup] ELSE NULL END) AS LastDiffBackup, 
        MAX(CASE WHEN [S].[BackupType] = 'F' THEN [S].[LastBackup] ELSE NULL END) AS LastFileBackup, 
        MAX(CASE WHEN [S].[BackupType] = 'D' THEN ISNULL([S].[CompressedBackupSize], [S].[BackupSize]) ELSE NULL END) AS LastDatabaseBackupSize, 
        MAX(CASE WHEN [S].[BackupType] = 'L' THEN ISNULL([S].[CompressedBackupSize], [S].[BackupSize]) ELSE NULL END) AS LastLogBackupSize, 
        MAX(CASE WHEN [S].[BackupType] = 'I' THEN ISNULL([S].[CompressedBackupSize], [S].[BackupSize]) ELSE NULL END) AS LastDiffBackupSize, 
        MAX(CASE WHEN [S].[BackupType] = 'F' THEN ISNULL([S].[CompressedBackupSize], [S].[BackupSize]) ELSE NULL END) AS LastFileBackupSize, 
        MAX(CASE WHEN [S].[BackupType] = 'D' THEN [S].[AllFileNames] ELSE NULL END) AS FullFileName, 
        MAX(CASE WHEN [S].[BackupType] = 'L' THEN [S].[AllFileNames] ELSE NULL END) AS LogFileName, 
        MAX(CASE WHEN [S].[BackupType] = 'I' THEN [S].[AllFileNames] ELSE NULL END) AS DiffFileName, 
        MAX(CASE WHEN [S].[BackupType] = 'F' THEN [S].[AllFileNames] ELSE NULL END) AS FileFileName
FROM    [Summary] [S] 
JOIN    [dbo].[tDatabaseConfiguration] [DS1] ON [S].[DatabaseID] = [DS1].[DatabaseID]
                                                AND [DS1].[EndDate] IS NULL
                                                AND [DS1].[ConfigurationName] = 'state_desc'
                                                AND CONVERT(nvarchar(128), [DS1].[ConfigurationValue]) = N'ONLINE'
JOIN    [dbo].[tDatabaseConfiguration] [DS2] ON [S].[DatabaseID] = [DS2].[DatabaseID]
                                                AND [DS2].[EndDate] IS NULL
                                                AND [DS2].[ConfigurationName] = 'is_read_only'
                                                AND CONVERT(bit, [DS2].[ConfigurationValue]) = CONVERT(bit, 0)
JOIN    [dbo].[tDatabaseConfiguration] [DS3] ON [S].[DatabaseID] = [DS3].[DatabaseID]
                                                AND [DS3].[EndDate] IS NULL
                                                AND [DS3].[ConfigurationName] = 'recovery_model_desc'
GROUP BY [S].[AGServerName],[S].[ServerID], [S].[ServerName], [S].[DatabaseName], [S].[ServerDatabaseID], CONVERT(nvarchar(128), [DS3].[ConfigurationValue]), [S].[IsProduction]
ORDER BY [AGServerName], [DatabaseName], [ServerName],[S].[ServerID];

--Blank-out Simple Recovery Log Backup Date or if occured before Full or Diff Backup  
UPDATE #BackupDate  
SET  
	LastLogBackup=NULL  
WHERE  
	RecoveryModel='SIMPLE'  

;WITH MaxBackupDates AS 
(
 SELECT 
 	AGServerName, 
	DatabaseName,	  
	MAX(LastBackup) AS MaxLastBackup,  
	MAX(LastDatabaseBackup) AS MaxLastDatabaseBackup,  
	MAX(LastLogBackup) AS MaxLastLogBackup,  
	MAX(LastDiffBackup) AS MaxLastDiffBackup,  
	MAX(LastFileBackup) AS MaxLastFileBackup
	FROM #BackupDate WHERE LastBackup is NOT NULL
	GROUP BY  	AGServerName, 
	DatabaseName
)

UPDATE #BackupDate SET  
LastBackup = MaxLastBackup, 
LastDatabaseBackup = MaxLastDatabaseBackup, 
LastLogBackup = MaxLastLogBackup, 
LastDiffBackup = MaxLastDiffBackup, 
LastFileBackup = MaxLastFileBackup
FROM #BackupDate DB
LEFT JOIN  MaxBackupDates MBD
ON DB.AGServerName = MBD.AGServerName AND DB.DatabaseName = MBD.DatabaseName
WHERE DB.[ServerName] <> DB.[AGServerName]

UPDATE #BackupDate  
SET  
HighlightColorFull=CASE 
				WHEN LastDatabaseBackup IS NULL OR LastDatabaseBackup<=GETUTCDATE()-15 THEN 'R' 
				WHEN LastDatabaseBackup>GETUTCDATE()-15 AND LastDatabaseBackup<GETUTCDATE()-7 THEN 'O' 
				WHEN LastDatabaseBackup>=GETUTCDATE()-7 THEN 'G' ELSE 'B' END  
,HighlightColorDiff=CASE 
				WHEN ServerDatabaseID IN (1,2,3,4) THEN 'B'
				WHEN LastDiffBackup>=GETUTCDATE()-1 OR LastDatabaseBackup>=GETUTCDATE()-1 THEN 'G'
				WHEN (LastDiffBackup IS NULL OR LastDiffBackup<=GETUTCDATE()-7) AND LastDatabaseBackup<GETUTCDATE()-3 THEN 'R' 
				WHEN (LastDiffBackup>=GETUTCDATE()-3 AND LastDiffBackup<GETUTCDATE()-1) AND (LastDatabaseBackup>=GETUTCDATE()-3 AND  LastDatabaseBackup<GETUTCDATE()-1) THEN 'O'
				ELSE 'B' END
,HighlightColorLog=CASE 
				WHEN RecoveryModel='Simple' THEN 'G' 
				WHEN LastLogBackup IS NULL OR LastLogBackup<=GETUTCDATE()-2 THEN 'R' 
				WHEN LastLogBackup>GETUTCDATE()-1 AND LastLogBackup<GETUTCDATE()-0.25 THEN 'O' 
				WHEN LastLogBackup>=GETUTCDATE()-0.25 THEN 'G' ELSE 'B' END  
--SELECT GETUTCDATE()-1		2020-05-02 00:12:52.780		  
;WITH BD AS (SELECT HighlightColor, HighlightColorFull+HighlightColorDiff+HighlightColorLog AS HighlightColorAll FROM #BackupDate)  
UPDATE BD SET BD.HighlightColor=CASE WHEN BD.HighlightColorAll LIKE '%R%' THEN 1 WHEN BD.HighlightColorAll LIKE '%O%' AND BD.HighlightColorAll NOT LIKE '%R%' THEN 2 WHEN BD.HighlightColorAll = 'GGG' THEN 3 WHEN BD.HighlightColorAll LIKE '%B%' AND BD.HighlightColorAll NOT LIKE '%O%' AND BD.HighlightColorAll NOT LIKE '%R%' THEN 2 ELSE 1 END  

       
INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, Tooltip)       
SELECT
	BD.ServerID,
		   --,[S].[ServerName]
       'Backup Status' AS [MetricName]
       /*has any replica backed up successfully for this AG*/
       ,MIN(HighlightColor) AS [Severity]
       ,'Database Backup Dates' AS [SubReportName]
       ,'Backup Dates Detail for [ServerName]' AS [ToolTip]
	 FROM #BackupDate BD
	 WHERE LASTbackup is NOT NULL AND  [ServerName] = [AGServerName]
	 GROUP BY [BD].[ServerID], [BD].[ServerName]
	 UNION 
SELECT 
	BD.ServerID,
		   --,[S].[ServerName]
       'Backup Status' AS [MetricName]
       /*has any replica backed up successfully for this AG*/
       ,MIN(HighlightColor) AS [Severity]
       ,'Database Backup Dates' AS [SubReportName]
       ,'Backup Dates Detail for [ServerName]' AS [ToolTip]
	 FROM #BackupDate BD
	 JOIN tAGPrimaryDatabase PDB
	 ON BD.ServerID = PDB.ServerID AND BD.ServerDatabaseID = PDB.ServerDatabaseID	 
	 WHERE LASTbackup is NOT NULL AND  [ServerName] <> [AGServerName]
	 GROUP BY [BD].[ServerID], [BD].[ServerName]
    
 PRINT 'backup status'        
       
--/**************       
--* Log Errors *       
--*************/       
INSERT INTO #ErrorMetric (MetricName, Error)           
SELECT 'Logon Failure', message_id AS Error FROM sys.messages WHERE is_event_logged=1 AND severity=14 AND language_id=1033 AND message_id <> 18456
AND TEXT NOT LIKE '%NT AUTHORITY\ANONYMOUS LOGON%' 
AND TEXT NOT LIKE '%untrusted domain%'
INSERT INTO #ErrorMetric (MetricName, Error)       
SELECT 'Replication Failure' AS MetricName, message_id AS Error FROM sys.messages WHERE text LIKE '%replication%' AND is_event_logged=1 AND severity>10 AND language_id=1033       
--INSERT INTO #ErrorMetric (MetricName, Error)       
--SELECT 'HADR Failure' AS MetricName, message_id AS Error FROM sys.messages WHERE text LIKE '%hadr%' AND is_event_logged=1 AND severity>10 AND language_id=1033       
INSERT INTO #ErrorMetric (MetricName, Error)       
SELECT 'Log Shipping Failure' AS MetricName, message_id AS Error FROM sys.messages WHERE text LIKE '%log shipping%' AND is_event_logged=1 AND severity>10 AND language_id=1033       
--INSERT INTO #ErrorMetric (MetricName, Error)       
--SELECT 'SEVERITY ' + CONVERT(VARCHAR(50),severity)+' Failure' AS MetricName, message_id AS Error FROM sys.messages WHERE is_event_logged=1 AND severity>=16 AND language_id=1033       
INSERT INTO #ErrorMetric (MetricName, Error)       
SELECT 'Stack Dump' AS MetricName, -1 AS Error      
INSERT INTO #ErrorMetric (MetricName, Error)       
SELECT 'Kerberos Failure' AS MetricName, -18456 AS Error      
      
DECLARE @LogStartDate24 DATETIME=CURRENT_TIMESTAMP-1       
  ,@LogStartDate1 DATETIME       
SET @LogStartDate1=@LogStartDate24+(23.0/24)       
      
--Specific Error Numbers      
;WITH C AS(       
SELECT        
 ServerID       
 ,E.MetricName       
 ,SUM (CASE WHEN L.LogDate>=@LogStartDate1 THEN 1 ELSE 0 END) AS Cnt1       
 ,COUNT(*) AS Cnt24       
 ,STUFF(       
 (SELECT ',' + CONVERT(VARCHAR(50),L2.Error)      
  FROM        
   tServerLog L2       
   JOIN #ErrorMetric E2 ON L2.Error=E2.Error AND E2.MetricName=E.MetricName       
  WHERE        
   L2.LogDate BETWEEN MIN(L.LogDate) AND MAX(L.LogDate)       
   AND L2.ServerID=L.ServerID       
 GROUP BY L2.Error       
 ORDER BY L2.Error       
 FOR XML PATH('')),1,1,'') AS Errors       
FROM        
 tServerLog L       
 JOIN #ErrorMetric E ON L.Error=E.Error       
WHERE        
 L.LogDate BETWEEN @LogStartDate24 AND @LogStartDate24+2       
 and l.ServerID not in (Select ServerID  from tserver where ServerGroupID <> 3)    
GROUP BY        
 L.ServerID       
 ,E.MetricName       
)       
       
INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, SubReportParameters, Tooltip)       
SELECT       
 C.ServerID       
 ,C.MetricName+'s' AS MetricName       
 ,CASE        
  WHEN Cnt1>=1 OR Cnt24>=24 THEN 1       
  WHEN Cnt24>0 THEN 2       
  ELSE 3 END AS Severity       
 ,'Server Log Error' AS SubReportName       
 ,''+C.Errors+'' AS SubReportParameters       
 ,CONVERT(VARCHAR(10),Cnt1)+' '+C.MetricName+CASE WHEN Cnt1=1 THEN '' ELSE 's' END+' in the last hour and '+CONVERT(VARCHAR(10),Cnt24)+' in the last day. Error'+CASE WHEN C.Errors LIKE '%,%' THEN 's: ' ELSE ': ' END + C.Errors AS ToolTip       
FROM C       
      
--High Severity Errors      
;WITH C AS(       
SELECT        
 ServerID       
 ,'SEVERITY ' + CONVERT(VARCHAR(50),L.Severity)+' Failure' AS MetricName       
 ,SUM (CASE WHEN L.LogDate>=@LogStartDate1 THEN 1 ELSE 0 END) AS Cnt1       
 ,COUNT(*) AS Cnt24       
 ,STUFF(       
 (SELECT ',' + CONVERT(VARCHAR(50),L2.Error)      
  FROM        
   tServerLog L2       
  WHERE        
   L2.LogDate BETWEEN MIN(L.LogDate) AND MAX(L.LogDate)       
   AND L2.LogDate BETWEEN @LogStartDate24 AND @LogStartDate24+2       
   AND L2.ServerID=L.ServerID       
   AND L2.Severity=L.Severity      
 GROUP BY L2.Error       
 ORDER BY L2.Error       
 FOR XML PATH('')),1,1,'') AS Errors       
FROM        
 tServerLog L       
WHERE
 L.Error <> 17806
 AND l.Text not like '%SSPI handshake%' AND 
 L.LogDate BETWEEN @LogStartDate24 AND @LogStartDate24+2       
 AND L.Severity>=16      
     
    
GROUP BY        
 L.ServerID       
 ,L.Severity      
)       
       
INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, SubReportParameters, Tooltip)       
SELECT        
 C.ServerID       
 ,C.MetricName+'s' AS MetricName       
 ,CASE        
  WHEN Cnt1>=1 OR Cnt24>=24 THEN 1       
  WHEN Cnt24>0 THEN 2       
  ELSE 3 END AS Severity       
 ,'Server Log Error' AS SubReportName       
 ,''+C.Errors+'' AS SubReportParameters       
 ,CONVERT(VARCHAR(10),Cnt1)+' '+C.MetricName+CASE WHEN Cnt1=1 THEN '' ELSE 's' END+' in the last hour and '+CONVERT(VARCHAR(10),Cnt24)+' in the last day. Error'+CASE WHEN C.Errors LIKE '%,%' THEN 's: ' ELSE ': ' END + C.Errors AS ToolTip      
FROM C       
  PRINT 'log errors'      
      
     
/***************     
* DBCC CHECKDB *     
***************/     
;WITH CheckDB AS (      
SELECT      
 D.ServerID
 ,S.ServerName
 ,D.DatabaseName
 ,CONVERT(DATETIME,DCT.ConfigurationValue) AS CREATE_DATE
 ,CONVERT(INT,DCE.ConfigurationValue) AS CHECKDB_Errors     
 ,CONVERT(DATETIME,DCD.ConfigurationValue) AS CHECKDB_Date     
 ,CASE      
  WHEN CONVERT(INT,DCE.ConfigurationValue)>0 THEN 1 --Errors Found   
  WHEN (CONVERT(DATETIME,DCD.ConfigurationValue)<=CURRENT_TIMESTAMP-15 AND CONVERT(DATETIME,DCD.ConfigurationValue)<>0) THEN 2 --Expired
  WHEN (CONVERT(DATETIME,DCD.ConfigurationValue)= 0 AND CONVERT(INT,DCE.ConfigurationValue)= -1 AND CONVERT(DATETIME,DCT.ConfigurationValue)>= CURRENT_TIMESTAMP-15) THEN 3 --New Database
  WHEN (CONVERT(DATETIME,DCD.ConfigurationValue)= 0 AND CONVERT(INT,DCE.ConfigurationValue)= -1 AND CONVERT(DATETIME,DCT.ConfigurationValue)< CURRENT_TIMESTAMP-15) THEN 2 --DBCC CheckDB Never happened  
  WHEN CONVERT(INT,DCE.ConfigurationValue)=0 THEN 3 --No Erros Found    
	 ELSE 1 END --Unknown Reason    
  AS Severity     
FROM       
 tServer S     
 JOIN tDatabase D     
  ON D.ServerID=S.ServerID     
 JOIN tDatabaseConfiguration DCS     
  ON DCS.DatabaseID=D.DatabaseID     
  AND DCS.ConfigurationName=N'is_in_standby'     
  AND DCS.EndDate IS NULL     
  AND CONVERT(BIT,DCS.ConfigurationValue)=0    
  JOIN tDatabaseConfiguration DCR     
  ON DCR.DatabaseID=D.DatabaseID     
  AND DCR.ConfigurationName=N'is_distributor'     
  AND DCR.EndDate IS NULL     
  AND CONVERT(BIT,DCR.ConfigurationValue)=0  
 JOIN tDatabaseConfiguration DCD     
  ON DCD.DatabaseID=D.DatabaseID     
  AND DCD.ConfigurationName=N'CHECKDB_Date'     
  AND DCD.EndDate IS NULL     
 JOIN tDatabaseConfiguration DCE     
  ON DCE.DatabaseID=D.DatabaseID     
  AND DCE.ConfigurationName=N'CHECKDB_Errors'     
  AND DCE.EndDate IS NULL
 JOIN tDatabaseConfiguration DCT     
  ON DCT.DatabaseID=D.DatabaseID     
  AND DCT.ConfigurationName=N'CREATE_DATE'     
  AND DCT.EndDate IS NULL
WHERE     
 S.Active=1 
 AND S.IsProduction = 1    
 AND D.Active=1    
 AND D.DatabaseName NOT IN ('DBA')    
 UNION
SELECT      
 D.ServerID
 ,S.ServerName
 ,D.DatabaseName
 ,CONVERT(DATETIME,DCT.ConfigurationValue) AS CREATE_DATE
 ,CONVERT(INT,DCE.ConfigurationValue) AS CHECKDB_Errors     
 ,CONVERT(DATETIME,DCD.ConfigurationValue) AS CHECKDB_Date     
 ,CASE      
  WHEN CONVERT(INT,DCE.ConfigurationValue)>0 THEN 1 --Errors Found   
  WHEN (CONVERT(DATETIME,DCD.ConfigurationValue)<=CURRENT_TIMESTAMP-15 AND CONVERT(DATETIME,DCD.ConfigurationValue)<>0) THEN 2 --Expired
  WHEN (CONVERT(DATETIME,DCD.ConfigurationValue)= 0 AND CONVERT(INT,DCE.ConfigurationValue)= -1 AND CONVERT(DATETIME,DCT.ConfigurationValue)>= CURRENT_TIMESTAMP-15) THEN 3 --New Database
  WHEN (CONVERT(DATETIME,DCD.ConfigurationValue)= 0 AND CONVERT(INT,DCE.ConfigurationValue)= -1 AND CONVERT(DATETIME,DCT.ConfigurationValue)< CURRENT_TIMESTAMP-15) THEN 2 --DBCC CheckDB Never happened  
  WHEN CONVERT(INT,DCE.ConfigurationValue)=0 THEN 3 --No Erros Found    
	 ELSE 1 END --Unknown Reason    
  AS Severity     
FROM       
 tServer S     
 JOIN tDatabase D     
  ON D.ServerID=S.ServerID     
 JOIN tDatabaseConfiguration DCS     
  ON DCS.DatabaseID=D.DatabaseID     
  AND DCS.ConfigurationName=N'is_in_standby'     
  AND DCS.EndDate IS NULL     
  AND CONVERT(BIT,DCS.ConfigurationValue)=0    
 JOIN tDatabaseConfiguration DCR     
  ON DCR.DatabaseID=D.DatabaseID     
  AND DCR.ConfigurationName=N'is_distributor'     
  AND DCR.EndDate IS NULL     
  AND CONVERT(BIT,DCR.ConfigurationValue)=1  
 JOIN tCurrentAGHealthStatus AHS
 ON S.ServerName=AHS.ReplicaServerName 
 AND AHS.RoleDescription = 'PRIMARY'
 JOIN tDatabaseConfiguration DCD     
  ON DCD.DatabaseID=D.DatabaseID    
  AND DCD.ConfigurationName=N'CHECKDB_Date'     
  AND DCD.EndDate IS NULL     
 JOIN tDatabaseConfiguration DCE     
  ON DCE.DatabaseID=D.DatabaseID     
  AND DCE.ConfigurationName=N'CHECKDB_Errors'     
  AND DCE.EndDate IS NULL
 JOIN tDatabaseConfiguration DCT     
  ON DCT.DatabaseID=D.DatabaseID     
  AND DCT.ConfigurationName=N'CREATE_DATE'     
  AND DCT.EndDate IS NULL
WHERE     
 S.Active=1 
 AND S.IsProduction = 1    
 AND D.Active=1    
 AND D.DatabaseName NOT IN ('DBA')    
)

INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, SubReportParameters, Tooltip)
SELECT      
 CDB2.ServerID
  ,'DBCC CHECKDB' AS MetricName      
 ,MIN(CDB2.Severity) AS Severity      
 ,'CheckDBSubReport' AS SubReportName      
 ,NULL AS SubReportParameters      
 ,REPLACE(      
  STUFF(       
   (SELECT TOP 25     
    ',' + CDB1.DatabaseName + ' - '     
    + CASE	      
     WHEN CDB1.CHECKDB_Errors>0 THEN CONVERT(NVARCHAR(5),CDB1.CHECKDB_Errors) + ' Error' + CASE CDB1.CHECKDB_Errors WHEN 1 THEN '' ELSE 's' END + '; Last Check Date: [' + CONVERT(NVARCHAR(20),CDB1.CHECKDB_Date,100) +']'    
     WHEN CDB1.Severity=2 AND CDB1.CHECKDB_Date<>0 AND CDB1.CREATE_DATE < CURRENT_TIMESTAMP-15 THEN 'Expired; Last Check Date: [' + CONVERT(NVARCHAR(20),CDB1.CHECKDB_Date,100) +']'  
     WHEN CDB1.CHECKDB_Errors=0 THEN 'OK; Last Check Date: [' + CONVERT(NVARCHAR(20),CDB1.CHECKDB_Date,100) +']'
	 WHEN CDB1.CHECKDB_Errors= -1 AND CDB1.CHECKDB_Date=0 AND CDB1.CREATE_DATE >= CURRENT_TIMESTAMP-15 THEN 'New DB on ['+ CONVERT(NVARCHAR(20),CDB1.CREATE_DATE,100) +']'
	 WHEN CDB1.Severity=2 AND CDB1.CHECKDB_Errors= -1 AND CDB1.CHECKDB_Date=0 AND CDB1.CREATE_DATE < CURRENT_TIMESTAMP-15 THEN 'NEVER Started; DB Created: ['+ CONVERT(NVARCHAR(20),CDB1.CREATE_DATE,100) +']'
     ELSE 'Unknown Reason'        
    END     
   FROM        
    CheckDB CDB1     
   WHERE       
    CDB1.ServerID=CDB2.ServerID      
   ORDER BY CDB1.Severity, CDB1.[DatabaseName]     
   FOR XML PATH('')),1,1,'')       
  ,',',CHAR(13)+CHAR(10)    
 )AS ToolTip      
FROM       
 CheckDB CDB2      
 GROUP BY      
 CDB2.ServerID 
 PRINT 'check db status'      
    
    
/***************       
* Volume Capacity *       
***************/     
 ;WITH VS AS (      
SELECT  sisv.ServerID AS ServerId     
 ,sisv.SpaceFreePercent AS SpaceFreePercent    
 ,sisv.LogicalVolumeName as VolumeName    
 ,sisv.TimeStamp as TimeStamp    
    
FROM       
 SQLInstanceStorageVolumestatus SISV)    
    
INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, SubReportParameters, Tooltip)       
SELECT      
 vs.ServerID      
 ,'Volume Status' AS MetricName      
 ,CASE WHEN vs.SpaceFreePercent>=12 THEN 2 ELSE 1 END AS Severity      
 ,'VolumeStatusLog' AS SubReportName      
 ,NULL AS SubReportParameters      
 ,vs.SpaceFreePercent AS ToolTip      
FROM       
 VS     
 JOIN tServer ts on vs.ServerId=ts.ServerID      
  where   
  (DAY(vs.TimeStamp)=day(GETDATE()) AND month(vs.TimeStamp)=month(GETDATE()) AND Year(vs.TimeStamp)=year(GETDATE()))  
  PRINT 'volume status'    

 /***************       
* Inactive Instances *       
***************/  
 ;With CII as (
 SELECT ServerID, ServerGroupID, ServerName, Active 
FROM DBA.dbo.tServer
WHERE Active = 0 
AND servername LIKE '%DBS%'
)

INSERT INTO #Dashboard (ServerID, MetricName, Severity, SubReportName, SubReportParameters, Tooltip)       
SELECT      
 CII.ServerID      
 ,'Inactive Instances on tServer' AS MetricName      
 ,CASE WHEN CII.Active = 0 THEN 1
  ELSE 3 END AS Severity      
 ,NULL AS SubReportName      
 ,NULL AS SubReportParameters      
 ,NULL AS ToolTip      
 FROM  CII     
 PRINT 'Inactive Instances'
 

/***************       
* FINAL RESULT *       
***************/       
SELECT        
 SG.ServerGroupName       
 ,S.ServerName       
 ,DB.ServerID       
 ,DB.MetricName       
 ,DB.Severity       
 ,ISNULL(DB.SubReportName,'NoSubReport') AS  SubReportName
 ,DB.SubReportParameters       
 ,REPLACE(DB.Tooltip,'[ServerName]',S.ServerName) AS Tooltip       
FROM        
 #Dashboard DB       
 JOIN tServer S ON        
  DB.ServerID=S.ServerID       
 JOIN tServerGroup SG       
  ON S.ServerGroupID=SG.ServerGroupID
  ORDER BY DB.MetricName,S.ServerID
     
    
    
    
--  exec [dbo].[DBDashboard]    


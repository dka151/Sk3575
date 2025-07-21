USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rDatabaseBackupDate]    Script Date: 7/21/2025 11:01:31 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[rDatabaseBackupDate] @ServerIDs VARCHAR(MAX) = NULL AS  
 
--This procedure returns a list of Databases and Backup Dates  

DECLARE @SQL nvarchar(MAX), @ServerName nvarchar(128), @IsLinked bit, @X xml;
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
	HighlightColor CHAR(1),  
	HighlightColorFull CHAR(1),  
	HighlightColorDiff CHAR(1),  
	HighlightColorLog CHAR(1),
	ServerWithLastDatabaseBackup NVARCHAR(256) NULL,
	ServerWithLastDiffBackup NVARCHAR(256) NULL, 
	ServerWithLastLogBackup NVARCHAR(256) NULL,	  
	ServerWithLastFileBackup NVARCHAR(256)  
	  
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

SET @X = '<r>' + REPLACE(@ServerIDs, ',', '</r>' + '<r>') + '</r>';
WITH [SX] AS (SELECT    [Tbl].[Col].[value]('.', 'INT') AS [ServerID] FROM @X.[nodes]('//r') AS [Tbl]([Col]) )
INSERT INTO [#Server] ([ServerID], [ServerName], [Active], [IsProduction], [ISAG])
SELECT  [S].[ServerID], [S].[ServerName], [S].[Active], [S].[IsProduction], [S].[ISAG]
FROM    [dbo].[tServer] AS [S]
JOIN    [SX] ON [S].[ServerID] = [SX].[ServerID]
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
WHERE   [D].[DatabaseName] NOT in ('tempdb', 'model', 'master', 'msdb')
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
--AND [S].[Active] = 1
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
	DatabaseName)
 
UPDATE #BackupDate SET  
LastBackup = MaxLastBackup, 
LastDatabaseBackup = MaxLastDatabaseBackup, 
LastLogBackup = MaxLastLogBackup, 
LastDiffBackup = MaxLastDiffBackup, 
LastFileBackup = MaxLastFileBackup,
ServerWithLastDatabaseBackup=(SELECT QUOTENAME(B.Servername)+CHAR(13)+CHAR(10)+Convert(VARCHAR, B.LastDatabaseBackup, 100) FROM #BackupDate B WHERE B.LastDatabaseBackup = MBD.MaxLastDatabaseBackup AND B.AGServerName = MBD.AGServerName AND B.DatabaseName = MBD.DatabaseName),
ServerWithLastDiffBackup=(SELECT QUOTENAME(B.Servername)+CHAR(13)+CHAR(10)+Convert(VARCHAR, B.LastDiffBackup, 100) FROM #BackupDate B WHERE B.LastDiffBackup = MBD.MaxLastDiffBackup AND B.AGServerName = MBD.AGServerName AND B.DatabaseName = MBD.DatabaseName),
ServerWithLastLogBackup=(SELECT QUOTENAME(B.Servername)+CHAR(13)+CHAR(10)+Convert(VARCHAR, B.LastLogBackup, 100) FROM #BackupDate B WHERE B.LastLogBackup = MBD.MaxLastLogBackup  AND B.AGServerName = MBD.AGServerName AND B.DatabaseName = MBD.DatabaseName),
ServerWithLastFileBackup=(SELECT QUOTENAME(B.Servername)+CHAR(13)+CHAR(10)+Convert(VARCHAR, B.LastFileBackup, 100) FROM #BackupDate B WHERE B.LastFileBackup = MBD.MaxLastFileBackup AND B.AGServerName = MBD.AGServerName AND B.DatabaseName = MBD.DatabaseName)
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
				WHEN LastLogBackup IS NULL OR LastLogBackup<GETUTCDATE()-1 THEN 'R' 
				WHEN LastLogBackup>GETUTCDATE()-1 AND LastLogBackup<GETUTCDATE()-0.25 THEN 'O' 
				WHEN LastLogBackup>=GETUTCDATE()-0.25 THEN 'G' ELSE 'B' END 
								  
;WITH BD AS (SELECT HighlightColor, HighlightColorFull+HighlightColorDiff+HighlightColorLog AS HighlightColorAll FROM #BackupDate)  
UPDATE BD SET BD.HighlightColor=CASE WHEN BD.HighlightColorAll LIKE '%R%' THEN 'R' WHEN BD.HighlightColorAll LIKE '%O%' AND BD.HighlightColorAll NOT LIKE '%R%' THEN 'O' WHEN BD.HighlightColorAll = 'GGG' THEN 'G' WHEN BD.HighlightColorAll LIKE '%B%' AND BD.HighlightColorAll NOT LIKE '%O%' AND BD.HighlightColorAll NOT LIKE '%R%' THEN 'B' ELSE 'R' END    
 

 SELECT 
	BD.ServerName, 
	BD.AGServerName,
	BD.DatabaseName,  
	BD.ServerDatabaseID,  
	BD.RecoveryModel,  
	BD.LastBackup,  
	CONVERT(VARCHAR, BD.LastDatabaseBackup, 100) AS LastDatabaseBackup,
	CONVERT(VARCHAR, BD.LastDiffBackup, 100) AS LastDiffBackup,
	CONVERT(VARCHAR, BD.LastLogBackup, 100) AS LastLogBackup,	 
	CONVERT(VARCHAR, BD.LastFileBackup, 100) AS LastFileBackup, 
	BD.LastDatabaseBackupSize,
	BD.LastDiffBackupSize,  
	BD.LastLogBackupSize,	  
	BD.LastFileBackupSize,  
	BD.FullFileName,  
	BD.LogFileName,  
	BD.DiffFileName,  
	BD.FileFileName,
	BD.HighlightColor,
	BD.HighlightColorFull,
	BD.HighlightColorDiff,
	BD.HighlightColorLog
	 FROM #BackupDate BD
	 WHERE LASTbackup is NOT NULL AND  [ServerName] = [AGServerName]
	 AND [BD].[DatabaseName] NOT LIKE '%BI%' -- Exclude BI databases from MES Servers
	 UNION
  SELECT 
	BD.ServerName,
	BD.AGServerName,
	BD.DatabaseName,  
	BD.ServerDatabaseID,  
	BD.RecoveryModel,  
	BD.LastBackup,  
	BD.ServerWithLastDatabaseBackup AS LastDatabaseBackup,
	BD.ServerWithLastDiffBackup AS LastDiffBackup,
	BD.ServerWithLastLogBackup AS LastLogBackup,	
	BD.ServerWithLastFileBackup AS LastFileBackup,
	BD.LastDatabaseBackupSize,
	BD.LastDiffBackupSize,  
	BD.LastLogBackupSize,	  
	BD.LastFileBackupSize,  
	BD.FullFileName,  
	BD.LogFileName,  
	BD.DiffFileName,  
	BD.FileFileName,
	BD.HighlightColor,
	BD.HighlightColorFull,
	BD.HighlightColorDiff,
	BD.HighlightColorLog
	 FROM #BackupDate BD
	 JOIN tAGPrimaryDatabase PDB
	 ON BD.ServerID = PDB.ServerID AND BD.ServerDatabaseID = PDB.ServerDatabaseID	 
	 WHERE LASTbackup is NOT NULL AND  [ServerName] <> [AGServerName]
	 order by DatabaseName


GO



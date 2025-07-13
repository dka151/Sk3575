USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshDatabaseFile]    Script Date: 7/13/2025 1:59:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROC [dbo].[pRefreshDatabaseFile]
/***************************************************
* Keep track of all database files and their sizes *
***************************************************/
AS
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;
DECLARE @CDate SMALLDATETIME = CURRENT_TIMESTAMP,
		@SQL NVARCHAR(MAX),
		@ServerID INT,
		@ServerName NVARCHAR (255)
		
IF OBJECT_ID ('tempdb..#Files') IS NOT NULL DROP TABLE #Files
CREATE TABLE #Files(
	[ServerID] [int] NOT NULL,
	[DatabaseID] [int] NULL,
	[DatabaseName] [nvarchar] (255),
	--[FileID] [int] NOT NULL,
	[ServerDatabaseID] [int] NOT NULL,
	[ServerFileID] [int] NOT NULL,
	[FileGroup] [nvarchar](128) NOT NULL,
	[FileName] [nvarchar](128) NOT NULL,
	[PhysicalName] [nvarchar](260) NOT NULL,
	[Type] [tinyint] NOT NULL,
	[CurrentFileSizeMB] [dec] (12,3) NULL,
	[CurrentUsedSizeMB] [dec] (12,3) NULL,
	PRIMARY KEY (ServerID,ServerDatabaseID,ServerFileID)
)

DECLARE  @DBSize TABLE
	(ServerDatabaseID INT,
	DatabaseName NVARCHAR(128),
	ServerFileID INT,
	[FileGroup] NVARCHAR(128),
	[FileName] NVARCHAR(128),
	PhysicalName NVARCHAR(260),
	FileType TINYINT,
	TotalSizeMB DEC (18,6),
	UsedSizeMB DEC (18,6),
	AvailableSpaceMB DEC (18,6) )
	
---------- Define / Begin Server Loop ----------
DECLARE curServers CURSOR 
     FOR 
			/*SELECT  
			ServerID, ServerName 
		FROM  
			tServer  
		WHERE  
			IsSQLServer=1  
			AND Active=1  
			AND EnableServerDBTrack=1 
			AND ISAG<>1
			UNION*/
		SELECT DISTINCT 
			ts.ServerID, ServerName 
		FROM  
			tServer ts  LEFT JOIN [tAGPrimaryDatabase] tag
			ON ts.ServerID = tag.ServerID
		WHERE  
			IsSQLServer=1  
			AND Active=1  
			AND EnableServerDBTrack=1 
			AND ISAG=1
		ORDER BY  
			ServerID
		    
    OPEN curServers

WHILE 1=1
BEGIN
    FETCH NEXT FROM curServers
	INTO @ServerID, @ServerName
	IF @@FETCH_STATUS<>0 BREAK
	PRINT '--------------------'
	RAISERROR ('%s', 0, 1, @ServerName) WITH NOWAIT
	PRINT '--------------------'
	--Get File Information
	DELETE FROM @DBSize
	INSERT INTO @DBSize
		EXEC pGetDatabaseUsedSpace @ServerName
	
	INSERT INTO #Files (ServerID, ServerDatabaseID, DatabaseName, ServerFileID, [FileGroup], [FileName], PhysicalName, [Type], CurrentFileSizeMB, CurrentUsedSizeMB)
	SELECT 
		@ServerID, ServerDatabaseID, DatabaseName, ServerFileID, [FileGroup], [FileName], PhysicalName, FileType, TotalSizeMB, UsedSizeMB
	FROM 
		@DBSize
	WHERE
		DatabaseName NOT IN ('model')
	
	--Update Active Database IDs
	UPDATE F
	SET DatabaseID=
		(SELECT MAX(D.DatabaseID) FROM tDatabase D
		WHERE
		D.ServerDatabaseID=F.ServerDatabaseID
		AND D.ServerID=@ServerID
		AND D.Active=1
		AND D.DatabaseName=F.DatabaseName
		)
	FROM #Files F
	WHERE
		F.ServerID=@ServerID
		AND F.DatabaseID IS NULL

	--Update Non-Active Database IDs
	UPDATE F
	SET DatabaseID=
		(SELECT MAX(D.DatabaseID) FROM tDatabase D
		WHERE
		D.ServerDatabaseID=F.ServerDatabaseID
		AND D.ServerID=@ServerID
		AND D.Active=0
		AND D.DatabaseName=F.DatabaseName
		)
	FROM #Files F
	WHERE
		F.ServerID=@ServerID
		AND F.DatabaseID IS NULL

END
CLOSE curServers
DEALLOCATE curServers
---------- End Server Loop ----------


--Set End Date for no longer matching files
UPDATE DF
SET DF.EndDate=@CDate
FROM tDatabaseFile DF 
JOIN tDatabase D ON DF.DatabaseID=D.DatabaseID
LEFT JOIN #Files F
ON	DF.DatabaseID=F.DatabaseID 
	AND DF.ServerFileID=F.ServerFileID 
	AND DF.[FileGroup]=F.[FileGroup]
	AND DF.[FileName]=F.[FileName]
	AND DF.Type=F.Type
	AND DF.PhysicalName=F.PhysicalName
WHERE 
F.DatabaseID IS NULL
AND DF.EndDate IS NULL
AND D.ServerID IN (SELECT DISTINCT F2.ServerID from #Files F2)


--Insert New Files
INSERT INTO tDatabaseFile (DatabaseID, ServerDatabaseID, ServerFileID, [FileGroup], [FileName], PhysicalName, Type, StartDate)
SELECT F.DatabaseID, F.ServerDatabaseID, F.ServerFileID, F.[FileGroup], F.[FileName], F.PhysicalName, F.Type, @CDate AS StartDate
FROM #Files F
WHERE F.DatabaseID IS NOT NULL
EXCEPT
SELECT DF.DatabaseID, DF.ServerDatabaseID, DF.ServerFileID, DF.[FileGroup], DF.[FileName], DF.PhysicalName, DF.Type, @CDate AS StartDate
FROM tDatabaseFile DF
WHERE EndDate IS NULL

--Update Current Size Snapshot in Database File table
UPDATE DF
SET
DF.CurrentFileSizeMB=F.CurrentFileSizeMB,
DF.CurrentUsedSizeMB=F.CurrentUsedSizeMB
--------------------------------------------------------
,DF.[FileGroup]=F.[FileGroup]
FROM tDatabaseFile DF
JOIN #Files F ON F.DatabaseID=DF.DatabaseID AND F.PhysicalName=DF.PhysicalName AND F.ServerFileID=DF.ServerFileID AND F.Type=DF.Type
WHERE
DF.EndDate IS NULL

--Update File Size History from Current Snapshot
UPDATE FS
SET FS.EndDate=@CDate
FROM 
tDatabaseFileSize FS 
	LEFT JOIN tDatabaseFile DF ON 
		FS.FileID=DF.FileID 
		AND ISNULL(FS.FileSizeMB,-1)=ISNULL(DF.CurrentFileSizeMB,-1)
		AND ISNULL(FS.UsedSizeMB,-1)=ISNULL(DF.CurrentUsedSizeMB,-1)
		AND DF.EndDate IS NULL
WHERE
DF.DatabaseID IS NULL
AND FS.EndDate IS NULL

INSERT INTO tDatabaseFileSize (FileID, StartDate, FileSizeMB, UsedSizeMB)
SELECT DF.FileID, @CDate AS StartDate, DF.CurrentFileSizeMB, DF.CurrentUsedSizeMB
FROM tDatabaseFile DF
WHERE DF.EndDate IS NULL
AND DF.FileID NOT IN
	(SELECT FS.FileID FROM tDatabaseFileSize FS WHERE FS.EndDate IS NULL)


GO



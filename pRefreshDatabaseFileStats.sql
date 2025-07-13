USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshDatabaseFileStats]    Script Date: 7/13/2025 1:59:56 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[pRefreshDatabaseFileStats]
AS
/*************************************************
* Capture I/O activity across all database files *
*************************************************/
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;

DECLARE @ServerID INT
		,@ServerName NVARCHAR (128)
		,@SQL VARCHAR(MAX)
		,@SampleDateID INT
		,@GlobalSampleDate DATETIME=CURRENT_TIMESTAMP
		,@ErrorMessage NVARCHAR(MAX)

--Temp Table for File I/O
IF OBJECT_ID ('tempdb..#FileStats') IS NOT NULL DROP TABLE #FileStats
CREATE TABLE #FileStats(
	[ServerID] INT NOT NULL,
	[SampleDate] DATETIME NOT NULL,
	[ServerDatabaseID] [smallint] NOT NULL,
	[ServerFileId] [smallint] NOT NULL,
	[SampleMS] [bigint] NOT NULL,
	[NumberReads] [bigint] NOT NULL,
	[BytesRead] [bigint] NOT NULL,
	[IoStallReadMS] [bigint] NOT NULL,
	[NumberWrites] [bigint] NOT NULL,
	[BytesWritten] [bigint] NOT NULL,
	[IoStallWriteMS] [bigint] NOT NULL,
	[IoStallMS] [bigint] NOT NULL,
	--[BytesOnDisk] [bigint] NOT NULL,
	--[FileHandle] [varbinary](8) NOT NULL,
	PRIMARY KEY CLUSTERED (ServerID, ServerDatabaseID, ServerFileID)
	)

--Get Global Date ID
INSERT INTO tDatabaseFileStats_SampleDate (GlobalSampleDate) VALUES (@GlobalSampleDate)
SET @SampleDateID=IDENT_CURRENT('dbo.tDatabaseFileStats_SampleDate')

---------- Loop Through All Servers ----------
DECLARE cServer CURSOR 
	FOR 
	SELECT ServerID, ServerName from DBA.dbo.tServer
	WHERE
		EnableIOLog =1
		AND Active = 1
		AND ServerID > 0
	ORDER BY ServerID
    OPEN cServer

WHILE 1=1
BEGIN
    FETCH NEXT FROM cServer
	INTO @ServerID, @ServerName
	IF @@FETCH_STATUS<>0 BREAK
	
	PRINT @ServerName
	
	--Get All of Current DB File I/O statistics
	SET @SQL='SELECT '+CONVERT (VARCHAR (5),@ServerID)+' AS ServerID, CURRENT_TIMESTAMP AS CurrentTimeStamp, database_id, file_id, sample_ms AS sample_ms, num_of_reads, num_of_bytes_read, io_stall_read_ms, /*io_stall_queued_read_ms,*/ num_of_writes, num_of_bytes_written, io_stall_write_ms, /*io_stall_queued_write_ms,*/ io_stall FROM sys.dm_io_virtual_file_stats  (NULL,NULL)'
	--Run 
	IF @ServerID>0 SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']'
	BEGIN TRY
		INSERT INTO #FileStats WITH (TABLOCKX)
		EXEC (@SQL)
	END TRY
	--On Error Do Nothing
	BEGIN CATCH
		SET @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'')+'['+@ServerName+']: '+ERROR_MESSAGE()
	END CATCH
END
CLOSE cServer
DEALLOCATE cServer

--Insert Only Values That Have Changed
BEGIN TRAN
	INSERT INTO tDatabaseFileStats (
		FileId
		,SampleDateID
		,SampleDate
		,SampleMS
		,NumberReads
		,BytesRead
		,IoStallReadMS
		,NumberWrites
		,BytesWritten
		,IoStallWriteMS
	
		,DeltaSampleMS
		,DeltaNumberReads
		,DeltaBytesRead
		,DeltaIoStallReadMS
		,DeltaNumberWrites
		,DeltaBytesWritten
		,DeltaIoStallWriteMS
		)
	SELECT 
		DF.FileID
		,@SampleDateID
		,FS.SampleDate
		,FS.SampleMS
		,FS.NumberReads
		,FS.BytesRead
		,FS.IoStallReadMS
		,FS.NumberWrites
		,FS.BytesWritten
		,FS.IoStallWriteMS

		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS THEN FS.SampleMS ELSE FS.SampleMS-DF.LastSampleMSIO END AS DeltaSampleMS
		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS OR DF.LastNumberReads>FS.NumberReads THEN FS.NumberReads ELSE FS.NumberReads-DF.LastNumberReads END AS DeltaNumberReads
		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS OR DF.LastBytesRead>FS.BytesRead THEN FS.BytesRead ELSE FS.BytesRead-DF.LastBytesRead END AS DeltaBytesRead
		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS OR DF.LastIoStallReadMS>FS.IoStallReadMS THEN FS.IoStallReadMS ELSE FS.IoStallReadMS-DF.LastIoStallReadMS END AS DeltaIoStallReadMS
		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS OR DF.LastNumberWrites>FS.NumberWrites THEN FS.NumberWrites ELSE FS.NumberWrites-DF.LastNumberWrites END AS DeltaNumberWrites
		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS OR DF.LastBytesWritten>FS.BytesWritten THEN FS.BytesWritten ELSE FS.BytesWritten-DF.LastBytesWritten END AS DeltaBytesWritten
		,CASE WHEN DF.LastSampleMSIO IS NULL OR SIGN(DF.LastSampleMSIO)<>SIGN(FS.SampleMS) THEN 0 WHEN DF.LastSampleMSIO>FS.SampleMS OR DF.LastIoStallWriteMS>FS.IoStallWriteMS THEN FS.IoStallWriteMS ELSE FS.IoStallWriteMS-DF.LastIoStallWriteMS END AS DeltaIoStallWriteMS

	FROM
		#FileStats FS 
		JOIN tDatabase D
			ON FS.ServerID=D.ServerID
			AND FS.ServerDatabaseID=D.ServerDatabaseID 
			AND D.Active=1
		JOIN tDatabaseFile DF 
			ON D.DatabaseID=DF.DatabaseID 
			AND FS.ServerFileID = DF.ServerFileID 
			AND DF.EndDate IS NULL
	WHERE
		(
		ISNULL(DF.LastNumberReads,0)<>FS.NumberReads
		OR ISNULL(DF.LastBytesRead,0)<>FS.BytesRead
		OR ISNULL(DF.LastIoStallReadMS,0)<>FS.IoStallReadMS
		OR ISNULL(DF.LastNumberWrites,0)<>FS.NumberWrites
		OR ISNULL(DF.LastBytesWritten,0)<>FS.BytesWritten
		OR ISNULL(DF.LastIoStallWriteMS,0)<>FS.IoStallWriteMS
		)

	--Store Current I/O Information to Be Used In the Next Sample
	UPDATE DF
	SET
		LastSampleMSIO=FS.SampleMS
		,LastNumberReads=FS.NumberReads
		,LastBytesRead=FS.BytesRead
		,LastIoStallReadMS=FS.IoStallReadMS
		,LastNumberWrites=FS.NumberWrites
		,LastBytesWritten=FS.BytesWritten
		,LastIoStallWriteMS=FS.IoStallWriteMS
		,LastSampleDateIO=FS.SampleDate
	FROM
		#FileStats FS 
		JOIN tDatabase D
			ON FS.ServerID=D.ServerID
			AND FS.ServerDatabaseID=D.ServerDatabaseID 
			AND D.Active=1
		JOIN tDatabaseFile DF 
			ON D.DatabaseID=DF.DatabaseID
			AND FS.ServerFileID = DF.ServerFileID 
			AND DF.EndDate IS NULL
COMMIT


/****************
* ERROR HANDLER *
***************/
IF @ErrorMessage IS NOT NULL
	RAISERROR (@ErrorMessage,18,1)


GO



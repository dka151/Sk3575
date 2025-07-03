USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshServerAgentLog]    Script Date: 7/3/2025 12:05:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[pRefreshServerAgentLog] AS 
/********************************************************** 
* Go through all Log files until no records are returned  * 
* Use the last log date stored to start filtering on      * 
* Exclude anything with the same last date, but not count * 
**********************************************************/ 
SET NOCOUNT ON 
DECLARE @SQL NVARCHAR(MAX) 
		,@ServerID INT 
		,@ServerName NVARCHAR(128) 
		,@IsLinked BIT 
		,@ErrorMessage NVARCHAR(MAX) 
		,@LastLogDate DATETIME 
		,@LastLogDateCount INT 
		,@LogFileID INT 
		,@LogFileMaxID INT 
 
IF OBJECT_ID('tempdb.dbo.#Log') IS NOT NULL DROP TABLE #Log 
CREATE TABLE #Log( 
	 LogID INT IDENTITY (1,1) PRIMARY KEY CLUSTERED 
	,LogDate DATETIME NOT NULL 
	,ErrorLevel TINYINT NULL 
	,[Text] NVARCHAR(4000) NULL 
	,[Error] INT NULL 
	,[ErrorPrefix] CHAR(3) NULL 
	,[State] INT NULL 
	,UNIQUE (LogDate, LogID) 
	) 
 
IF OBJECT_ID ('tempdb..#EnumLOG','U') IS NOT NULL DROP TABLE #EnumLOG 
CREATE TABLE #EnumLOG (LogFileID INT PRIMARY KEY CLUSTERED, LogDate DATETIME NOT NULL, LogSizeByte INT NOT NULL) 
 
IF OBJECT_ID('tempdb..#Error','U') IS NOT NULL DROP TABLE #Error
CREATE TABLE #Error (ServerID INT NOT NULL PRIMARY KEY, ServerName NVARCHAR(128) NOT NULL UNIQUE CLUSTERED, ErrorSeverity INT NOT NULL, ErrorMessage NVARCHAR(MAX) NOT NULL)
 
DECLARE curServer CURSOR  
	FOR  
	SELECT  
		S.ServerID, S.ServerName, S.IsLinked 
	FROM  
		dbo.tServer S 
		JOIN dbo.tServerConfiguration SC ON S.ServerID=SC.ServerID AND SC.ConfigurationName = 'Agent XPs' AND SC.EndDate IS NULL 
	WHERE 
		S.IsSQLServer=1 
		AND S.Active=1 
		AND S.EnableServerLog=1 
		AND SC.ConfigurationValue=1 
	ORDER BY S.ServerID 
    OPEN curServer 
 
/*************************** 
* Loop through all servers * 
***************************/ 
WHILE 1=1 
BEGIN 
    FETCH NEXT FROM curServer 
	INTO @ServerID, @ServerName, @Islinked 
	IF @@FETCH_STATUS<>0 BREAK 
	 
	PRINT @ServerName 
	/************** 
	* Get The Log * 
	**************/ 
	BEGIN TRY 
		--Get Last Log Date; go back 7 days if no log was previously collected 
		SET @LastLogDate=CONVERT(DATE,CURRENT_TIMESTAMP-7) 
		SELECT TOP 1 WITH TIES @LastLogDate=LogDate FROM tServerAgentLog WHERE ServerID=@ServerID ORDER BY LogDate DESC 
		SET @LastLogDateCount=@@ROWCOUNT --Retrieve record count for the max log date using WITH TIES clause 
		 
		TRUNCATE TABLE #EnumLOG 
		SET @SQL=N'EXEC master.dbo.xp_EnumErrorLogs 2' 
		IF @IsLinked=1 
				SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']' 
		INSERT INTO #EnumLOG (LogFileID, LogDate, LogSizeByte) 
			EXEC (@SQL) 
 
		SELECT @LogFileMaxID=ISNULL(MAX(LogFileID),0) FROM #EnumLOG WHERE LogDate>=DATEADD(MINUTE,DATEDIFF(MINUTE,0,@LastLogDate)-60,0) --Minute Precision from Enum Error Log; Go back an hour to compensate for DST 
 
		TRUNCATE TABLE #Log 
		SET @LogFileID=@LogFileMaxID+1 --0-based loop in descending order 
		 
		WHILE @LogFileID>0 
		BEGIN --Log File Loop 
			SET @LogFileID-=1 
			PRINT 'Processing Log #'+CONVERT(VARCHAR(5),@LogFileID) 
			SET @SQL='EXEC master.dbo.xp_ReadErrorLog '+CONVERT(NVARCHAR(5),@LogFileID)+', 2, NULL, NULL, N''' + CONVERT(VARCHAR(50),@LastLogDate,121) + '''' 
			--Do not use Linked Server if running locally 
			IF @IsLinked=1 
				SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']' 
		 
			INSERT INTO #Log (LogDate,ErrorLevel,[Text]) 
				EXEC (@SQL) 
		 
			/********************** 
			* Log Successful Ping * 
			**********************/ 
			UPDATE tServerPingLog 
			SET 
				LastPingSource='ServerAgentLog' 
				,LastPingDate=CURRENT_TIMESTAMP 
			WHERE 
				ServerID=@ServerID 
 
		END --Log File Count 
 
		--Remove Logs that have the same log date as the previously-processed last log date 
		;WITH D AS (SELECT TOP (@LastLogDateCount) * FROM #Log WHERE LogDate=@LastLogDate ORDER BY LogID) 
			DELETE FROM D  
		--Delete No-content Entries 
		DELETE FROM #Log WHERE [Text] IS NULL 
		--Delete normal operation messages 
		DELETE FROM #Log WHERE [Text] LIKE 'Reloading agent settings%' 
		--Remove Trailing Spaces 
		UPDATE #Log	SET	[Text]=RTRIM([Text])  
		--Set Error Prefix 
		UPDATE #Log SET ErrorPrefix=SUBSTRING([Text],2,3) WHERE [Text] LIKE '[[]___]%' 
		-- Set Error Number and State 
		UPDATE  
			#Log  
		SET 
			[Error]=SUBSTRING ([Text],24, CHARINDEX (',',[Text])-24) 
			,[State]=REPLACE(RIGHT([Text],PATINDEX('%_[^0-9]%',REVERSE([Text]))),']','') 
		WHERE  
			[Text] LIKE N'[[]___] SQLServer Error: [0-9]%, %. [[]SQLSTATE [0-9]%]' 
 
		--Persist the Log 
		INSERT INTO tServerAgentLog (ServerID, LogDate, ErrorLevel, [Text], Error, ErrorPrefix, [State]) 
			SELECT @ServerID AS ServerID, LogDate, ErrorLevel, [Text], Error, ErrorPrefix, [State] FROM #Log ORDER BY LogID 
		 
	 
	END TRY
	BEGIN CATCH
	INSERT INTO #Error (ServerID, ServerName, ErrorSeverity, ErrorMessage)
		VALUES (@ServerID, @ServerName, ERROR_SEVERITY(), ERROR_MESSAGE())
	END CATCH
 
END --Server Cursor Loop 
CLOSE curServer 
DEALLOCATE curServer 
 
--Report Back Errors
SET @ErrorMessage=NULL
SELECT @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'') + '['+ServerName+']: ' + ErrorMessage FROM #Error
IF @ErrorMessage IS NOT NULL
	RAISERROR (@ErrorMessage,18,1)

 

GO



USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshServerLog]    Script Date: 7/3/2025 12:05:55 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[pRefreshServerLog] AS   
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
	,ProcessInfo VARCHAR(128) NOT NULL   
	,[Text] NVARCHAR(4000) --NOT NULL   
	,[Error] INT NULL   
	,[Severity] INT NULL   
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
		DBA.dbo.tServer S   
	WHERE   
		S.IsSQLServer=1   
		AND S.Active=1   
		AND S.EnableServerLog=1   
		--AND TS.IsAgentRunning=1   
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
		SELECT TOP 1 WITH TIES @LastLogDate=LogDate FROM tServerLog WHERE ServerID=@ServerID ORDER BY LogDate DESC   
		--SET @LastLogDateCount=@@ROWCOUNT --Retrieve record count for the max log date using WITH TIES clause --Disabled due to new counts feature  
		SET @LastLogDateCount=1000  
		  
		TRUNCATE TABLE #EnumLOG   
		SET @SQL=N'EXEC master.dbo.xp_EnumErrorLogs 1'   
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
			SET @SQL='EXEC master.dbo.xp_ReadErrorLog '+CONVERT(NVARCHAR(5),@LogFileID)+', 1, NULL, NULL, N''' + CONVERT(VARCHAR(50),@LastLogDate,121) + ''''   
			--Do not use Linked Server if running locally   
			IF @IsLinked=1   
				SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']'   
		   
			INSERT INTO #Log (LogDate,ProcessInfo,[Text])   
				EXEC (@SQL)   
		   
			/**********************   
			* Log Successful Ping *   
			**********************/   
			UPDATE tServerPingLog   
			SET   
				LastPingSource='ServerLog'   
				,LastPingDate=CURRENT_TIMESTAMP   
			WHERE   
				ServerID=@ServerID   
   
		END --Log File Count   
   
		--Remove Logs that have the same log date as the previously-processed last log date   
		;WITH D AS (SELECT TOP (@LastLogDateCount) * FROM #Log WHERE LogDate=@LastLogDate ORDER BY LogID)   
			DELETE FROM D    
		   
		DELETE FROM #Log WHERE [Text] IS NULL   
   
		UPDATE #Log	SET ProcessInfo=RTRIM(ProcessInfo), [Text]=RTRIM([Text]) --Remove Trailing Spaces   
   
		-- Set Error Number and State   
		UPDATE L   
		SET    
			L.Error=E.Error   
			,L.Severity=E.Severity   
			,L.[State]=E.[State]   
		FROM   
		#Log L    
			OUTER APPLY   
			(   
			SELECT    
				CONVERT(INT,RIGHT(ErrorText,PATINDEX('%[^0-9]%',REVERSE([ErrorText]))-1)) AS [Error]   
				,CONVERT(INT,RIGHT(SeverityText,PATINDEX('%[^0-9]%',REVERSE([SeverityText]))-1)) AS [Severity]   
				,CONVERT(INT,RIGHT(StateText,PATINDEX('%[^0-9]%',REVERSE([StateText]))-1)) AS [State]   
				,*   
			FROM   
				(SELECT    
						Tbl.Col.value('r[1]','VARCHAR(16)') AS ErrorText   
						,Tbl.Col.value('r[2]','VARCHAR(19)') AS SeverityText   
						,REPLACE(Tbl.Col.value('r[3]','VARCHAR(16)'),'.','') AS StateText   
					FROM    
						(SELECT CONVERT(XML,'<r>'+REPLACE([Text],', ','</r>+<r>')+'</r>') AS X)X1    
						CROSS APPLY    
						X.nodes('/') Tbl(Col)   
				) ET   
			) E   
		WHERE    
			L.[Text] LIKE N'Error: %[0-9]%, Severity: %[0-9]%, State: [0-9]%.' AND [Text] NOT LIKE N'%[<>]%'   
   
		  
		--Update Custom Errors, such as Stack Dumps, CDC and Kerberos  
		UPDATE L   
		SET    
			L.Error=CE.Error  
			,L.Severity=CE.Severity  
			,L.[State]=CE.[State]  
		FROM   
			#Log L  
			JOIN tServerLogCustomError CE  
				ON L.[Text] LIKE CE.TextPattern  
		WHERE  
			L.Error IS NULL  
		  
		  
  
		--Mark DBCC CHECKDB Status AS Severity 0 or 99, Error -9, State = Number of Errors  
		/*  
		;WITH A AS(SELECT PATINDEX (N'% found [0-9]%',[Text]) AS FoundErrorMark,* FROM #Log L WHERE [Text] LIKE N'DBCC CHECKDB % found [0-9]% errors and repaired % errors%')  
		,B AS (SELECT RIGHT([Text],DATALENGTH([Text])/2-FoundErrorMark-6) AS FoundErrorRight,* FROM A)  
		,C AS (SELECT CONVERT(INT,LEFT(FoundErrorRight,PATINDEX('%[^0-9]%',FoundErrorRight))) AS ErrorCount,* FROM B)  
		UPDATE C  
		SET   
			C.Error=-9  
			,C.Severity=CASE C.ErrorCount WHEN 0 THEN 0 ELSE 99 END  
			,C.[State]=C.ErrorCount  
		*/  
  
 		--Persist the Log   
		INSERT INTO tServerLog (ServerID, LogDate, ProcessInfo, [Text], Error, Severity, [State], TextCnt)   
		SELECT   
			@ServerID AS ServerID, MAX(LogDate), ProcessInfo, [Text], Error, Severity, [State], COUNT(*) AS TextCnt  
		FROM   
			#Log   
		GROUP BY   
			ProcessInfo, [Text], Error, Severity, [State], CONVERT(DATETIME2(0),LogDate) --Combine same entries, down to the second precision  
		ORDER BY   
			MIN(LogID)  
		  
		--Cycle Error Log if the last entry on the second log file (id=1) is older than a week  
		IF (SELECT LogDate FROM #EnumLOG WHERE LogFileID=1)<=CONVERT(DATE,CURRENT_TIMESTAMP-7)  
		BEGIN  
			SET @SQL='EXEC master.dbo.sp_cycle_errorlog'  
			--Do not use Linked Server if running locally   
			IF @IsLinked=1   
				SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']'  
			EXEC (@SQL)  
		END  
  
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



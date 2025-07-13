USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshDatabase]    Script Date: 7/13/2025 1:59:32 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[pRefreshDatabase] AS 
/********************************************************** 
* Keep Track of All of Databases and Their Confugurations * 
**********************************************************/ 
 
DECLARE @Date DATETIME = CURRENT_TIMESTAMP  
		,@SQL NVARCHAR(MAX) 
		,@ServerID INT 
		,@ServerName NVARCHAR(128) 
		,@IsLinked BIT 
		,@ErrorMessage NVARCHAR(MAX) 
 
IF OBJECT_ID('tempdb..#Database') IS NOT NULL DROP TABLE #Database 
CREATE TABLE #Database ( 
	 ServerDatabaseID INT NOT NULL UNIQUE 
	, DatabaseGUID UNIQUEIDENTIFIER NULL 
	, DatabaseName NVARCHAR(128) PRIMARY KEY CLUSTERED 
	, CompatibilityLevel INT 
	, Status NVARCHAR(128) 
	, Collation NVARCHAR(128) 
	, IsAutoCreateStatistics bit 
	, IsAutoShrink bit 
	, IsAutoUpdateStatistics bit 
	, IsPublished bit 
	, IsSubscribed bit 
	, [Recovery] NVARCHAR(128) 
	, UserAccess NVARCHAR(128) 
	, IsReadOnly BIT 
	, IsAutoClose BIT 
	, CreateDate DATETIME) 
 
IF OBJECT_ID('tempdb..#DatabaseConfiguration') IS NOT NULL DROP TABLE #DatabaseConfiguration  
CREATE TABLE #DatabaseConfiguration  
(  
	ServerDatabaseID INT NOT NULL 
	,DatabaseName NVARCHAR(128) NOT NULL 
	,DatabaseGUID UNIQUEIDENTIFIER NULL 
	,ConfigurationName NVARCHAR(128) NOT NULL 
	,ConfigurationValue SQL_VARIANT NULL  
	,PRIMARY KEY CLUSTERED(DatabaseName, ConfigurationName) 
	,UNIQUE (ServerDatabaseID, ConfigurationName) 
	,UNIQUE (DatabaseGUID, DatabaseName, ConfigurationName)  
)  
 
IF OBJECT_ID ('tempdb..#CheckDB','U') IS NOT NULL DROP TABLE #CheckDB 
CREATE TABLE #CheckDB  
( 
	DatabaseName NVARCHAR(128) PRIMARY KEY CLUSTERED 
	,ErrorCount INT 
	,LogDate DATETIME NOT NULL 
) 
 
IF OBJECT_ID('tempdb..#ServerError') IS NOT NULL DROP TABLE #ServerError 
CREATE TABLE #ServerError 
( 
	ServerID INT PRIMARY KEY CLUSTERED 
	,ErrorMessage NVARCHAR(MAX) 
) 
 
 
/*************************** 
* Loop through all servers * 
***************************/ 
DECLARE cServer CURSOR  
     FOR  
		SELECT  
			ServerID, ServerName, IsLinked 
		FROM  
			tServer  
		WHERE  
			IsSQLServer=1  
			AND Active=1  
			AND EnableServerDBTrack=1 
		ORDER BY  
			ServerID 
 
OPEN cServer    
 
WHILE 1=1 
	BEGIN 
	SET @ErrorMessage=NULL 
 
	FETCH NEXT FROM cServer 
		INTO @ServerID, @ServerName, @IsLinked 
	IF @@FETCH_STATUS<>0 BREAK 
		PRINT @ServerName 
 
	BEGIN TRY 
		TRUNCATE TABLE #Database 
		TRUNCATE TABLE #DatabaseConfiguration 
		TRUNCATE TABLE #CheckDB 
 
		SET @SQL='IF OBJECT_ID(''tempdb..#DB'',''U'') IS NOT NULL DROP TABLE #DB 
		DECLARE @SQL NVARCHAR(MAX) 
				,@SelectColumns NVARCHAR(MAX) 
				,@SelectColumnsVariant NVARCHAR(MAX) 
 
		SELECT DB.*, RS.database_guid INTO #DB FROM master.sys.databases DB JOIN master.sys.database_recovery_status RS ON DB.database_id=RS.database_id 
 
		SELECT  
			@SelectColumns=ISNULL(@SelectColumns+'','','''')+''[''+C.name+'']''  
			,@SelectColumnsVariant=ISNULL(@SelectColumnsVariant+'','','''')+''CONVERT(SQL_VARIANT,[''+C.name+'']) AS [''+C.name+'']'' 
		FROM  
			tempdb.sys.columns C  
		WHERE  
			C.[object_id]=OBJECT_ID(''tempdb..#DB'',''U'') 
			--AND C.name NOT IN (''database_id'',''name'') 
 
		SET @SQL=''SELECT ServerDatabaseID, DatabaseGUID, DatabaseName, ConfigruationName, ConfigurationValue 
		FROM 
		(SELECT database_id AS ServerDatabaseID, database_guid AS DatabaseGUID, [name] AS DatabaseName, ''+@SelectColumnsVariant+'' FROM #DB) p 
		UNPIVOT 
		(ConfigurationValue FOR ConfigruationName IN (''+@SelectColumns+'')) AS Unpvt'' 
 
		EXEC(@SQL)' 
 
		IF @IsLinked=1 
		SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']' 
		 
		INSERT INTO #DatabaseConfiguration (ServerDatabaseID, DatabaseGUID, DatabaseName, ConfigurationName, ConfigurationValue) 
			EXEC (@SQL) 
 
		;WITH DB AS ( 
		SELECT  
			[database_id] 
			,[database_guid] 
			,[name] 
			,[compatibility_level] 
			,[state_desc] 
			,[collation_name] 
			,[is_auto_create_stats_on] 
			,[is_auto_shrink_on] 
			,[is_auto_update_stats_on] 
			,[is_published] 
			,[is_subscribed] 
			,[recovery_model_desc] 
			,[user_access_desc] 
			,[is_read_only] 
			,[is_auto_close_on] 
			,[create_date]  
		FROM 
		(SELECT  
			DatabaseName 
			,ConfigurationName 
			,CONVERT(NVARCHAR(128),ConfigurationValue) AS ConfigurationValue  
		FROM  
			#DatabaseConfiguration) AS Src 
		PIVOT 
		(MAX(ConfigurationValue)  
		FOR ConfigurationName IN ( 
			[database_id] 
			,[database_guid] 
			,[name] 
			,[compatibility_level] 
			,[state_desc] 
			,[collation_name] 
			,[is_auto_create_stats_on] 
			,[is_auto_shrink_on] 
			,[is_auto_update_stats_on] 
			,[is_published] 
			,[is_subscribed] 
			,[recovery_model_desc] 
			,[user_access_desc] 
			,[is_read_only] 
			,[is_auto_close_on] 
			,[create_date] 
			)) AS Pvt 
		) 
		INSERT INTO #Database (ServerDatabaseID, DatabaseGUID, DatabaseName, CompatibilityLevel, Status, Collation, IsAutoCreateStatistics, IsAutoShrink, IsAutoUpdateStatistics, IsPublished, IsSubscribed, Recovery, UserAccess, IsReadOnly, IsAutoClose, CreateDate) 
		SELECT  
			DB.database_id 
			,DB.database_guid AS DatabaseGUID 
			,DB.name AS Name  
			,DB.compatibility_level AS CompatabilityLevel  
			,DB.[state_desc] AS [Status] 
			,DB.collation_name AS [Collation] 
			,DB.is_auto_create_stats_on [IsAutoCreateStatistics] 
			,DB.is_auto_shrink_on AS  [IsAutoShrink] 
			,DB.is_auto_update_stats_on AS [IsAutoUpdateStatistics] 
			,DB.is_published AS [IsPublished] 
			,DB.is_subscribed AS [IsSubscribed] 
			,DB.recovery_model_desc AS [Recovery] 
			,DB.user_access_desc AS [UserAccess] 
			,DB.is_read_only AS [IsReadOnly] 
			,DB.is_auto_close_on AS [ISAutoClose] 
			,DB.create_date AS CreateDate 
		FROM  DB 
		 
		-- Update NULL Database GUID - Database GUID is reported as NULL if the database is NOT Online (i.e. Restoring, Offline); Assume it has not changed - use previosly stored GUID if ServerDatabaseID and Name have not changed. 
		UPDATE D 
		SET D.DatabaseGUID=DB.DatabaseGUID 
		FROM #Database D 
			JOIN tDatabase DB 
			ON D.ServerDatabaseID = DB.ServerDatabaseID 
				AND D.DatabaseName = DB.DatabaseName  
		WHERE 
			DB.ServerID=@ServerID 
			AND D.DatabaseGUID IS NULL  
			AND D.[Status] NOT IN ('ONLINE') 
		 
		--Do the same for Database Configuration 
		UPDATE DC 
		SET DC.DatabaseGUID=D.DatabaseGUID 
		FROM 
			#DatabaseConfiguration DC 
			JOIN #Database D 
				ON DC.DatabaseName=D.DatabaseName 
		WHERE 
			DC.DatabaseGUID IS NULL 
 
		-- Rename Renames 
		UPDATE DB 
		SET DB.DatabaseName=D.DatabaseName 
		FROM tDatabase DB 
		JOIN #Database D 
			ON D.DatabaseGUID = DB.DatabaseGUID 
			AND D.ServerDatabaseID=DB.ServerDatabaseID --It is a rename only if the Instance-side Database ID has not changed; otherwise it could be a copy of the database 
		WHERE	 
			DB.ServerID=@ServerID 
			AND D.DatabaseName <> DB.DatabaseName 
 
		-- Incactivate offline or missing databases 
		UPDATE DB 
		SET Active = 0 
		FROM  
			tDatabase DB 
			LEFT JOIN #Database D 
			ON D.DatabaseGUID = DB.DatabaseGUID 
				AND D.DatabaseName = DB.DatabaseName 
				AND D.[Status] IN ('ONLINE') 
		WHERE  
			DB.ServerID = @ServerID 
			AND DB.Active = 1 
			AND D.DatabaseName IS NULL  
		 
		-- Add new Databases 
		INSERT INTO tDatabase 
		(ServerID, ServerDatabaseID, DatabaseGUID, DatabaseName, BackupStrategyID, EnableIndexMaintenance, ReindexStrategyID, EnableStatisticsMaintenance, StatisticsMaintenanceStrategyID, EnableSpaceMaintenance, EnableBackup, EnableRestore, EnableRestoreKillSession, EnableLogQueryHistory, Active) 
		SELECT  
			@ServerID AS ServerID 
			,D.ServerDatabaseID 
			,D.DatabaseGUID 
			,D.DatabaseName 
			,S.DefaultBackupStrategyID AS BackupStrategyID 
			,S.DefaultEnableIndexMaintenance AS EnableIndexMaintenance 
			,S.DefaultReindexStrategyID 
			,S.DefaultEnableStatisticsMaintenance AS EnableStatisticsMaintenance 
			,S.DefaultStatisticsMaintenanceStrategyID AS StatisticsMaintenanceStrategyID 
			,S.DefaultEnableSpaceMaintenance AS EnableSpaceMaintenance 
			,S.DefaultEnableBackup AS EnableBackup 
			,S.DefaultEnableRestore AS EnableRestore 
			,S.DefaultEnableRestoreKillSession AS EnableRestoreKillSession 
			,S.DefaultEnableLogQueryHistory AS EnableLogQueryHistory 
			, 1 AS Active 
		FROM  
			#Database D 
		JOIN tServer S 
			ON S.ServerID=@ServerID 
		LEFT JOIN tDatabase DB 
			ON DB.ServerID=@ServerID 
				AND D.DatabaseGUID = DB.DatabaseGUID 
				AND D.DatabaseName = DB.DatabaseName 
		WHERE 
			DB.DatabaseName IS NULL  
			AND D.DatabaseGUID IS NOT NULL --Database GUID will be null for newly-found Databases that are not Online 
 
		-- ACTIVATE MATCHED 
		UPDATE DB 
		SET Active = 1 
		FROM tDatabase DB 
			JOIN #Database D 
			ON D.DatabaseGUID = DB.DatabaseGUID 
				AND D.DatabaseName = DB.DatabaseName 
				AND D.[Status]='ONLINE' 
		WHERE  
			DB.ServerID = @ServerID 
			AND DB.Active = 0 
 
		/********************** 
		* DBCC CHECKDB Metric * 
		**********************/ 
		;WITH  
		A AS ( 
			SELECT PATINDEX (N'% found [0-9]%',L.[Text]) AS FoundErrorMark, SUBSTRING([Text],15,CHARINDEX(N')',[Text])-15) AS DatabaseName, L.Text, L.LogDate 
				FROM tServerLog L  
			WHERE  
				L.ServerID=@ServerID 
				-- AND L.Error=-9 (NOT required for SQL 2017) - Deepak Adhya
				AND L.LogDate>=CURRENT_TIMESTAMP-60 
				AND [Text] LIKE N'DBCC CHECKDB % found [0-9]% errors and repaired % errors%' 
		) 
		,B AS (SELECT RIGHT([Text],DATALENGTH([Text])/2-FoundErrorMark-6) AS FoundErrorRight,* FROM A) 
		,C AS (SELECT CONVERT(INT,LEFT(FoundErrorRight,PATINDEX('%[^0-9]%',FoundErrorRight))) AS ErrorCount,* FROM B) 
		,D AS (SELECT *, ROW_NUMBER() OVER(PARTITION BY DatabaseName ORDER BY LogDate DESC) RN FROM C) 
		--Store last CHECKDB results from the server log, going back 60 days 
		INSERT INTO #CheckDB (DatabaseName, ErrorCount, LogDate) 
		SELECT  
			DatabaseName, ErrorCount, LogDate 
		FROM D  
		WHERE  
			RN=1  
 
		--Store CHECKDB results in Database Configuration 
		--If no data found, store dates as 0 and counts as -1 
		--Look at previous configuration values if none are found in the server error log 
		;WITH CHK AS( 
		SELECT 
			D.ServerDatabaseID 
			,D.DatabaseName 
			,D.DatabaseGUID 
			,COALESCE(CDB.ErrorCount, CONVERT(INT,(DCE.ConfigurationValue)),-1) AS CHECKDB_Errors 
			,COALESCE(CDB.LogDate,CONVERT(DATETIME,DCD.ConfigurationValue),0) AS CHECKDB_Date 
			,D.CreateDate 
		FROM  
			#Database D  
			JOIN tDatabase DB  
				ON DB.ServerID=@ServerID 
				AND DB.ServerDatabaseID NOT IN (2) --tempdb 
				AND D.DatabaseName=DB.DatabaseName 
				AND D.DatabaseGUID=DB.DatabaseGUID 
			LEFT JOIN #CheckDB CDB  
				ON DB.DatabaseName=CDB.DatabaseName 
			LEFT JOIN tDatabaseConfiguration DCD --Find last checkdb values in case none are found in the server log above 
				ON DCD.DatabaseID=DB.DatabaseID 
				AND DCD.ConfigurationName=N'CHECKDB_Date' 
				AND DCD.EndDate IS NULL 
				AND CONVERT(DATETIME,DCD.ConfigurationValue)>=D.CreateDate --Ignore any CheckDB values prior to DB Creation date 
			LEFT JOIN tDatabaseConfiguration DCE 
				ON DCE.DatabaseID=DB.DatabaseID 
				AND DCE.ConfigurationName=N'CHECKDB_Errors' 
				AND DCE.EndDate IS NULL 
				AND DCD.ConfigurationName IS NOT NULL --Only pull error counts if error date exists 
		) 
		INSERT INTO #DatabaseConfiguration (ServerDatabaseID, DatabaseName, DatabaseGUID, ConfigurationName, ConfigurationValue) 
		SELECT ServerDatabaseID, DatabaseName, DatabaseGUID, ConfigrurationName, ConfigurationValue 
		FROM 
		(SELECT ServerDatabaseID, DatabaseName, DatabaseGUID, CONVERT(SQL_VARIANT,[CHECKDB_Errors]) AS [CHECKDB_Errors], CONVERT(SQL_VARIANT,[CHECKDB_Date]) AS [CHECKDB_Date] FROM CHK) P 
		UNPIVOT 
		(ConfigurationValue FOR ConfigrurationName IN ([CHECKDB_Errors],[CHECKDB_Date])) AS Unpvt 
 
		/******************************* 
		* Store Database Configuration *  
		*******************************/  
		--Use Temp Table to temporary store values to insert due to SQL2012 limitations  
		IF OBJECT_ID('tempdb..#DatabaseConfigurationTemp') IS NOT NULL DROP TABLE #DatabaseConfigurationTemp  
		SELECT TOP 0 * INTO #DatabaseConfigurationTemp FROM tDatabaseConfiguration  
		BEGIN TRAN  
			;WITH   
			Tgt AS( 
				SELECT  
					DC.* 
				FROM  
					tDatabaseConfiguration DC 
					JOIN tDatabase D  
						ON D.ServerID=@ServerID 
						AND D.DatabaseID=DC.DatabaseID 
						--AND D.Active=1  
				WHERE 
					DC.EndDate IS NULL)  
			,Src AS( 
				SELECT  
					D.DatabaseID 
					,DC.ConfigurationName 
					,DC.ConfigurationValue 
				FROM  
					#DatabaseConfiguration DC 
					JOIN tDatabase D  
						ON D.ServerID=@ServerID 
						AND D.DatabaseName=DC.DatabaseName 
						AND D.DatabaseGUID=DC.DatabaseGUID --Includes inactive databases 
			)  
  
 			--Insert new values records that had its values changed (End Date updated to Timestamp, Source Server ID is not null)  
			--Use temp table because direct insert only works in SQL2014  
			INSERT INTO #DatabaseConfigurationTemp (DatabaseID, ConfigurationName, StartDate, EndDate, ConfigurationValue)  
			SELECT DatabaseID, ConfigurationName, @Date AS StartDate, NULL AS EndDate, ConfigurationValue  
			FROM  
			(  
				MERGE Tgt  
				USING Src  
					ON Tgt.DatabaseID=Src.DatabaseID AND Tgt.ConfigurationName=Src.ConfigurationName  
				--Any new configuration names  
				WHEN NOT MATCHED   
					THEN INSERT (DatabaseID,ConfigurationName,ConfigurationValue,StartDate,EndDate) VALUES (DatabaseID,ConfigurationName,ConfigurationValue,@Date,NULL)  
				--Configuration no longer exists and no error reported 
				WHEN NOT MATCHED BY SOURCE AND @ErrorMessage IS NULL 
					THEN UPDATE SET Tgt.EndDate=@Date  
				--Configuration values changed; Source Database ID is not null in this case  
				WHEN MATCHED AND EXISTS (SELECT Tgt.ConfigurationValue EXCEPT SELECT Src.ConfigurationValue) 
					THEN UPDATE SET Tgt.EndDate=@Date  
				OUTPUT $ACTION AS [Action], Src.*  
			) Mrg  
			--See Insert comment above  
			WHERE Mrg.[Action]='UPDATE' AND Mrg.DatabaseID IS NOT NULL  
			;  
			INSERT INTO tDatabaseConfiguration (DatabaseID, ConfigurationName, StartDate, EndDate, ConfigurationValue)  
				SELECT DatabaseID, ConfigurationName, StartDate, EndDate, ConfigurationValue FROM #DatabaseConfigurationTemp  
		COMMIT  
 
	END TRY 
	BEGIN CATCH 
		IF @@TRANCOUNT>0 ROLLBACK 
		SET @ErrorMessage = @ServerName + ': ' + ERROR_MESSAGE() 
		INSERT INTO #ServerError (ServerID, ErrorMessage) OUTPUT INSERTED.* VALUES (@ServerID, @ErrorMessage) 
		 
	END CATCH 
END		 
CLOSE cServer 
DEALLOCATE cServer 
 
--Deactivate offline servers 
UPDATE DB 
SET DB.Active=0 
FROM 
	tDatabase DB 
	JOIN tServer S 
		ON DB.ServerID=S.ServerID 
WHERE 
	S.IsSQLServer=1  
	AND S.Active=0  
	AND S.EnableServerDBTrack=1 
	AND DB.Active=1 
 
--Disable Backups and Maintenance for tempdb and model system databases 
UPDATE tDatabase 
SET 
	 BackupStrategyID=0 
	,EnableBackup=0 
	,EnableIndexMaintenance=0 
	,ReindexStrategyID=NULL 
	,EnableLogQueryHistory=0 
	,EnableRestore=0 
	,EnableRestoreKillSession=0 
	,EnableSpaceMaintenance=0 
	,EnableStatisticsMaintenance=0 
WHERE  
	DatabaseName IN ('tempdb','model') 
	--AND Active=1 
	AND  
	BackupStrategyID 
	|EnableBackup 
	|EnableIndexMaintenance 
	|EnableLogQueryHistory 
	|EnableRestore 
	|EnableRestoreKillSession 
	|EnableSpaceMaintenance 
	|EnableStatisticsMaintenance 
	=CONVERT(BIT,1) 
 
/***************** 
* ERROR HANDLING * 
*****************/ 
SET @ErrorMessage=NULL 
SELECT  
	@ErrorMessage=ISNULL(@ErrorMessage+';'+CHAR(13),'')+ SE.ErrorMessage 
FROM  
	#ServerError SE 
WHERE 
	SE.ErrorMessage IS NOT NULL 
 
IF @ErrorMessage IS NOT NULL 
BEGIN 
	RAISERROR (@ErrorMessage,18,1) 
END 

GO



USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshBackupSet]    Script Date: 7/3/2025 12:06:08 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[pRefreshBackupSet] @ServerName NVARCHAR (255)=NULL 
/*************************************************** 
* Keep track of all database files and their sizes * 
***************************************************/ 
AS 
SET XACT_ABORT ON; 
SET LOCK_TIMEOUT 60000; 
DECLARE @SQL NVARCHAR(MAX) 
		,@ServerID INT 
		,@IsLinked BIT 
		,@LastBackupFinishDate DATETIME 
		,@NewBackupFinishDate DATETIME 
		,@LastRestoreHistoryID INT 
		,@ErrorMessage NVARCHAR(MAX) 
 
IF OBJECT_ID('tempdb..#BFD','U') IS NOT NULL DROP TABLE #BFD 
CREATE TABLE #BFD (BackupFinishDate DATETIME PRIMARY KEY CLUSTERED WITH (IGNORE_DUP_KEY=ON)) 
 
IF OBJECT_ID('tempdb..#ServerError') IS NOT NULL DROP TABLE #ServerError 
CREATE TABLE #ServerError 
( 
	ServerID INT PRIMARY KEY CLUSTERED 
	,ErrorMessage NVARCHAR(MAX) 
) 
		 
---------- Define / Begin Server Loop ---------- 
DECLARE curServers CURSOR  
     FOR  
		SELECT ServerID, ServerName, IsLinked from DBA.dbo.tServer 
		WHERE 
		    IsSQLServer = 1 AND Active = 1 AND EnableServerDBTrack=1 
			AND (@ServerName IS NULL OR ServerName=@ServerName)
		ORDER BY 
			ServerID 
    OPEN curServers 
 
WHILE 1=1 
BEGIN 
    FETCH NEXT FROM curServers 
	INTO @ServerID, @ServerName, @IsLinked 
	IF @@FETCH_STATUS<>0 BREAK 
--	PRINT '--------------------' 
	RAISERROR ('%s', 0, 1, @ServerName) WITH NOWAIT 
--	PRINT '--------------------' 
 
	SELECT @LastBackupFinishDate=ISNULL(MAX(BackupFinishDate),0) FROM tBackupSet WHERE ServerID=@ServerID 
	SELECT @LastRestoreHistoryID=ISNULL(MAX(ServerRestoreHistoryID),0) FROM tBackupSetRestore WHERE ServerID=@ServerID 
 
	BEGIN TRY 
		/*************** 
		* Backup Files * 
		***************/ 
		TRUNCATE TABLE #BFD 
		SET @SQL= 
		'SELECT 
			@ServerID AS ServerID 
			,[database_name] AS ServerDatabaseName 
			,backup_set_id AS ServerBackupSetID 
			,backup_set_uuid AS ServerBackupSetUUID 
			,database_guid AS DatabaseGUID 
			,family_guid AS DatabaseFamilyGUID 
			,backup_start_date AS BackupStartDate 
			,backup_finish_date AS BackupFinishDate 
			,[Type] AS BackupType 
			,compressed_backup_size AS CompressedBackupSize 
			,backup_size AS BackupSize 
			,[name] AS BackupName 
			,[user_name] AS UserName 
			,software_major_version AS SoftwareMajorVersion 
			,software_minor_version AS SoftwareMinorVersion 
			,software_build_version AS SoftwareBuildVersion 
			,time_zone AS TimeZone 
			,first_lsn AS FirstLSN 
			,last_lsn AS LastLSN 
			,checkpoint_lsn AS CheckpointLSN 
			,database_backup_lsn AS DatabaseBackupLSN 
			,differential_base_lsn AS DifferentialBaseLSN 
			,differential_base_guid DifferentialBaseGUID 
			,first_recovery_fork_guid AS FirstRecoveryForkGUID 
			,last_recovery_fork_guid AS LastRecoveryForkGUID 
			,fork_point_lsn AS ForkPointLSN 
			,is_damaged AS IsDamaged 
			,has_backup_checksums AS IsChecksum 
			,is_copy_only AS IsCopyOnly 
			,is_readonly AS IsReadOnly 
			,begins_log_chain AS IsBeginsLogChain 
			,has_bulk_logged_data AS IsBulkLoggedData 
		FROM [[ServerName]].msdb.dbo.BackupSet WITH (NOLOCK) 
		WHERE backup_finish_date>@LastBackupFinishDate AND backup_finish_date<=CURRENT_TIMESTAMP+1' 
 
		IF @IsLinked=1 
			SET @SQL=REPLACE(@SQL,'[ServerName]',@ServerName) 
		ELSE 
			SET @SQL=REPLACE(@SQL,'[[ServerName]].','') 
		 
		SET @SQL= 
		'INSERT INTO tBackupSet 
			(ServerID 
			,ServerDatabaseName 
			,ServerBackupSetID 
			,ServerBackupSetUUID 
			,DatabaseGUID 
			,DatabaseFamilyGUID 
			,BackupStartDate 
			,BackupFinishDate 
			,BackupType 
			,CompressedBackupSize 
			,BackupSize 
			,BackupName 
			,UserName 
			,SoftwareMajorVersion 
			,SoftwareMinorVersion 
			,SoftwareBuildVersion 
			,TimeZone 
			,FirstLSN 
			,LastLSN 
			,CheckpointLSN 
			,DatabaseBackupLSN 
			,DifferentialBaseLSN 
			,DifferentialBaseGUID 
			,FirstRecoveryForkGUID 
			,LastRecoveryForkGUID 
			,ForkPointLSN 
			,IsDamaged 
			,IsChecksum 
			,IsCopyOnly 
			,IsReadOnly 
			,IsBeginsLogChain 
			,IsBulkLoggedData 
			) 
		OUTPUT INSERTED.BackupFinishDate INTO #BFD (BackupFinishDate)' 
		+@SQL 
	 
		EXEC sp_executesql @SQL,N'@ServerID INT, @LastBackupFinishDate DATETIME', @ServerID=@ServerID, @LastBackupFinishDate=@LastBackupFinishDate 
		 
		/****************** 
		* Restore History * 
		******************/ 
		SET @SQL= 
		'INSERT INTO tBackupSetRestore 
			([ServerID] 
			  ,[ServerRestoreHistoryID] 
			  ,[RestoreDate] 
			  ,[ServerDestinationDatabaseName] 
			  ,[UserName] 
			  ,[ServerBackupSetID] 
			  ,[RestoreType] 
			  ,[Replace] 
			  ,[Recovery] 
			  ,[Restart] 
			  ,[StopAt] 
			  ,[DeviceCount] 
			  ,[StopAtMarkName] 
			  ,[StopBefore] 
			) 
		SELECT 
			@ServerID AS ServerID 
			,restore_history_id AS ServerRestoreHistoryID 
			,restore_date AS RestoreDate 
			,destination_database_name AS ServerDestinationDatabaseName 
			,[user_name] AS UserName 
			,backup_set_id AS ServerBackupSetID 
			,restore_type AS [RestoreType] 
			,[replace] AS [Replace] 
			,[recovery] AS [Recovery] 
			,[restart] AS [Restart] 
			,stop_at AS [StopAt] 
			,device_count AS [DeviceCount] 
			,stop_at_mark_name AS [StopAtMarkName] 
			,stop_before AS [StopBefore] 
		FROM  
			[[ServerName]].msdb.dbo.restorehistory RH 
		WHERE 
			RH.restore_history_id>@LastRestoreHistoryID 
			' 
		IF @IsLinked=1 
			SET @SQL=REPLACE(@SQL,'[ServerName]',@ServerName) 
		ELSE 
			SET @SQL=REPLACE(@SQL,'[[ServerName]].','') 
 
		EXEC sp_executesql @SQL,N'@ServerID INT, @LastRestoreHistoryID INT', @ServerID=@ServerID, @LastRestoreHistoryID=@LastRestoreHistoryID 
 
		/************************************************* 
		* If no new backups found, go to the next server * 
		*************************************************/ 
		SELECT @NewBackupFinishDate=MAX(BackupFinishDate) FROM #BFD 
		IF @NewBackupFinishDate IS NULL CONTINUE 
 
		/*************** 
		* Backup Files * 
		***************/ 
		SET @SQL= 
		'SELECT 
			@ServerID AS ServerID 
			,BS.backup_set_uuid AS ServerBackupSetUUID 
			,BMF.family_sequence_number AS FamilySequenceNumber 
			,BMF.mirror AS Mirror 
			,BMF.physical_device_name AS PhysicalDeviceName 
			,BMF.device_type AS DeviceType 
			,BMF.physical_block_size AS PhysicalBlockSize 
			FROM  
			[[ServerName]].msdb.dbo.backupset BS WITH (NOLOCK) 
			JOIN [[ServerName]].msdb.dbo.backupmediafamily BMF WITH (NOLOCK) ON BS.media_set_id=BMF.media_set_id 
		WHERE 
			BS.backup_finish_date>@LastBackupFinishDate 
			AND BS.backup_finish_date<=@NewBackupFinishDate 
			' 
		IF @IsLinked=1 
			SET @SQL=REPLACE(@SQL,'[ServerName]',@ServerName) 
		ELSE 
			SET @SQL=REPLACE(@SQL,'[[ServerName]].','') 
 
		SET @SQL= 
		'INSERT INTO tBackupSetMedia 
			(ServerID 
			  ,ServerBackupSetUUID 
			  ,FamilySequenceNumber 
			  ,Mirror 
			  ,PhyicalDeviceName 
			  ,DeviceType 
			  ,PhysicalBlockSize 
			)' 
		+@SQL 
 
		EXEC sp_executesql @SQL,N'@ServerID INT, @LastBackupFinishDate DATETIME, @NewBackupFinishDate DATETIME', @ServerID=@ServerID, @LastBackupFinishDate=@LastBackupFinishDate, @NewBackupFinishDate=@NewBackupFinishDate 
 
	END TRY 
	BEGIN CATCH 
		SET @ErrorMessage = @ServerName + ': ' + ERROR_MESSAGE() 
		INSERT INTO #ServerError (ServerID, ErrorMessage) VALUES (@ServerID, @ErrorMessage) 
	END CATCH 
 
END 
CLOSE curServers 
DEALLOCATE curServers 
---------- End Server Loop ---------- 
 
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
IF @@ROWCOUNT>0 
	SELECT * FROM #ServerError 
 
IF @ErrorMessage IS NOT NULL 
BEGIN 
	RAISERROR (@ErrorMessage,18,1) 
END 
 

GO



USE [msdb]
GO

/****** Object:  Job [[DBMonitor] Manage Blocking]    Script Date: 7/22/2025 4:11:13 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [DBA-Maintenance]    Script Date: 7/22/2025 4:11:13 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'[DBMonitor] Manage Blocking', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Send alerts on blocking.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'DBA ALERT', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Manage Blocking]    Script Date: 7/22/2025 4:11:13 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Manage Blocking', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/**********************************************************
* Monitor for blocking session activity                   *
* And send-out notifications if anything has been blocked *
* For longer than 15 seconds                              *
***********************************************************/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET LOCK_TIMEOUT 15000;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE 
		@BlockThresholdSec INT=15
		,@BlockCountKillThreshold INT=15
		,@SQL NVARCHAR(MAX)
		,@Body NVARCHAR(MAX)
		,@Subject VARCHAR(MAX)
		,@Recipients VARCHAR (255)
		,@FromAddress VARCHAR(255)
		,@ProfileName NVARCHAR(128)
		,@ServerName NVARCHAR(128)
		,@SessionID INT
		,@ConnectionID UNIQUEIDENTIFIER
		,@DatabaseID INT
		,@DatabaseName NVARCHAR(128)
		,@ObjectID_CSV VARCHAR(MAX)
		,@IsLinked BIT
		,@ErrorMessage NVARCHAR(MAX)
		,@BlockCount INT
		,@KillCount INT
		,@Cnt INT
		

DECLARE @InputBuffer TABLE ([EventType] NVARCHAR(30), [Parameters] SMALLINT, [EventInfo] NVARCHAR(4000))

IF OBJECT_ID(''tempdb.dbo.#Block'') IS NOT NULL DROP TABLE #Block
CREATE TABLE #Block(
	SessionID INT PRIMARY KEY,
	ConnectionID UNIQUEIDENTIFIER,
	BlockSessionID INT,
	ParentBlockSessionID INT,
	BlockLevel INT,
	Command VARCHAR(255),
	RunTime VARCHAR(255),
	WaitTime VARCHAR(255),
	WaitType VARCHAR(255),
	WaitResource NVARCHAR(256),
	ResourceDesc NVARCHAR(1024),
	SQLStart INT,
	SQLEnd INT,
	HostName NVARCHAR(128),
	ProgramName NVARCHAR(128),
	DatabaseID INT,
	ObjectID INT,
	LoginName NVARCHAR(255),
	TransactionType INT,
	SQLText NVARCHAR(MAX),
	InputBuffer NVARCHAR(4000),
	IsUserProcess BIT DEFAULT(1),
	IsKilled BIT DEFAULT(0),
	UNIQUE CLUSTERED (ParentBlockSessionID, BlockLevel, BlockSessionID,SessionID)
)

IF OBJECT_ID(''tempdb.dbo.#Object'') IS NOT NULL DROP TABLE #Object
CREATE TABLE #Object(
	DatabaseID INT
	,ObjectID INT
	,ObjectName NVARCHAR(128)
	,PRIMARY KEY CLUSTERED (DatabaseID, ObjectID)
	)



SET @ErrorMessage=NULL
SET @ServerName = @@ServerName
SET @Body=NULL

TRUNCATE TABLE #Block

/*****************
* Get Exec Times *
*****************/
SET @BlockCount=NULL
BEGIN TRY
	INSERT INTO #Block

	SELECT 
		ES.session_id
		,EC.connection_id
		,ER.blocking_session_id AS BlockID
		,ER.blocking_session_id AS ParentBlockID
		,1 AS BlockLevel
		,ER.command
		,ISNULL(CONVERT(VARCHAR(10),NULLIF(DATEDIFF(DAY,ES.last_request_start_time,CURRENT_TIMESTAMP),0))+''d:'','''') + CONVERT(VARCHAR(50),CURRENT_TIMESTAMP-ES.last_request_start_time,108)+CASE WHEN ER.session_id IS NULL THEN ''*'' ELSE '''' END AS RunTime
		--,ER.wait_time
		,CASE WHEN ER.wait_time<=0 THEN ''--'' ELSE '''' END + ISNULL(CONVERT(VARCHAR(10),NULLIF(DATEDIFF(D,0,DATEADD(MS,ABS(ER.wait_time),0)),0))+''d:'','''') + CONVERT(VARCHAR(50),DATEADD(MS,ABS(ER.wait_time),0),108) AS WaitTime
		,ER.wait_type
		,ER.wait_resource
		,WT.resource_description
		,ER.statement_start_offset
		,ER.statement_end_offset
		,ES.host_name
		,ES.program_name
		,ST.dbid
		,ST.objectid
		,ES.original_login_name
		,TA.transaction_type
		,ST.text
		,NULL AS InputBuffer
		,ES.is_user_process
		,0 AS IsKilled
	FROM 
		sys.dm_exec_sessions ES WITH (NOLOCK)
		LEFT JOIN sys.dm_exec_requests ER WITH (NOLOCK) ON ES.session_id=ER.session_id AND ER.session_id>50
		LEFT JOIN sys.dm_exec_connections EC WITH (NOLOCK) on ES.session_id=EC.session_id AND EC.parent_connection_id IS NULL
		LEFT JOIN sys.dm_tran_session_transactions TS  WITH (NOLOCK) ON TS.session_id=ES.session_id
		LEFT JOIN sys.dm_tran_active_transactions TA  WITH (NOLOCK) ON TS.transaction_id=TA.transaction_id
		LEFT JOIN sys.dm_os_waiting_tasks WT WITH (NOLOCK) ON ER.session_id=WT.session_id AND ER.task_address=WT.waiting_task_address
		LEFT JOIN (SELECT DISTINCT ER2.blocking_session_id FROM sys.dm_exec_requests ER2 WITH (NOLOCK) WHERE ER2.blocking_session_id>0 AND ER2.wait_time>=1000*@BlockThresholdSec) RB ON ES.session_id=RB.blocking_session_id

		OUTER APPLY sys.dm_exec_sql_text(ISNULL(ER.sql_handle, EC.most_recent_sql_handle)) ST 
	WHERE 
		(
			(ES.session_id>50 AND ER.blocking_session_id>0 AND ER.wait_time>=1000*@BlockThresholdSec)
			OR 
			RB.blocking_session_id IS NOT NULL
		)
	
	--Get Rid of IntelliSence
	DELETE FROM #Block WHERE ProgramName LIKE ''%Microsoft SQL Server Management Studio - Transact-SQL IntelliSense%''
	--Get Rid of Parent Sessions w/o blocks
	DELETE FROM #Block WHERE (BlockSessionID=0 OR BlockSessionID IS NULL) AND SessionID NOT IN (SELECT B2.BlockSessionID FROM #Block B2 WHERE B2.BlockSessionID>0)

	SELECT @BlockCount=COUNT(*) FROM #Block WHERE BlockSessionID>0
END TRY
BEGIN CATCH
	SET @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'''') + ''[''+ @ServerName +''] - '' + ERROR_MESSAGE()
END CATCH

IF @BlockCount>0
BEGIN
	/***************************
	* Get Session Input Buffer *
	***************************/
	DECLARE cInputBuffer CURSOR FOR
		SELECT SessionID, ConnectionID FROM #Block ORDER BY SessionID

	OPEN cInputBuffer
	WHILE 1=1
	BEGIN
		FETCH NEXT FROM cInputBuffer INTO @SessionID, @ConnectionID
		IF @@FETCH_STATUS<>0 BREAK
		SET @SQL=''
		SET LOCK_TIMEOUT 15000;
		SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
		DBCC INPUTBUFFER (''+CONVERT(VARCHAR(5),@SessionID)+'')''
		DELETE FROM @InputBuffer
		BEGIN TRY
			IF EXISTS (SELECT 1 FROM sys.dm_exec_connections WHERE connection_id=@ConnectionID)
			BEGIN
				INSERT INTO @InputBuffer ([EventType],[Parameters],[EventInfo])
					EXEC (@SQL)
				UPDATE #Block SET InputBuffer=(SELECT TOP 1 IB.[EventInfo] FROM @InputBuffer IB) WHERE SessionID=@SessionID 
			END
		END TRY
		BEGIN CATCH
			SET @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'''') + ''[''+ @ServerName +''] - '' + ERROR_MESSAGE()
		END CATCH

	END
	CLOSE cInputBuffer
	DEALLOCATE cInputBuffer
	
	
	
	/*************************************
	* Recursively update parent block id *
	*************************************/
	SET @Cnt=1
	UPDATE 
		#Block
	SET 
		ParentBlockSessionID=SessionID, BlockLevel=0
	WHERE 
		BlockSessionID=0 OR BlockSessionID IS NULL
	WHILE @Cnt<@BlockCount
	BEGIN
		SET @Cnt=@Cnt+1
		UPDATE B1
		SET 
			ParentBlockSessionID=B2.BlockSessionID,
			B1.BlockLevel=B1.BlockLevel+1
		FROM 
			#Block B1
			JOIN #Block B2 ON B1.ParentBlockSessionID=B2.SessionID
		WHERE
			B2.BlockSessionID>0
		IF @@ROWCOUNT=0 BREAK
	END

	/*******************
	* Get Object Names *
	*******************/
	BEGIN TRY
		DECLARE cDatabase CURSOR FOR
			SELECT 
				D.database_id AS DatabaseID
				,D.name AS DatabaseName
				,STUFF(
					(SELECT '','' + CONVERT(VARCHAR(50),objectid)
					FROM 
						#Block B2
					WHERE 
						D.database_id = B2.DatabaseID
					FOR XML PATH(''''),TYPE).value(''.'',''VARCHAR(MAX)''),1,1,'''') AS ObjectID_CSV
			FROM
			sys.databases D WITH (NOLOCK)
			WHERE 
				D.state_desc=''ONLINE''			
				AND D.database_id IN (SELECT B1.DatabaseID FROM #Block B1)
			OPEN cDatabase
		WHILE 1=1
		BEGIN
			FETCH NEXT FROM cDatabase 
				INTO @DatabaseID, @DatabaseName, @ObjectID_CSV
			IF @@FETCH_STATUS<>0 BREAK --End Loop
			SET @SQL=''SELECT ''+CONVERT(NVARCHAR(10),@DatabaseID)+'' AS DatabaseID, O.object_id, O.name FROM [''+@DatabaseName+''].sys.objects O WITH (NOLOCK) WHERE O.object_id IN (''+@ObjectID_CSV+'')''
			
			INSERT INTO #Object (DatabaseID, ObjectID, ObjectName)
				EXEC (@SQL)
		END
		CLOSE cDatabase
		DEALLOCATE cDatabase
	END TRY
	BEGIN CATCH
		SET @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'''') + ''[''+ @ServerName +''] - '' + ERROR_MESSAGE()
	END CATCH
	
	/*******************
	* KILL TOP BLOCKER *
	*******************/
	--@BlockCountKillThreshold
	UPDATE B1
		SET B1.IsKilled=1
	FROM #Block B1
	WHERE 
		B1.SessionID=B1.ParentBlockSessionID
		AND (SELECT COUNT(*) FROM #Block B2 WHERE B2.ParentBlockSessionID=B1.SessionID AND B2.IsUserProcess=1)>@BlockCountKillThreshold
		AND B1.IsUserProcess=1
	SET @KillCount=@@ROWCOUNT

	SET @SQL=NULL
	SELECT 
		@SQL=ISNULL(@SQL+CHAR(13)+CHAR(10),N'''')+
		N''IF EXISTS (SELECT 1 FROM sys.dm_exec_connections WHERE connection_id='''''' + CONVERT(NVARCHAR(512),B1.ConnectionID)+'''''') KILL ''+CONVERT(NVARCHAR(10),B1.SessionID)+'';''
	FROM 
		#Block B1 
	WHERE 
		IsKilled=1

	IF @SQL IS NOT NULL EXEC (@SQL)

	/**************
	* Send E-mail *
	**************/
	SET @Subject=NULL
	SELECT 
		@Subject=ISNULL(@Subject+'', '','''') + CONVERT(VARCHAR(5),SessionID)
	FROM 
		#Block
	WHERE
		BlockSessionID>0
	
	SET @Subject= @ServerName
	+CASE WHEN @KillCount>0 THEN '' KILLED '' + CONVERT (VARCHAR(5),@KillCount)+''; '' ELSE '''' END
	+ '' Blocked ''
	+ CONVERT (VARCHAR(5),@BlockCount) + '' session''+CASE WHEN @BlockCount>1 THEN ''s'' ELSE '''' END +'' - ''
	+ @Subject
	
	/***********************
	* Build HTML using XML *
	***********************/
	SET @Body=
	''<html><body><table border = "1">
	<tr>
		<th>Top Block</th>
		<th>Block</th>
		<th>SPID</th>
		<th>Command</th>
		<th>Run</th>
		<th>Wait</th>
		<th>Wait Type</th>
		<th>Database</th>
		<th>Object</th>
		<th>Host Name</th>
		<th>Program Name</th>
		<th>Login</th>
		<th>Tran Type</th>
		<th>Start SQL</th>
		<th>Current SQL</th>
		<th>Input Buffer</th>
		<th>Resource</th>
		<th>Description</th>
		
	</tr>''
	+
	(SELECT		
		CASE WHEN B.IsKilled=1 THEN ''Green'' WHEN B.ParentBlockSessionID=B.SessionID THEN ''Red'' ELSE ''Default'' END AS [BGColor] --Marker to replace with proper colors
		,CASE WHEN B.IsKilled=1 THEN ''KILLED'' WHEN B.ParentBlockSessionID=B.SessionID THEN ''*'' WHEN B.ParentBlockSessionID>0 THEN CONVERT(VARCHAR(10),B.ParentBlockSessionID) ELSE ''--'' END AS [td] --Top Block
		,CASE WHEN B.ParentBlockSessionID=B.SessionID THEN ''*'' WHEN B.BlockSessionID>0 THEN CONVERT(VARCHAR(10),B.BlockSessionID) ELSE ''--'' END AS [td] --Block
		,CONVERT(VARCHAR(10),B.SessionID)AS [td] --SPID
		,LEFT(ISNULL(B.Command,''--''),256)AS [td] --Command
		,ISNULL(B.RunTime,''--'')AS [td] --Run Time
		,ISNULL(B.WaitTime,''--'')AS [td] --Wait Time
		,LEFT(ISNULL(B.WaitType,''--''),255)AS [td] --Wait Type
		,LEFT(COALESCE(D.name,CONVERT(VARCHAR(5),B.DatabaseID),''--''),255)AS [td] --Database
		,LEFT(COALESCE(O.ObjectName,CONVERT(VARCHAR(255),B.ObjectID),''--''),255)AS [td] --Object
		,ISNULL(B.HostName,''--'')AS [td] --Host Name
		,ISNULL(B.ProgramName,''--'')AS [td] --Program Name
		,RIGHT(B.LoginName,LEN(B.LoginName)-CHARINDEX (''\'',B.LoginName)+1)AS [td] --Login
		,CASE B.TransactionType WHEN 1 THEN ''R/W'' WHEN 2 THEN ''R/O'' WHEN 3 THEN ''Sys'' WHEN 4 THEN ''Distr'' ELSE ''--'' END AS [td] --Tran Type
		,LEFT(ISNULL(B.SQLText,''--''),512)AS [td] --Start SQL
		,CASE WHEN B.SQLText IS NULL --Current SQL
				THEN ''--''
			WHEN B.SQLStart IS NULL OR B.SQLEnd IS NULL OR B.SQLEnd<=0
				THEN B.SQLText
			ELSE (SUBSTRING(B.SQLText,(B.SQLStart+2)/2,       
				(CASE WHEN B.SQLEnd = -1         
				THEN DATALENGTH (B.SQLText)      
				ELSE B.SQLEnd
				END - B.SQLStart) /2))
		END/*,255)*/
		AS [td]
		,ISNULL(B.InputBuffer,''--'')AS [td] --Input Buffer
		,ISNULL(B.WaitResource,''--'')AS [td] --Wait Resource
		,ISNULL(B.ResourceDesc,''--'')AS [td] --Wait Resource Description
	FROM #Block B
	LEFT JOIN #Object O ON B.DatabaseID=O.DatabaseID AND B.ObjectID=O.ObjectID
	LEFT JOIN sys.databases D ON B.DatabaseID=D.database_id
	ORDER BY MAX(CASE B.IsKilled WHEN 1 THEN 1 ELSE 0 END) OVER (PARTITION BY B.ParentBlockSessionID) DESC, B.ParentBlockSessionID, B.BlockSessionID, B.SessionID
	FOR XML RAW(''tr''), Elements)
	+''</table></body></html>''

	SET @Body=REPLACE(@Body,''<tr><BGColor>Red</BGColor>'',''<tr bgcolor=#FF0000>'')
	SET @Body=REPLACE(@Body,''<tr><BGColor>Green</BGColor>'',''<tr bgcolor=#00FF00>'')
	SET @Body=REPLACE(@Body,''<tr><BGColor>Blue</BGColor>'',''<tr bgcolor=#0000FF>'')
	SET @Body=REPLACE(@Body,''<tr><BGColor>Default</BGColor>'',''<tr>'')

	/*************************************************
	* Get DBA Opertor E-mail and E-mail profile Name *
	*************************************************/
	SELECT @Recipients=email_address from msdb.dbo.sysoperators WHERE name=''DBA'' and enabled=1
	SELECT TOP 1 @ProfileName=P.name FROM msdb..sysmail_principalprofile PP RIGHT JOIN msdb..sysmail_profile P ON PP.profile_id=P.profile_id ORDER BY PP.is_default DESC, P.profile_id
	IF @Recipients IS NULL OR @Recipients NOT LIKE ''%@%'' --Verify if e-mail is configured
	BEGIN
		SET @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'''') + ''[''+ @ServerName +''] - '' + ''No DBA Operator Found, please configure DBA Operator''
	END	
	ELSE
	IF @ProfileName IS NULL --Verify a profile was retrieved
	BEGIN
		SET @ErrorMessage=ISNULL(@ErrorMessage + CHAR(13),'''') + ''[''+ @ServerName +''] - '' + ''No e-mail profile found; please configure e-mail profile''
	END	  
	ELSE
	BEGIN
		SET @FromAddress=@ServerName + ''<noreply@''+@ServerName+''>''
		EXEC msdb.dbo.sp_send_dbmail
		@profile_name=@ProfileName,
		@recipients = @Recipients,
		@body = @Body,
		@subject = @Subject,
		@body_format=''HTML''
	END

	SELECT B.*
	,CASE WHEN B.SQLText IS NULL
		THEN NULL
	WHEN B.SQLStart IS NULL OR B.SQLEnd IS NULL OR B.SQLEnd<1
		THEN B.SQLText
		ELSE (SUBSTRING(B.SQLText,(B.SQLStart+2)/2,       
			(CASE WHEN B.SQLEnd = -1         
			THEN DATALENGTH (B.SQLText)      
			ELSE B.SQLEnd
			END - B.SQLStart) /2))
	END AS CurrentSQL
	FROM #Block B 
	LEFT JOIN #Object O ON B.DatabaseID=O.DatabaseID AND B.ObjectID=O.ObjectID
	LEFT JOIN sys.databases D ON B.DatabaseID=D.database_id
	ORDER BY MAX(CASE B.IsKilled WHEN 1 THEN 1 ELSE 0 END) OVER (PARTITION BY B.ParentBlockSessionID) DESC, B.ParentBlockSessionID, B.BlockSessionID, B.SessionID
END


--Report Back Error
IF @ErrorMessage IS NOT NULL
	RAISERROR (@ErrorMessage,18,1)

', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Manage Blocking', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=60, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20140106, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO



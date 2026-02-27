USE [DBA_Central]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[pNotify_ServerPing]
AS
/**********************************************************************
* Check which servers haven't pinged; ping them and notify of failure *
**********************************************************************/
DECLARE @PingStartDate DATETIME=DATEADD(MINUTE,-3,CURRENT_TIMESTAMP)
DECLARE @NotifyStartDate DATETIME=DATEADD(MINUTE,-5,CURRENT_TIMESTAMP)
DECLARE @SQL NVARCHAR(MAX)
		,@Body NVARCHAR(MAX)
		,@Subject NVARCHAR(MAX)
		,@Recipients NVARCHAR (255)
		,@FromAddress NVARCHAR (255)
		,@ServerID INT
		,@IsLinked BIT
		,@ServerName NVARCHAR(128)
		,@ErrorMessage NVARCHAR(MAX)
		,@ErrorNumber INT

CREATE TABLE #PingServer (ServerID INT, ServerName NVARCHAR(128), IsLinked BIT)

INSERT INTO #PingServer (ServerID, ServerName, IsLinked)
SELECT 
	S.ServerID, S.ServerName, IsLinked
FROM 
	tServer S
WHERE 
	S.EnablePingNotification=1
	AND S.ServerID NOT IN (
		SELECT 
			PL.ServerID 
		FROM 
			tServerPingLog PL
		WHERE 
			PL.LastPingDate>=@PingStartDate
			OR PL.LastNotificationDate>=@NotifyStartDate
		)
	

DECLARE curServer CURSOR 
	FOR 
	SELECT 
		ServerID, ServerName, IsLinked
	FROM 
		#PingServer
	ORDER BY ServerID
    OPEN curServer

/***************************
* Loop through all servers *
***************************/
SET @ErrorMessage=NULL
WHILE 1=1
BEGIN
    FETCH NEXT FROM curServer
	INTO @ServerID, @ServerName, @IsLinked
	IF @@FETCH_STATUS<>0 BREAK
	
	PRINT @ServerName
	SET @ErrorMessage=NULL
	SET @Body=NULL
	SET @Subject=NULL

	/**************
	* Try Pinging *
	**************/
	BEGIN TRY
		SET @SQL='SELECT '''+REPLACE(@ServerName,'''','')+''' AS PING'
		IF @IsLinked=1
			SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'
		EXEC (@SQL)
		/**********************
		* Log Successful Ping *
		***********************/
		UPDATE tServerPingLog
		SET
			LastPingSource='ServerPing'
			,LastPingDate=CURRENT_TIMESTAMP
		WHERE
			ServerID=@ServerID
	END TRY
	/********************
	* Notify of Failure *
	********************/
	BEGIN CATCH
		--18456
		SET @ErrorNumber=ERROR_NUMBER()
		SET @ErrorMessage=ERROR_MESSAGE() + CHAR(13) + 'Error Number: ' + CONVERT(VARCHAR(10),@ErrorNumber)
		/**************************************************************
		* Ignore Login failed for user 'NT AUTHORITY\ANONYMOUS LOGON' *
		* And Linked Server being dropped                             *
		**************************************************************/
		IF NOT @ErrorNumber IN(18456,7202)
		BEGIN
			UPDATE tServerPingLog
			SET
				LastPingSource='ServerPing'
				,LastNotificationDate=CURRENT_TIMESTAMP
			WHERE
				ServerID=@ServerID
		
			SET @Subject=@ServerName + ' - NO PING!!!'
			SET @Body=@ErrorMessage
			
	
			SET @Recipients=dbo.fGetDBAEmail(2)
			SET @FromAddress=dbo.fFromEmail (@ServerName)
			EXEC msdb.dbo.sp_send_dbmail
			@recipients = @Recipients,
			@from_address=@FromAddress,
			@body = @Body,
			@subject = @Subject
		END
	END CATCH

END
CLOSE curServer
DEALLOCATE curServer



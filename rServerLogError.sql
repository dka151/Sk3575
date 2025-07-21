USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rServerLogError]    Script Date: 7/21/2025 10:54:35 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[rServerLogError] @ServerIDs VARCHAR(MAX)=NULL, @StartDate DATETIME=NULL, @EndDate DATETIME=NULL, @Errors VARCHAR(MAX)=NULL AS  
--DECLARE @ServerIDs VARCHAR(MAX)=NULL, @StartDate DATETIME=NULL, @EndDate DATETIME=NULL, @Errors VARCHAR(MAX)='ALL' 
 
--SQL Server Error Log Report 
DECLARE @SQL NVARCHAR(MAX)  
		,@ServerName NVARCHAR(128)  
		,@X XML 
 
BEGIN TRY 
	IF RTRIM(@Errors)='' OR RTRIM(@Errors)='ALL' SET @Errors=NULL 
	IF @Errors LIKE '%[^0-9,]' 
		RAISERROR ('Incorrect Errors Parameter Format',18,1) 
 
	IF OBJECT_ID ('tempdb..#Server','U') IS NOT NULL DROP TABLE #Server 
	CREATE TABLE #Server (ServerID INT, ServerName NVARCHAR(128) NOT NULL UNIQUE, PRIMARY KEY CLUSTERED (ServerID) WITH (IGNORE_DUP_KEY=ON)) 
	IF OBJECT_ID ('tempdb..#Error','U') IS NOT NULL DROP TABLE #Error 
	CREATE TABLE #Error (Error INT PRIMARY KEY CLUSTERED WITH (IGNORE_DUP_KEY=ON)) 
 
	--Set Date Range 
	IF @StartDate IS NULL SET @StartDate=CURRENT_TIMESTAMP-1 
	SET @EndDate=ISNULL(@EndDate,@StartDate+1) 
 
	--Get a list of Servers 
	IF @ServerIDs IS NOT NULL 
	BEGIN 
		SET @X='<r>'+REPLACE(@ServerIDs,',','</r>'+'<r>')+'</r>' 
		;WITH SX AS 
			(SELECT   
				   Tbl.Col.value('.', 'INT') AS ServerID 
			FROM   @X.nodes('//r') Tbl(Col) 
		) 
	 
		INSERT INTO #Server (ServerID, ServerName) 
		SELECT  
			S.ServerID, S.ServerName 
		FROM  
			tServer S 
			JOIN SX ON S.ServerID=SX.ServerID 
		--WHERE  
		--	S.Active=1 
	END 
	ELSE 
	BEGIN 
		INSERT INTO #Server (ServerID, ServerName) 
		SELECT  
			S.ServerID, S.ServerName 
		FROM  
			tServer S 
		--WHERE  
			--S.Active=1 
	END 
 
	--Get a list of Errors 
	IF @Errors IS NOT NULL 
	BEGIN 
		SET @X='<r>'+REPLACE(@Errors,',','</r>'+'<r>')+'</r>' 
		INSERT INTO #Error (Error) 
		SELECT   
			Tbl.Col.value('.', 'INT') AS Error 
			FROM   @X.nodes('//r') Tbl(Col) 
	END 
	ELSE 
	BEGIN 
		INSERT INTO #Error (Error) 
		SELECT  
			message_id AS Error 
		FROM  
			sys.messages  
		WHERE  
			is_event_logged=1  
			AND language_id=1033 
	END 
 
	SELECT  
		SG.ServerGroupName 
		,S.ServerGroupID 
		,S.ServerName 
		,L1.ServerID 
		,L1.LogID 
		,L1.LogDate 
		,L1.ProcessInfo 
		,L1.Text 
		,L2.Error 
		,L2.Severity 
		,L2.[State] 
		FROM 
		#Server TS 
		JOIN tServer S ON TS.ServerID=S.ServerID 
		JOIN tServerGroup SG ON S.ServerGroupID=SG.ServerGroupID 
		JOIN tServerLog L1 ON S.ServerID=L1.ServerID 
		JOIN tServerLog L2 
			ON L1.ServerID=L2.ServerID 
			AND L1.LogDate=L2.LogDate 
	WHERE 
		L2.Error IN (SELECT E.Error FROM #Error E) 
		AND L1.LogDate BETWEEN @StartDate AND @EndDate 
		AND L1.LogID>=L2.LogID --Remove some Duplicates 
	ORDER BY 
		S.ServerName 
		,L1.LogDate 
		,L1.LogID 
END TRY 
BEGIN CATCH 
	THROW 
END CATCH 

GO



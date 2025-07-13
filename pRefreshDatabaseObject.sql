USE [DBMoitor]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshDatabaseObject]    Script Date: 7/13/2025 2:00:57 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[pRefreshDatabaseObject] AS 
/*************************************************** 
* Keep track of all database files and their sizes * 
***************************************************/ 
SET LOCK_TIMEOUT 60000; 
DECLARE @Date SMALLDATETIME = CURRENT_TIMESTAMP, 
		@SQL NVARCHAR(MAX), 
		@ServerID INT, 
		@IsLinked BIT, 
		@ServerName NVARCHAR (128), 
		@DatabaseID INT, 
		@DatabaseName NVARCHAR (128), 
		@ErrorMessage NVARCHAR(MAX) 
		 
		 
IF OBJECT_ID ('tempdb..#Schema') IS NOT NULL DROP TABLE #Schema 
CREATE TABLE #Schema( 
	[SchemaName] NVARCHAR(128) NOT NULL PRIMARY KEY CLUSTERED, 
	[ServerSchemaID] INT NOT NULL UNIQUE, 
	[ServerPrincipalID] INT NOT NULL) 
 
IF OBJECT_ID ('tempdb..#Object') IS NOT NULL DROP TABLE #Object 
CREATE TABLE #Object( 
	[ObjectName] NVARCHAR(128) NOT NULL, 
	[ObjectType] VARCHAR(2), 
	[ServerSchemaID] INT NOT NULL, 
	[ServerObjectID] INT NOT NULL UNIQUE, 
	[ServerParentObjectID] INT NOT NULL, 
	[ServerPrincipalID] INT NULL, 
	[ObjectCreateDate] DATETIME NOT NULL, 
	[ObjectModifyDate] DATETIME NOT NULL, 
	[IsMSShipped] BIT NOT NULL, 
	[IsSchemaPublished] BIT NOT NULL, 
	PRIMARY KEY CLUSTERED (ServerSchemaID, ObjectName) 
	) 
IF OBJECT_ID('tempdb..#ObjectStateTemp','U') IS NOT NULL DROP TABLE #ObjectStateTemp 
SELECT TOP 0 * INTO #ObjectStateTemp FROM tObjectState 
 
IF OBJECT_ID('tempdb..#SchemaStateTemp','U') IS NOT NULL DROP TABLE #SchemaStateTemp 
SELECT TOP 0 * INTO #SchemaStateTemp FROM tSchemaState 
 
IF OBJECT_ID('tempdb..#DatabaseError') IS NOT NULL DROP TABLE #DatabaseError 
CREATE TABLE #DatabaseError 
( 
	DatabaseID INT PRIMARY KEY CLUSTERED 
	,ErrorMessage NVARCHAR(MAX) 
) 
 
DECLARE curDatabase CURSOR  
     FOR  
				
			SELECT  
			S.ServerID, S.ServerName, S.IsLinked, D.DatabaseID, D.DatabaseName  
		FROM  
			tServer S 
			JOIN tDatabase D  
				ON S.ServerID=D.ServerID 
			JOIN tDatabaseConfiguration DS 
				ON D.DatabaseID=DS.DatabaseID AND DS.EndDate IS NULL AND DS.ConfigurationName='state_desc' AND CONVERT(NVARCHAR(128),DS.ConfigurationValue) = N'ONLINE' 
		WHERE 
		    S.IsSQLServer=1  
			AND S.Active = 1  
			AND S.EnableServerDBTrack=1  
			AND D.Active=1  
			AND D.ServerDatabaseID NOT IN (2) 
			AND s.ISAG<>1
			UNION
		SELECT  
			S.ServerID, S.ServerName, S.IsLinked, D.DatabaseID, D.DatabaseName  
		FROM  
			tServer S  INNER JOIN [tAGPrimaryDatabase] tag
			ON s.ServerID = tag.ServerID
			JOIN tDatabase D  
				ON S.ServerID=D.ServerID 
			JOIN tDatabaseConfiguration DS 
				ON D.DatabaseID=DS.DatabaseID AND DS.EndDate IS NULL AND DS.ConfigurationName='state_desc' AND CONVERT(NVARCHAR(128),DS.ConfigurationValue) = N'ONLINE'
		WHERE  
			s.IsSQLServer=1  
			AND s.Active=1  
			AND s.EnableServerDBTrack=1 
			AND s.ISAG=1
			AND s.ServerName LIKE '%DBS%'
			--AND s.ServerName NOT LIKE '%WRK%DBS%' 
			--AND s.ServerName NOT LIKE '%BUS%DBS%'  
			--AND s.ServerName NOT LIKE '%MES%DBS%'  
			--AND s.ServerName NOT LIKE '%MIS%DBS%'
		ORDER BY  
			ServerID
			
			 
OPEN curDatabase 
 
WHILE 1=1 
BEGIN 
    FETCH NEXT FROM curDatabase 
	INTO @ServerID, @ServerName, @IsLinked, @DatabaseID, @DatabaseName 
	IF @@FETCH_STATUS<>0 BREAK 
	PRINT '--------------------' 
	PRINT @ServerName + ' - '+@DatabaseName 
	RAISERROR ('%s', 0, 1,'') WITH NOWAIT 
	PRINT '--------------------' 
 
	BEGIN TRY 
		TRUNCATE TABLE #Schema 
		TRUNCATE TABLE #Object 
 
		/********* 
		* Schema * 
		********/ 
		SET @SQL= 
		N'IF EXISTS (SELECT *
		FROM sys.databases d
		LEFT JOIN sys.dm_hadr_availability_replica_states hars ON d.replica_id = hars.replica_id
		WHERE (hars.role IS NULL or hars.role = 1) AND d.name = ''' + +@DatabaseName+ '''
		)
		BEGIN 
			SELECT  
				name AS SchemaName 
				,[schema_id] AS ServerSchemaID 
				,[principal_id] AS ServerPrincipalID 
			FROM ['+@DatabaseName+'].sys.schemas 
		END'
		IF @IsLinked=1 
			SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']' 
 
		INSERT INTO #Schema	(SchemaName, ServerSchemaID, ServerPrincipalID) 
			EXEC (@SQL) 

 
		;WITH Tgt AS (SELECT * FROM tSchema WHERE DatabaseID=@DatabaseID) 
 
		MERGE Tgt
		USING #Schema AS Src
			ON Tgt.SchemaName=Src.SchemaName
				AND Tgt.ServerSchemaID=Src.ServerSchemaID
		WHEN NOT MATCHED 
			THEN INSERT (
				DatabaseID
				,StartDate
				,EndDate
				,SchemaName
				,ServerSchemaID
				) 
			VALUES 
				(@DatabaseID --DatabaseID
				,@Date --StartDate
				,NULL --EndDate
				,Src.SchemaName
				,Src.ServerSchemaID
				)
		WHEN NOT MATCHED BY SOURCE
			THEN UPDATE SET Tgt.EndDate=@Date
		--OUTPUT $ACTION AS [Action], Src.* 
		; 
 
		/*************** 
		* Schema State * 
		***************/ 
		TRUNCATE TABLE #SchemaStateTemp 
		BEGIN TRAN SchemaState 
			;WITH Tgt AS (SELECT * FROM tSchemaState WHERE EndDate IS NULL AND SchemaID IN (SELECT S.SchemaID FROM tSchema S WHERE S.DatabaseID=@DatabaseID)) 
			,Src AS ( 
				SELECT S2.SchemaID, S.*  
				FROM  
					#Schema S  
					JOIN tSchema S2 
						ON S2.DatabaseID=@DatabaseID 
						AND S2.ServerSchemaID=S.ServerSchemaID
						AND S2.EndDate IS NULL
			) 
 
			--Insert new values records that had its values changed (End Date updated to Timestamp, Schema ID is not null)
			--Use temp table because direct insert only works in SQL2014
			INSERT INTO #SchemaStateTemp (SchemaID, StartDate, EndDate, ServerPrincipalID)
			SELECT SchemaID, @Date AS StartDate, NULL AS EndDate, ServerPrincipalID
			FROM
			(
				MERGE Tgt
				USING Src
					ON Tgt.SchemaID=Src.SchemaID
				WHEN NOT MATCHED --New Entries
					THEN INSERT (
						SchemaID
						,StartDate
						,EndDate
						,ServerPrincipalID
						) 
					VALUES 
						(SchemaID
						,@Date --StartDate
						,NULL --EndDate
						,ServerPrincipalID
						)
				WHEN NOT MATCHED BY SOURCE --Deleted Entries
					THEN UPDATE SET Tgt.EndDate=@Date
				WHEN MATCHED --Entires that have changed; insert new values at the top level
					AND EXISTS
						(SELECT Src.ServerPrincipalID
						EXCEPT
						SELECT Tgt.ServerPrincipalID)
					THEN UPDATE SET Tgt.EndDate=@Date
				OUTPUT $ACTION AS [Action], Src.* 
			) Mrg
			--See Insert comment above
			WHERE Mrg.[Action]='UPDATE' AND Mrg.SchemaID IS NOT NULL
			; 
			INSERT INTO tSchemaState  
				SELECT * FROM #SchemaStateTemp 
		COMMIT 
		 
		 
		/********* 
		* Object * 
		********/ 
		SET @SQL= 
		N'IF EXISTS (SELECT *
		FROM sys.databases d
		LEFT JOIN sys.dm_hadr_availability_replica_states hars ON d.replica_id = hars.replica_id
		WHERE (hars.role IS NULL or hars.role = 1) AND d.name = ''' + +@DatabaseName+ '''
		)
		BEGIN 
			SELECT  
			name AS ObjectName 
			,[type] AS ObjectType 
			,[schema_id] AS ServerSchemaID 
			,[object_id] AS ServerObjectID 
			,[parent_object_id] AS ServerParentObjectID 
			,[principal_id] AS [ServerPrincipalID] 
			,create_date AS [ObjectCreateDate] 
			,modify_date AS [ObjectModifyDate] 
			,is_ms_shipped AS [IsMSShipped] 
			,is_schema_published AS [IsSchemaPublished]		 
			FROM ['+@DatabaseName+'].sys.objects
		END'
		IF @IsLinked=1 
			SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']' 
 
		INSERT INTO #Object 
			(ObjectName 
			,ObjectType 
			,ServerSchemaID 
			,ServerObjectID 
			,ServerParentObjectID 
			,ServerPrincipalID 
			,ObjectCreateDate 
			,ObjectModifyDate 
			,IsMSShipped 
			,IsSchemaPublished 
			) 
			EXEC (@SQL) 
 
/* 
		--Remove objects for non-existing schemas 
		UPDATE O SET EndDate = @Date 
		FROM tObject O 
			LEFT JOIN tSchema S  
				ON O.SchemaID=S.SchemaID AND S.EndDate IS NULL 
		WHERE 
			O.EndDate IS NULL 
			AND S.SchemaID IS NULL 
*/ 
		;WITH Tgt AS (SELECT * FROM tObject WHERE EndDate IS NULL AND SchemaID IN (SELECT S.SchemaID FROM tSchema S WHERE S.DatabaseID=@DatabaseID /*AND S.EndDate IS NULL*/)) 
		,Src AS (SELECT S.SchemaID, O.* FROM #Object O JOIN tSchema S ON S.DatabaseID=@DatabaseID AND O.ServerSchemaID=S.ServerSchemaID AND S.EndDate IS NULL) 
 
		MERGE Tgt
		USING Src
			ON Tgt.ObjectName=Src.ObjectName COLLATE DATABASE_DEFAULT
			AND Tgt.ServerObjectID=Src.ServerObjectID
			AND Tgt.ServerParentObjectID=Src.ServerParentObjectID
			AND Tgt.ObjectType=Src.ObjectType COLLATE DATABASE_DEFAULT
			AND Tgt.SchemaID=Src.SchemaID
		WHEN NOT MATCHED 
			THEN INSERT (
				SchemaID
				,StartDate
				,EndDate
				,ObjectName
				,ObjectType
				,ServerObjectID
				,ServerParentObjectID
				,ServerSchemaID
				) 
			VALUES 
				(SchemaID
				,@Date --StartDate
				,NULL --EndDate
				,ObjectName
				,ObjectType
				,ServerObjectID
				,ServerParentObjectID
				,ServerSchemaID
				)
		WHEN NOT MATCHED BY SOURCE
			THEN UPDATE SET Tgt.EndDate=@Date
		--OUTPUT $ACTION AS [Action], Src.* 
	; 
 
		/*************** 
		* Object State * 
		***************/ 
		TRUNCATE TABLE #ObjectStateTemp 
		BEGIN TRAN ObjectState 
			;WITH Tgt AS (SELECT * FROM tObjectState WHERE EndDate IS NULL AND ObjectID IN (SELECT O.ObjectID FROM tSchema S JOIN tObject O ON S.SchemaID=O.SchemaID WHERE S.DatabaseID=@DatabaseID /*AND S.EndDate IS NULL AND O.EndDate IS NULL*/)) 
			,Src AS ( 
				SELECT O2.ObjectID, O.*  
				FROM  
					#Object O  
					JOIN tSchema S ON S.DatabaseID=@DatabaseID AND O.ServerSchemaID=S.ServerSchemaID AND S.EndDate IS NULL 
					JOIN tObject O2 
						ON S.SchemaID=O2.SchemaID
						AND O.ServerObjectID=O2.ServerObjectID
						AND O2.EndDate IS NULL
			) 
 
			--Insert new values records that had its values changed (End Date updated to Timestamp, Object ID is not null)
			--Use temp table because direct insert only works in SQL2014
			INSERT INTO #ObjectStateTemp (ObjectID, StartDate, EndDate, ServerPrincipalID, ObjectCreateDate, ObjectModifyDate, IsMSShipped, IsSchemaPublished)
			SELECT ObjectID, @Date AS StartDate, NULL AS EndDate, ServerPrincipalID, ObjectCreateDate, ObjectModifyDate, IsMSShipped, IsSchemaPublished
			FROM
			(
				MERGE Tgt
				USING Src
					ON Tgt.ObjectID=Src.ObjectID
				WHEN NOT MATCHED --New Entries
					THEN INSERT (
						ObjectID
						,StartDate
						,EndDate
						,ServerPrincipalID
						,ObjectCreateDate
						,ObjectModifyDate
						,IsMSShipped
						,IsSchemaPublished
						) 
					VALUES 
						(ObjectID
						,@Date --StartDate
						,NULL --EndDate
						,ServerPrincipalID
						,ObjectCreateDate
						,ObjectModifyDate
						,IsMSShipped
						,IsSchemaPublished
						)
				WHEN NOT MATCHED BY SOURCE --Deleted Entries
					THEN UPDATE SET Tgt.EndDate=@Date
				WHEN MATCHED --Entires that have changed; insert new values at the top level
					AND EXISTS
						(SELECT Src.ServerPrincipalID,Src.ObjectCreateDate,Src.ObjectModifyDate,Src.IsMSShipped,Src.IsSchemaPublished
						EXCEPT
						SELECT Tgt.ServerPrincipalID,Tgt.ObjectCreateDate,Tgt.ObjectModifyDate,Tgt.IsMSShipped,Tgt.IsSchemaPublished)
					THEN UPDATE SET Tgt.EndDate=@Date
				OUTPUT $ACTION AS [Action], Src.* 
			) Mrg
		--See Insert comment above
		WHERE Mrg.[Action]='UPDATE' AND Mrg.ObjectID IS NOT NULL
		; 
		INSERT INTO tObjectState  
			SELECT * FROM #ObjectStateTemp 
	COMMIT 
 
	END TRY 
	BEGIN CATCH 
		IF @@TRANCOUNT>0 ROLLBACK 
		SET @ErrorMessage = '['+@ServerName + '].['+@DatabaseName+']: ' + ERROR_MESSAGE() 
		INSERT INTO #DatabaseError (DatabaseID, ErrorMessage) VALUES (@DatabaseID, @ErrorMessage) 
	END CATCH 
 
END 
CLOSE curDatabase 
DEALLOCATE curDatabase 
---------- End Server Loop ---------- 
 
 
/***************** 
* ERROR HANDLING * 
*****************/ 
SET @ErrorMessage=NULL 
SELECT  
	@ErrorMessage=ISNULL(@ErrorMessage+';'+CHAR(13),'')+ SE.ErrorMessage 
FROM  
	#DatabaseError SE 
WHERE 
	SE.ErrorMessage IS NOT NULL 
 
IF @ErrorMessage IS NOT NULL 
BEGIN 
	SELECT * FROM #DatabaseError 
	RAISERROR (@ErrorMessage,18,1) 
END 

GO



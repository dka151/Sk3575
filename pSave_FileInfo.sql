USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pSave_FileInfo]    Script Date: 7/22/2025 11:41:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROC [dbo].[pSave_FileInfo] 
AS

BEGIN
	SET NOCOUNT ON;
	
	DECLARE @sqlstring NVARCHAR(4000),
	@DBName NVARCHAR(257),
	@OPENQUERY NVARCHAR(4000),
	@query NVARCHAR(max),
	@sid NVARCHAR(10) ,
    @sname NVARCHAR(100);
	IF OBJECT_ID('tempdb..#tempdatabaseList', 'U') IS NOT NULL
    DROP TABLE #tempdatabaseList;   
CREATE TABLE #tempdatabaseList
    (
      ServerID INT ,
      servername sysname ,
      DBName NVARCHAR(128)
    );  
	DECLARE @servers TABLE
    (
      servername sysname ,
      serverid INT
    );
   
INSERT  @servers
        ( serverid ,
          servername
        )
SELECT  [serverid]  
       ,[servername]  
FROM    [dbo].[tServer]  
WHERE   [IsLinked] = 1  
        AND [Active] = 1  
		
		
		
 SET @query = 'INSERT INTO #tempdatabaseList (
          ServerID,
		  ServerName,
		  DBName)';
DECLARE @union BIT;
SET @union = 'FALSE';

WHILE 1 = 1
    BEGIN
        DECLARE @server sysname ,
            @serverid INT;

        SELECT TOP 1
                @server = servername ,
                @serverid = serverid
        FROM    @servers;

        IF @@rowcount = 0
            BREAK;

        IF @union = 'TRUE'
            SET @query = @query + ' union all ' + CHAR(13) + CHAR(10);
 
        SET @query = @query + 'SELECT ' + CAST(@serverid AS VARCHAR(10))
            + ',''' + CAST(@server AS VARCHAR(50)) + ''','
            + '* FROM OPENQUERY (' + QUOTENAME(@server) + ','
            + '''SELECT name
	FROM   master.[sys].[databases] d
	LEFT JOIN sys.dm_hadr_availability_replica_states hars ON d.replica_id = hars.replica_id
	WHERE  NAME NOT IN (''''sysutility_mdw'''',''''perfmon_collector'''',''''DBA'''')
		   AND (hars.role IS NULL or hars.role = 1)
		   AND state = 0	
		   AND database_id > 4'')' + CHAR(13) + CHAR(10);
        SET @union = 'TRUE';
         
        DELETE  FROM @servers
        WHERE   servername = @server;

    END;
    
EXEC (@query);

--SELECT  * FROM  #tempdatabaseList; --For debugging

SELECT  TOP (1) @sid=[ServerID], @sname=[servername], @dbname=[DBName]
FROM    [#tempdatabaseList]
ORDER BY [ServerID];

WHILE 1=1
    BEGIN

	     DELETE  FROM #tempdatabaseList
        WHERE   DBName = @dbName
                AND ServerID = @sid;
	 
	 SET @OPENQUERY = '
	INSERT [DBA].[dbo].[tFileInfo] (
		  [ServerID],
 		  [DatabaseName],
		  [FileID],
		  [Type],
		  [DriveLetter],
		  [LogicalFileName],
		  [PhysicalFileName],
		  [SizeMB],
		  [SpaceUsedMB],
		  [FreeSpaceMB],
		  [MaxSize],
		  [IsPercentGrowth],
		  [Growth],
		  [CaptureDate]
		  ) 
		  
		  SELECT * FROM OPENQUERY(' + QUOTENAME(@sname) +', ''Exec (''''USE '+ @DBName+ '; SELECT '''''''''+@sid+'''''''' +''','''''''''+ @DBName+ '''''''''
		  ,[file_id],
		   [type],
		  substring([physical_name],1,1),
		  [name],
		  [physical_name],
		  CAST([size] as DECIMAL(38,0))/128., 
		  CAST(FILEPROPERTY([name],''''''''SpaceUsed'''''''') AS DECIMAL(38,0))/128.,
		  (CAST([size] as DECIMAL(38,0))/128) - (CAST(FILEPROPERTY([name],''''''''SpaceUsed'''''''') AS DECIMAL(38,0))/128.) ,
		  [max_size],
		  [is_percent_growth],
		  [growth],
		  GETDATE()
		  FROM '+ @DBName + '.[sys].[database_files];'''')'')'

exec (@OPENQUERY); 


SELECT  TOP (1) @sid=[ServerID], @sname=[servername], @dbname=[DBName]
FROM    [#tempdatabaseList]
ORDER BY [ServerID];

IF NOT EXISTS (SELECT 1 FROM #tempdatabaseList) BREAK;
	
		END
	END

--SELECT * FROM [dbo].[tFileInfo] -- For Debugging
--truncate table [dbo].[tFileInfo] -- For Debugging



GO



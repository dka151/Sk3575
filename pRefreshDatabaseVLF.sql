USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshDatabaseVLF]    Script Date: 7/13/2025 2:01:28 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[pRefreshDatabaseVLF]
AS
/**********************************************************   
* Deepak Adhya: Collect VLF Size for database             *   
 **********************************************************/
SET NOCOUNT ON;


DECLARE @dbName VARCHAR(255),
        @tblName VARCHAR(255),
        @tName VARCHAR(255),
        @query NVARCHAR(MAX),
        @OPENQUERY NVARCHAR(4000),
        @sid NVARCHAR(10),
        @sname NVARCHAR(100),
        @Date DATETIME = CURRENT_TIMESTAMP;


--IF OBJECT_ID(N'tempdb..#SummaryInfo', N'U') IS NOT NULL
--BEGIN
--    DROP TABLE #SummaryInfo;
--END;
--CREATE TABLE #SummaryInfo
--(
--	ServerID INT NOT NULL,
--    DatabaseName sysname NOT NULL,
--    VLFCount INT NOT NULL,
--    AverageVLFSizeMB DECIMAL(10, 2) NOT NULL,
--    MinVLFSizeMB DECIMAL(10, 2) NOT NULL,
--    MaxVLFSizeMB DECIMAL(10, 2) NOT NULL
--); 


DECLARE @servers TABLE
(
    servername sysname NULL,
    serverid INT NULL
);

INSERT @servers
(
    [serverid],
    [servername]
)
SELECT 
	   [ServerID],
       [ServerName]
FROM [dbo].[tServer]
WHERE [IsLinked] = 1
      AND [Active] = 1
	  AND [IsSQLServer] = 1

--SELECT * FROM @servers;

TRUNCATE TABLE [dbo].[tDatabaseVLF];

SET @query = N'';

WHILE 1 = 1
BEGIN
    DECLARE @server sysname,
            @serverid INT;

    SELECT TOP (1)
           @server = [servername],
           @serverid = [serverid]
    FROM @servers
    ORDER BY serverid;

    IF @@rowcount = 0
        BREAK;

    SET @query
        = @query
          + N'INSERT INTO [dbo].[tDatabaseVLF] (
		ServerID,
		DatabaseName,
		VLFCount,
		AverageVLFSizeMB,
		MinVLFSizeMB,
		MaxVLFSizeMB
		)'       + N'EXEC ' + QUOTENAME(@server) + N'..sys.sp_executesql N' + N''''
          + N'SET NOCOUNT ON;
DECLARE @VersionMajor INT;
SET @VersionMajor = CONVERT(INT, SERVERPROPERTY(''''ProductMajorVersion''''));
DECLARE @cmd NVARCHAR(MAX);
DECLARE @dbID INT;
SET @cmd = N'''''''';
IF @VersionMajor >= 11
BEGIN 
    IF OBJECT_ID(N''''tempdb..#LogInfo'''', N''''U'''') IS NOT NULL
    BEGIN
        DROP TABLE #LogInfo;
    END;
    CREATE TABLE #LogInfo
    (
		DatabaseId INT NULL,
		RecoveryUnitId INT NOT NULL,
		FileId SMALLINT NOT NULL,
        FileSize FLOAT NOT NULL,
        StartOffset BIGINT NOT NULL,
        FSeqNo BIGINT NOT NULL,
        Status INT NOT NULL,
        Parity TINYINT NOT NULL,
        CreateLSN NVARCHAR(24) NOT NULL
	);

    CREATE CLUSTERED INDEX LogInfo_pk ON #LogInfo (FileId, FSeqNo);

    DECLARE @cmdi NVARCHAR(MAX);
    DECLARE cur CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY FOR
    SELECT d.database_id
    FROM sys.databases d
    WHERE d.database_id >= 4 AND d.state_desc = N''''ONLINE'''' AND d.user_access_desc = N''''MULTI_USER'''';
    OPEN cur;
    FETCH NEXT FROM cur
    INTO @dbID;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cmd = N''''DBCC LOGINFO('''' + CONVERT(nvarchar(11), @dbID) + N'''') WITH NO_INFOMSGS;''''
		SET @cmdi = N''''INSERT INTO #LogInfo WITH (TABLOCKX) (RecoveryUnitId, FileId, FileSize, StartOffset, FSeqNo, Status, Parity, CreateLSN)
EXEC ('''''''''''' + @cmd + N'''''''''''');''''
        EXEC sys.sp_executesql @cmdi;

        UPDATE #LogInfo
        SET DatabaseId = @dbID
        WHERE DatabaseId IS NULL;
        FETCH NEXT FROM cur
        INTO @dbID;
    END;
    CLOSE cur;
    DEALLOCATE cur;

       SELECT ServerID =' + CAST(@serverid AS VARCHAR(10))
          + N',DatabaseName = d.name,
           VLFCount = COUNT(1),
           AverageVLFSize = AVG(li.FileSize / 1048576.0),
           MinVLFSize = MIN(li.FileSize / 1048576.0),
           MaxVLFSize = MAX(li.FileSize / 1048576.0)
    FROM #LogInfo li
        INNER JOIN sys.databases d
            ON li.DatabaseId = d.database_id
    GROUP BY d.name;
END;

'                + N'''' + CHAR(13) + CHAR(10);


    DELETE FROM @servers
    WHERE [servername] = @server;

END;
--PRINT (@query)
EXEC (@query);




--Execute [dbo].[pRefreshDatabaseVLF]
GO



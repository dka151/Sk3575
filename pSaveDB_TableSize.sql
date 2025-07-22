USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pSaveDB_TableSize]    Script Date: 7/22/2025 11:41:08 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

  
CREATE OR ALTER PROC [dbo].[pSaveDB_TableSize]  
AS  

BEGIN  
 SET NOCOUNT ON   
  
   
  
--  --== ***  pSaveDB_TableSize ***                     
  
DECLARE @dbName varchar(255)  
       ,@tblName varchar(255)  
       ,@tName varchar(255)  
       ,@query nvarchar(max)  
       ,@OPENQUERY nvarchar(4000)  
       ,@sid nvarchar(10)  
       ,@sname nvarchar(100) ;  
  
IF OBJECT_ID('tempdb..#tmpTableOutput', 'U') IS NOT NULL  
    DROP TABLE [#tmpTableOutput];  
CREATE TABLE [#tmpTableOutput] (  
    [serverID] int NULL  
   ,[strDBName] varchar(255) COLLATE DATABASE_DEFAULT NULL  
   ,[strTableName] varchar(255) COLLATE DATABASE_DEFAULT NOT NULL  
   ,[rows] bigint NOT NULL  
   ,[reserved_KB] bigint NOT NULL  
   ,[used_KB] bigint NOT NULL  
   ,[data_KB] bigint NOT NULL  
   ,[index_size_KB] bigint NOT NULL  
   ,[unused_KB] bigint NOT NULL  
);  
  
IF OBJECT_ID('tempdb..#tempdatabaseList', 'U') IS NOT NULL  
    DROP TABLE [#tempdatabaseList];  
CREATE TABLE [#tempdatabaseList] (  
    [ServerID] int  
   ,[servername] sysname  
   ,[DBName] nvarchar(128)  
);  
  
DECLARE @servers table (  
    [servername] sysname  
   ,[serverid] int  
);  
  
INSERT  @servers  
(  
    [serverid]  
   ,[servername]  
)  
SELECT  [serverid]  
       ,[servername]  
FROM    [dbo].[tServer]  
WHERE   [IsLinked] = 1  
        AND [Active] = 1  
		AND (ServerName NOT LIKE '%MISDBS%') --NOT MIS Listeners, port is not 1433

    
  
  
SET @query = N'INSERT INTO #tempdatabaseList (  
ServerID,  
ServerName,  
DBName)';  
DECLARE @union bit;  
SET @union = 'FALSE';  
  
WHILE 1 = 1  
BEGIN  
    DECLARE @server sysname  
           ,@serverid int;  
  
    SELECT  TOP 1  
            @server = [servername]  
           ,@serverid = [serverid]  
    FROM    @servers;  
  
    IF @@rowcount = 0  
        BREAK;  
  
    IF @union = 'TRUE'  
        SET @query = @query + N' union all ' + CHAR(13) + CHAR(10);  
  
    SET @query = @query + N'SELECT ' + CAST(@serverid AS varchar(10)) + N',''' + CAST(@server AS varchar(50)) + N''',' + N'* FROM OPENQUERY ('  
                 + QUOTENAME(@server) + N','  
                 + N'''SELECT name  
FROM   master.[sys].[databases]  d
LEFT JOIN sys.dm_hadr_availability_replica_states hars ON d.replica_id = hars.replica_id
WHERE  NAME NOT IN (''''sysutility_mdw'''',''''perfmon_collector'''',''''DBA'''')  
AND (hars.role IS NULL or hars.role = 1)
AND state = 0   
AND database_id > 4'')' + CHAR(13) + CHAR(10);  
    SET @union = 'TRUE';  
  
    DELETE  FROM @servers  
    WHERE   [servername] = @server;  
  
END;  
--PRINT @query  

exec (@query);  
SELECT * FROM [#tempdatabaseList];   
 
	

  
--== *** Populating #tempdatabaseList ***  
  
SELECT  TOP (1) @sid=[ServerID], @sname=[servername], @dbname=[DBName]  
FROM    [#tempdatabaseList]  
ORDER BY [ServerID];  
  
WHILE 1=1  
BEGIN  
    DELETE  FROM [#tempdatabaseList]  
    WHERE   [DBName] = @dbName  
            AND [ServerID] = @sid;  
  
    ----save info about db size  
    SET @query = N'EXEC (''''USE ';  
    SET @query = @query + @dbName  
                 + N'  
set nocount on  
  
declare @dbsize bigint,  
@logsize bigint,  
@reservedpages bigint,  
@usedpages bigint,  
@pages bigint,  
@getdate datetime,  
@serverid int  
                  
set @getdate = convert(varchar(16), getdate(), 121)  
set @serverid = ' + @sid  
                 + N'  
select @dbsize = sum(convert(bigint, case when status & 64 = 0 then size else 0 end)),  
@logsize = sum(convert(bigint, case when status & 64 <> 0 then size else 0 end))  
from dbo.sysfiles  
  
select @reservedpages = sum(a.total_pages), @usedpages = sum(a.used_pages),  
@pages = sum(  
case  
when it.internal_type IN (202, 204) then 0  
when a.type <> 1 then a.used_pages  
when p.index_id < 2 then a.data_pages  
else 0  
end  
)  
from sys.partitions p join sys.allocation_units a on p.partition_id = a.container_id  
left join sys.internal_tables it on p.object_id = it.object_id  
  
                  
select @serverid as ServerID, @getdate as dateSaved,  
db_name() as DBName,   
cast(((@dbsize + @logsize) * 8192/1048576.) as decimal(15, 2)) "DB Size(MB)",  
(case when @dbsize >= @reservedpages then cast(((@dbsize - @reservedpages) * 8192/1048567.) as decimal(15, 2)) else 0 end) "Unalloc. Space(MB)",  
cast((@reservedpages * 8192/1048576.) as decimal(15, 2)) "Reserved(MB)",  
cast((@pages * 8192/1048576.) as decimal(15, 2)) "Data Used(MB)",  
cast(((@usedpages - @pages) * 8192/1048576.) as decimal(15, 2)) "Index Used(MB)",  
cast(((@reservedpages - @usedpages) * 8192/1048576.) as decimal(15, 2)) "Unused(MB)"  
''''); '')  
'   ;  
  
    SET @OPENQUERY = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@sname) + N',''';  
  
    INSERT INTO [dbo].[tDBGrowth]  
    (  
        [ServerID]  
       ,[DateCreated]  
       ,[strDBName]  
       ,[DBSize_MB]  
       ,[UnAllocatedSize_MB]  
       ,[Reserved_MB]  
       ,[DataUsed_MB]  
       ,[IndexUsed_MB]  
       ,[UnUsed_MB]  
    )  
    EXEC (@OPENQUERY + @query);  
  
    SET @OPENQUERY = N'SELECT * FROM OPENQUERY(' + QUOTENAME(@sname) + N',''';  
    SET @query = N'SELECT OBJECT_SCHEMA_NAME(t.object_id, DB_ID(N''''' + @dbName + ''''')) + ''''.'''' + t.name AS TableName,  
SUM(CASE WHEN i.index_id < 2 THEN p.rows ELSE 0 END) AS RowCounts,  
(SUM(ps.reserved_page_count) * 8) AS TotalSpaceReservedKB,  
(SUM(ps.used_page_count) * 8) AS UsedSpaceKB,  
(SUM(CASE WHEN (ps.index_id < 2) THEN (ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count) ELSE 0 END) * 8) AS DataKB,  
CASE WHEN (SUM(ps.used_page_count) * 8) > (SUM(CASE WHEN (ps.index_id < 2) THEN (ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count) ELSE 0 END) * 8) THEN ((SUM(ps.used_page_count) * 8) - (SUM(CASE WHEN (ps.index_id < 2)
 THEN (ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count) ELSE 0 END) * 8)) ELSE 0 END AS IndexKB,  
CASE WHEN (SUM(ps.reserved_page_count) * 8) > (SUM(ps.used_page_count) * 8) THEN ((SUM(ps.reserved_page_count) * 8) - (SUM(ps.used_page_count) * 8)) ELSE 0 END AS UnusedSpaceKB  
      
FROM ' + @dbName + N'.sys.tables t  
INNER JOIN ' + @dbName + N'.sys.indexes i ON t.OBJECT_ID = i.object_id  
INNER JOIN ' + @dbName + N'.sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id  
INNER JOIN ' + @dbName + N'.sys.dm_db_partition_stats ps ON ps.object_id = p.object_id AND ps.index_id = p.index_id AND ps.partition_number = p.partition_number  
GROUP BY t.object_id, t.name'') ';  
  
  
    DELETE #tmpTableOutput;  
    INSERT  [#tmpTableOutput]  
    (  
        [strTableName]  
       ,[rows]  
       ,[reserved_KB]  
       ,[used_KB]  
       ,[data_KB]  
       ,[index_size_KB]  
       ,[unused_KB]  
    )  
    EXEC (@OPENQUERY + @query);  
    UPDATE  [#tmpTableOutput]  
    SET     [strDBName] = @dbName  
           ,[serverID] = @sid  
    WHERE   [strDBName] IS NULL;  
  
    INSERT  [dbo].[tTableGrowth]  
    (  
        [ServerID]  
       ,[strDBName]  
       ,[strTableNAME]  
       ,[Reserved_KB]  
       ,[Data_KB]  
       ,[Index_size_KB]  
       ,[Unused_KB]  
       ,[NumberofRows]  
    )  
    SELECT  [serverID]  
           ,[strDBName]  
           ,[strTableName]  
           ,REPLACE([reserved_KB], ' KB', '') AS [reserved_KB]  --[reserved_KB]  
           ,REPLACE([data_KB], ' KB', '') AS [data_KB]          --[data_KB],  
           ,REPLACE([index_size_KB], ' KB', '') [index_size_KB]  
           ,REPLACE([unused_KB], ' KB', '') AS [unused_KB]  
           ,[ROWS]  
    FROM    [#tmpTableOutput];  
  
    IF NOT EXISTS (SELECT 1 FROM #tempdatabaseList) BREAK;  
  
    SELECT  TOP (1) @sid=[ServerID], @sname=[servername], @dbname=[DBName]--, @sid, @sname, @dbName  
    FROM    [#tempdatabaseList]  
    ORDER BY [ServerID];  
  
END;  
  
END  
  
  
  
--EXEC [dbo].[pSaveDB_TableSize]  
  
--SELECT * FROM [dbo].[tDBGrowth];    -- for debugging  
--SELECT * FROM [dbo].[tTableGrowth];    -- for debugging  
--TRUNCATE table  [dbo].[tDBGrowth];   -- for debugging  
   
--truncate  TABLE [dbo].[tTableGrowth];    -- for debugging  
GO



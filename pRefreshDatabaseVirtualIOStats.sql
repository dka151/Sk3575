USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[pRefreshDatabaseVirtualIOStats]    Script Date: 7/13/2025 2:01:15 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE OR ALTER PROC [dbo].[pRefreshDatabaseVirtualIOStats]
AS
--/*********************************************************************************************************
--* Description:	stored procedure to automatically gather Virtual IO stats from
--*					SQL Server, runs every 15mins
--* Date:			09 Apr 2020
--* Author:			Deepak Adhya
--* Example:		[dbo].[pRefreshDatabaseVirtualIOStats]
--**********************************************************************************************************/
BEGIN
    SET NOCOUNT ON;


    DECLARE @query NVARCHAR(MAX);


    IF OBJECT_ID('tempdb..#VirtualIOStats', 'U') IS NOT NULL
        DROP TABLE [#VirtualIOStats];
    CREATE TABLE [#VirtualIOStats]
    (
        [Serverid] [VARCHAR](10) NULL,
        [Servername] [NVARCHAR](100) NULL,
        [database_id] [SMALLINT] NULL,
        [file_id] [SMALLINT] NULL,
        [num_of_reads] [BIGINT] NULL,
        [io_stall_read_ms] [BIGINT] NULL,
        [num_of_writes] [BIGINT] NULL,
        [io_stall_write_ms] [BIGINT] NULL,
        [io_stall] [BIGINT] NULL,
        [num_of_bytes_read] [BIGINT] NULL,
        [num_of_bytes_written] [BIGINT] NULL,
        [file_handle] [VARBINARY](8) NULL,
        [DBName] [NVARCHAR](128) NULL,
        [Drive] [NVARCHAR](2) NULL,
        [type_desc] [NVARCHAR](60) NULL,
        [Logical_File_Name] [sysname] NULL,
        [physical_name] [NVARCHAR](260) NULL,
        [Collection_time] [DATETIME] NULL
    );

    DECLARE @servers TABLE
    (
        [ServerName] sysname NOT NULL,
        [ServerID] INT NOT NULL
    );

    INSERT @servers
    (
        [ServerID],
        [ServerName]
    )
    SELECT [ServerID],
           [ServerName]
    FROM [dbo].[tServer]
    WHERE [IsLinked] = 1
          AND [Active] = 1
          AND (ServerName LIKE '%DBS%'
              );

    --SELECT * FROM @servers;

    SET @query = N'';

    WHILE 1 = 1
    BEGIN
        DECLARE @server sysname,
                @serverid INT;

        SELECT TOP (1)
               @server = [ServerName],
               @serverid = [ServerID]
        FROM @servers
        ORDER BY ServerID;

        IF @@rowcount = 0
            BREAK;

        SET @query
            = @query
              + N'TRUNCATE TABLE [#VirtualIOStats];
		   INSERT INTO [#VirtualIOStats] (
			[Serverid],
			[Servername],
			[database_id],
			[file_id],
			[num_of_reads],
			[io_stall_read_ms],
			[num_of_writes],
			[io_stall_write_ms],
			[io_stall],
			[num_of_bytes_read],
			[num_of_bytes_written],
			[file_handle],
			[DBName],
			[Drive],
			[type_desc],
			[Logical_File_Name],
			[physical_name],
			[Collection_time]
		)'           + N'EXEC ' + QUOTENAME(@server) + N'..sys.sp_executesql N' + N'''' + N'select '
              + CAST(@serverid AS VARCHAR(10)) + N', ' + N'''''' + CAST(@server AS NVARCHAR(50)) + N'''''' + N', '
              + N'vfs.[database_id], vfs.[file_id], [num_of_reads], [io_stall_read_ms],
       [num_of_writes], [io_stall_write_ms], [io_stall],
       [num_of_bytes_read], [num_of_bytes_written], [file_handle],
	        DB_NAME([vfs].[database_id]),
           LEFT([f].[physical_name], 2),
           [f].[type_desc], [f].[Name],
           [f].[physical_name],GETUTCDATE()
FROM sys.master_files AS f WITH (NOLOCK)
CROSS APPLY sys.dm_io_virtual_file_stats (f.database_id, f.[file_id]) AS vfs;' + N'''' + CHAR(13) + CHAR(10);

        -- PRINT (@query)
        EXEC (@query);


        ;WITH [DiffLatencies]
        AS (SELECT
                -- Files that weren't in the first snapshot
                [ts2].[Serverid],
                [ts2].[Servername],
                [ts2].[database_id],
                [ts2].[file_id],
                [ts2].[num_of_reads],
                [ts2].[io_stall_read_ms],
                [ts2].[num_of_writes],
                [ts2].[io_stall_write_ms],
                [ts2].[io_stall],
                [ts2].[num_of_bytes_read],
                [ts2].[num_of_bytes_written],
                [ts2].[DBName],
                [ts2].[Drive],
                [ts2].[type_desc],
                [ts2].[Logical_File_Name],
                [ts2].[physical_name]
            FROM [#VirtualIOStats] AS [ts2]
                LEFT OUTER JOIN [dbo].[tbl_VirtualIO_Stats_Staging] AS [ts1]
                    ON [ts2].[file_handle] = [ts1].[file_handle]
                       AND [ts2].[Serverid] = [ts1].[Serverid]
                       AND [ts2].[database_id] = [ts1].[database_id]
                       AND [ts2].[file_id] = [ts1].[file_id]
            WHERE [ts1].[file_handle] IS NULL
            UNION
            SELECT
                -- Diff of latencies in both snapshots
                [ts2].[Serverid],
                REPLACE([ts2].[Servername],'-',''),
                [ts2].[database_id],
                [ts2].[file_id],
                [ts2].[num_of_reads] - [ts1].[num_of_reads] AS [num_of_reads],
                [ts2].[io_stall_read_ms] - [ts1].[io_stall_read_ms] AS [io_stall_read_ms],
                [ts2].[num_of_writes] - [ts1].[num_of_writes] AS [num_of_writes],
                [ts2].[io_stall_write_ms] - [ts1].[io_stall_write_ms] AS [io_stall_write_ms],
                [ts2].[io_stall] - [ts1].[io_stall] AS [io_stall],
                [ts2].[num_of_bytes_read] - [ts1].[num_of_bytes_read] AS [num_of_bytes_read],
                [ts2].[num_of_bytes_written] - [ts1].[num_of_bytes_written] AS [num_of_bytes_written],
                [ts2].[DBName],
                [ts2].[Drive],
                [ts2].[type_desc],
                [ts2].[Logical_File_Name],
                [ts2].[physical_name]
            FROM [#VirtualIOStats] AS [ts2]
                LEFT OUTER JOIN [dbo].[tbl_VirtualIO_Stats_Staging] AS [ts1]
                    ON [ts2].[file_handle] = [ts1].[file_handle]
                       AND [ts2].[Serverid] = [ts1].[Serverid]
                       AND [ts2].[database_id] = [ts1].[database_id]
                       AND [ts2].[file_id] = [ts1].[file_id]
            WHERE [ts1].[file_handle] IS NOT NULL)
        INSERT INTO [dbo].[tbl_VirtualIO_Stats]
        (
            [Serverid],
            [Servername],
            [DBName],
            [Drive],
            [type_desc],
            [Reads],
            [Writes],
            [ReadLatency(ms)],
            [WriteLatency(ms)],
            [Latency],
            [AvgBPerRead],
            [AvgBPerWrite],
            [AvgBPerTransfer],
            [Logical_File_Name],
            [physical_name]
        )
        SELECT [vfs].[Serverid],
               REPLACE([vfs].[Servername],'-',''),
               [vfs].[DBName],
               [vfs].[Drive],
               [vfs].[type_desc],
               [num_of_reads] AS [Reads],
               [num_of_writes] AS [Writes],
               [ReadLatency(ms)] = CASE
                                       WHEN [num_of_reads] = 0 THEN
                                           0
                                       ELSE
               ([io_stall_read_ms] / [num_of_reads])
                                   END,
               [WriteLatency(ms)] = CASE
                                        WHEN [num_of_writes] = 0 THEN
                                            0
                                        ELSE
               ([io_stall_write_ms] / [num_of_writes])
                                    END,
               [Latency] = CASE
                               WHEN
                               (
                                   [num_of_reads] = 0
                                   AND [num_of_writes] = 0
                               ) THEN
                                   0
                               ELSE
               ([io_stall] / ([num_of_reads] + [num_of_writes]))
                           END,
               [AvgBPerRead] = CASE
                                   WHEN [num_of_reads] = 0 THEN
                                       0
                                   ELSE
               ([num_of_bytes_read] / [num_of_reads])
                               END,
               [AvgBPerWrite] = CASE
                                    WHEN [num_of_writes] = 0 THEN
                                        0
                                    ELSE
               ([num_of_bytes_written] / [num_of_writes])
                                END,
               [AvgBPerTransfer] = CASE
                                       WHEN
                                       (
                                           [num_of_reads] = 0
                                           AND [num_of_writes] = 0
                                       ) THEN
                                           0
                                       ELSE
               (([num_of_bytes_read] + [num_of_bytes_written]) / ([num_of_reads] + [num_of_writes]))
                                   END,
               [vfs].[Logical_File_Name],
               [vfs].[physical_name]
        FROM [DiffLatencies] AS [vfs];

        DELETE FROM [dbo].[tbl_VirtualIO_Stats_Staging]
        WHERE [Servername] = @server;

        INSERT INTO [dbo].[tbl_VirtualIO_Stats_Staging]
        (
            [Serverid],
            [Servername],
            [database_id],
            [file_id],
            [num_of_reads],
            [io_stall_read_ms],
            [num_of_writes],
            [io_stall_write_ms],
            [io_stall],
            [num_of_bytes_read],
            [num_of_bytes_written],
            [file_handle],
            [DBName],
            [Drive],
            [type_desc],
            [Logical_File_Name],
            [physical_name],
            [Collection_time]
        )
        SELECT [Serverid],
               REPLACE([Servername],'-',''),
               [database_id],
               [file_id],
               [num_of_reads],
               [io_stall_read_ms],
               [num_of_writes],
               [io_stall_write_ms],
               [io_stall],
               [num_of_bytes_read],
               [num_of_bytes_written],
               [file_handle],
               [DBName],
               [Drive],
               [type_desc],
               [Logical_File_Name],
               [physical_name],
               [Collection_time]
        FROM [#VirtualIOStats];


        DELETE FROM @servers
        WHERE [ServerName] = @server;



    END;

	-- Cleanup
IF EXISTS (SELECT * FROM [tempdb].[sys].[objects]
    WHERE [name] = N'#VirtualIOStats')
    DROP TABLE [#VirtualIOStats];

END;

GO



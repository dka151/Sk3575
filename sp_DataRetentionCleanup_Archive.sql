USE [DBA]
GO
/****** Object:  StoredProcedure [dbo].[sp_DataRetentionCleanup]    Script Date: 9/4/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================================================
--  Object:      dbo.sp_DataRetentionCleanup
--  Purpose:     Config-driven ARCHIVE + PURGE of aged data.
--
--               For every active row in dbo.DataRetentionConfig this procedure
--               copies rows older than the retention window into a matching
--               history table (<Archive DB>.<Archive Schema>.<Table>_HIST) and
--               then deletes the same rows from the source table.
--
--               Archive and purge for a given batch happen inside ONE short
--               transaction so the two never drift out of sync. Work is done in
--               small key-based batches to keep locks short, keep the log small,
--               allow the job to be stopped/restarted safely, and avoid blocking
--               concurrent OLTP traffic.
--
--  Design notes:
--     * Batch = capture N primary-key values into a temp table, then
--       INSERT..SELECT into _HIST and DELETE from source joined on those keys.
--       Both DML statements target the exact same rows even under concurrency.
--     * Archive column list is derived dynamically from the columns that exist
--       in BOTH the source and the _HIST table (sys.columns intersection), so
--       the proc is fully generic across arbitrary tables.
--     * Deadlock (1205) and lock-timeout (1222) are retried with backoff.
--     * XACT_ABORT ON inside each transactional batch.
--     * READPAST on the key-capture read so a batch never blocks on rows an
--       OLTP transaction is currently holding.
--     * Per-config error isolation: a failure on one table is logged and the
--       procedure moves on to the next config.
--     * All activity is logged to dbo.DataRetentionCleanupLog.
--
--  Parameters:
--     @ArchiveDatabaseName  Target DB holding the _HIST tables. Default 'ARCH'.
--     @ArchiveSchemaName    Schema of the _HIST tables. Default 'dbo'.
--     @BatchDelaySeconds    Seconds to WAITFOR between batches. Default 1.
--     @LockTimeoutMs        SET LOCK_TIMEOUT for each batch, ms. Default 5000.
--     @MaxRetries           Deadlock/lock-timeout retries per batch. Default 5.
--     @ArchiveEnabled       1 = archive then delete (skip config if no _HIST);
--                           0 = purge only. Default 1.
--     @DryRun               1 = report only, change nothing. Default 0.
--     @ConfigID             Optional: process a single config row only.
--     @out_vchMessage       OUTPUT: 'SUCCESS' or an aggregated error summary.
--
--  CHANGELOG:
--     2026-09-04  Config-driven archive-before-purge, batching,
--                 deadlock/lock-timeout retry, logging, dry-run.
-- Examples
-- DECLARE @msg NVARCHAR(MAX);
-- EXEC dbo.sp_DataRetentionCleanup
--      @DryRun = 1,
--      @out_vchMessage = @msg OUTPUT;
-- SELECT @msg;

-- -- Then review:
-- SELECT ConfigID, TableName, RowsDeleted AS CandidateRows, [Message]
-- FROM dbo.DataRetentionCleanupLog
-- WHERE [Action] = 'DRYRUN'
-- ORDER BY LogID DESC;
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_DataRetentionCleanup]
    @ArchiveDatabaseName SYSNAME       = N'ARCH',
    @ArchiveSchemaName   SYSNAME       = N'dbo',
    @BatchDelaySeconds   INT           = 1,
    @LockTimeoutMs       INT           = 5000,
    @MaxRetries          INT           = 5,
    @ArchiveEnabled      BIT           = 1,
    @DryRun              BIT           = 0,
    @ConfigID            INT           = NULL,
    @out_vchMessage      NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;   -- transactions are managed explicitly per batch

    -- -------------------------------------------------------------------------
    -- Run-log table (auto-create on first run)
    -- -------------------------------------------------------------------------
    IF OBJECT_ID(N'dbo.DataRetentionCleanupLog', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DataRetentionCleanupLog
        (
            LogID            BIGINT IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_DataRetentionCleanupLog PRIMARY KEY CLUSTERED,
            RunBatchID       UNIQUEIDENTIFIER NOT NULL,
            ConfigID         INT              NULL,
            DatabaseName     SYSNAME          NULL,
            SchemaName       SYSNAME          NULL,
            TableName        SYSNAME          NULL,
            [Action]         NVARCHAR(20)     NOT NULL,   -- START/ARCHIVE/PURGE/SKIP/DRYRUN/SUCCESS/ERROR/END
            RowsArchived     BIGINT           NULL,
            RowsDeleted      BIGINT           NULL,
            [Status]         CHAR(1)          NOT NULL,   -- I(info) S(success) F(fail)
            [Message]        NVARCHAR(MAX)    NULL,
            StartTime        DATETIME2(3)     NULL,
            EndTime          DATETIME2(3)     NULL,
            DurationMs       AS DATEDIFF(MILLISECOND, StartTime, EndTime),
            LoggedAt         DATETIME2(3)     NOT NULL
                CONSTRAINT DF_DataRetentionCleanupLog_LoggedAt DEFAULT (SYSDATETIME())
        );
    END;

    -- -------------------------------------------------------------------------
    -- Local variables
    -- -------------------------------------------------------------------------
    DECLARE @RunBatchID       UNIQUEIDENTIFIER = NEWID(),
            @ConfigID_cur     INT,
            @DatabaseName     SYSNAME,
            @SchemaName       SYSNAME,
            @TableName        SYSNAME,
            @RetentionColumn  SYSNAME,
            @RetentionDays    INT,
            @BatchSize        INT,
            @CutoffDate       DATETIME2(3),
            @SQL              NVARCHAR(MAX),
            @Msg              NVARCHAR(MAX),
            @ErrCount         INT = 0,
            @ConfigStart      DATETIME2(3),
            @SrcObjId         INT,
            @HistObjId        INT,
            @KeyColList       NVARCHAR(MAX),   -- e.g. [id1],[id2]
            @KeyJoinPred      NVARCHAR(MAX),   -- e.g. s.[id1]=k.[id1] AND ...
            @ArchColList      NVARCHAR(MAX),   -- common columns for archive
            @HasHist          BIT,
            @RowsArchivedCfg  BIGINT,
            @RowsDeletedCfg   BIGINT,
            @SrcFQN           NVARCHAR(400),
            @HistTable        SYSNAME,
            @HistFQN          NVARCHAR(400);

    SET @out_vchMessage = N'SUCCESS';

    -- Log run start
    INSERT dbo.DataRetentionCleanupLog (RunBatchID, [Action], [Status], [Message], StartTime, EndTime)
    VALUES (@RunBatchID, N'START', 'I',
            N'DryRun=' + CAST(@DryRun AS VARCHAR(1)) + N', ArchiveEnabled=' + CAST(@ArchiveEnabled AS VARCHAR(1)),
            SYSDATETIME(), SYSDATETIME());

    -- -------------------------------------------------------------------------
    -- Cursor over active configs (read-only, forward-only)
    -- -------------------------------------------------------------------------
    DECLARE retention_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ConfigID, DatabaseName, SchemaName, TableName,
               RetentionColumn, RetentionPeriodDays, DeletionRowCount
        FROM dbo.DataRetentionConfig
        WHERE IsActive = 1
          AND (@ConfigID IS NULL OR ConfigID = @ConfigID)
        ORDER BY ConfigID;

    OPEN retention_cursor;
    FETCH NEXT FROM retention_cursor
        INTO @ConfigID_cur, @DatabaseName, @SchemaName, @TableName,
             @RetentionColumn, @RetentionDays, @BatchSize;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ConfigStart     = SYSDATETIME();
        SET @RowsArchivedCfg = 0;
        SET @RowsDeletedCfg  = 0;

        BEGIN TRY
            ------------------------------------------------------------------
            -- 1. Validate config values & build safe qualified names
            ------------------------------------------------------------------
            IF @RetentionDays IS NULL OR @RetentionDays <= 0
                THROW 50001, N'RetentionPeriodDays must be > 0.', 1;

            IF @BatchSize IS NULL OR @BatchSize <= 0
                SET @BatchSize = 1000;   -- safe default

            SET @CutoffDate = DATEADD(DAY, -@RetentionDays, GETDATE());

            SET @SrcFQN   = QUOTENAME(@DatabaseName) + N'.' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);
            SET @HistTable = @TableName + N'_HIST';
            SET @HistFQN  = QUOTENAME(@ArchiveDatabaseName) + N'.' + QUOTENAME(@ArchiveSchemaName) + N'.' + QUOTENAME(@HistTable);

            -- Confirm source object exists (three-part OBJECT_ID)
            SET @SQL = N'SELECT @oid = OBJECT_ID(@fqn)';
            EXEC sp_executesql @SQL, N'@fqn NVARCHAR(400), @oid INT OUTPUT',
                               @fqn = @SrcFQN, @oid = @SrcObjId OUTPUT;
            IF @SrcObjId IS NULL
                THROW 50002, N'Source table not found.', 1;

            ------------------------------------------------------------------
            -- 2. Discover primary-key columns of the source table
            ------------------------------------------------------------------
            IF OBJECT_ID(N'tempdb..#keys') IS NOT NULL DROP TABLE #keys;
            CREATE TABLE #keys (ordinal INT, col SYSNAME);

            SET @SQL = N'
                SELECT ic.key_ordinal, c.name
                FROM ' + QUOTENAME(@DatabaseName) + N'.sys.indexes i
                JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.index_columns ic
                     ON ic.object_id = i.object_id AND ic.index_id = i.index_id
                JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.columns c
                     ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE i.object_id = OBJECT_ID(@fqn) AND i.is_primary_key = 1
                ORDER BY ic.key_ordinal;';
            INSERT #keys (ordinal, col)
            EXEC sp_executesql @SQL, N'@fqn NVARCHAR(400)', @fqn = @SrcFQN;

            IF NOT EXISTS (SELECT 1 FROM #keys)
                THROW 50003, N'No primary key found; generic archive requires a PK.', 1;

            SELECT @KeyColList  = STRING_AGG(QUOTENAME(col), N',') WITHIN GROUP (ORDER BY ordinal),
                   @KeyJoinPred = STRING_AGG(N's.' + QUOTENAME(col) + N' = k.' + QUOTENAME(col), N' AND ')
                                    WITHIN GROUP (ORDER BY ordinal)
            FROM #keys;

            ------------------------------------------------------------------
            -- 3. Resolve archive target & the common column list
            ------------------------------------------------------------------
            SET @HasHist = 0;
            IF @ArchiveEnabled = 1
            BEGIN
                SET @SQL = N'SELECT @oid = OBJECT_ID(@fqn)';
                EXEC sp_executesql @SQL, N'@fqn NVARCHAR(400), @oid INT OUTPUT',
                                   @fqn = @HistFQN, @oid = @HistObjId OUTPUT;

                IF @HistObjId IS NOT NULL
                BEGIN
                    SET @HasHist = 1;

                    IF OBJECT_ID(N'tempdb..#cols') IS NOT NULL DROP TABLE #cols;
                    CREATE TABLE #cols (col SYSNAME);

                    SET @SQL = N'
                        SELECT sc.name
                        FROM ' + QUOTENAME(@DatabaseName) + N'.sys.columns sc
                        WHERE sc.object_id = OBJECT_ID(@src)
                          AND EXISTS (SELECT 1
                                      FROM ' + QUOTENAME(@ArchiveDatabaseName) + N'.sys.columns hc
                                      WHERE hc.object_id = OBJECT_ID(@hist)
                                        AND hc.name = sc.name);';
                    INSERT #cols (col)
                    EXEC sp_executesql @SQL, N'@src NVARCHAR(400), @hist NVARCHAR(400)',
                                       @src = @SrcFQN, @hist = @HistFQN;

                    SELECT @ArchColList = STRING_AGG(QUOTENAME(col), N',') FROM #cols;

                    IF @ArchColList IS NULL
                        THROW 50004, N'No common columns between source and _HIST table.', 1;
                END
                ELSE
                BEGIN
                    -- Archive requested but no _HIST target: skip this config
                    SET @Msg = N'Archive enabled but ' + @HistFQN + N' not found. Config skipped.';
                    INSERT dbo.DataRetentionCleanupLog
                        (RunBatchID, ConfigID, DatabaseName, SchemaName, TableName, [Action], [Status], [Message], StartTime, EndTime)
                    VALUES (@RunBatchID, @ConfigID_cur, @DatabaseName, @SchemaName, @TableName,
                            N'SKIP', 'I', @Msg, @ConfigStart, SYSDATETIME());
                    GOTO NEXT_CONFIG;
                END;
            END;

            ------------------------------------------------------------------
            -- 4. DRY RUN: report candidate count and move on
            ------------------------------------------------------------------
            IF @DryRun = 1
            BEGIN
                DECLARE @Candidates BIGINT;
                SET @SQL = N'SELECT @cnt = COUNT_BIG(1) FROM ' + @SrcFQN +
                           N' WITH (READUNCOMMITTED) WHERE ' + QUOTENAME(@RetentionColumn) + N' < @cut;';
                EXEC sp_executesql @SQL, N'@cut DATETIME2(3), @cnt BIGINT OUTPUT',
                                   @cut = @CutoffDate, @cnt = @Candidates OUTPUT;

                SET @Msg = N'DRY RUN: ' + CAST(@Candidates AS NVARCHAR(20)) +
                           N' row(s) older than ' + CONVERT(NVARCHAR(30), @CutoffDate, 121) +
                           N' would be ' + CASE WHEN @HasHist = 1 THEN N'archived+purged.' ELSE N'purged.' END;
                INSERT dbo.DataRetentionCleanupLog
                    (RunBatchID, ConfigID, DatabaseName, SchemaName, TableName, [Action], RowsArchived, RowsDeleted, [Status], [Message], StartTime, EndTime)
                VALUES (@RunBatchID, @ConfigID_cur, @DatabaseName, @SchemaName, @TableName,
                        N'DRYRUN', @Candidates, @Candidates, 'I', @Msg, @ConfigStart, SYSDATETIME());
                GOTO NEXT_CONFIG;
            END;

            ------------------------------------------------------------------
            -- 5. Batch loop: capture keys -> archive -> delete (one txn/batch)
            ------------------------------------------------------------------
            DECLARE @Retry INT, @BatchRows INT, @ErrNum INT, @Xstate INT;

            WHILE 1 = 1
            BEGIN
                SET @Retry = @MaxRetries;

              RETRY_BATCH:
                SET LOCK_TIMEOUT @LockTimeoutMs;
                SET XACT_ABORT ON;

                BEGIN TRY
                    IF OBJECT_ID(N'tempdb..#batch_keys') IS NOT NULL DROP TABLE #batch_keys;

                    -- 5a. Capture a batch of PK values for aged rows.
                    --     READPAST skips rows currently locked by OLTP (no blocking).
                    SET @SQL = N'
                        SELECT TOP (@bs) ' + @KeyColList + N'
                        INTO #batch_keys
                        FROM ' + @SrcFQN + N' AS s WITH (READPAST)
                        WHERE s.' + QUOTENAME(@RetentionColumn) + N' < @cut
                        ORDER BY ' + @KeyColList + N';';
                    EXEC sp_executesql @SQL, N'@bs INT, @cut DATETIME2(3)',
                                       @bs = @BatchSize, @cut = @CutoffDate;
                    SET @BatchRows = @@ROWCOUNT;

                    IF @BatchRows = 0
                    BEGIN
                        IF OBJECT_ID(N'tempdb..#batch_keys') IS NOT NULL DROP TABLE #batch_keys;
                        BREAK;   -- nothing left for this config
                    END;

                    BEGIN TRANSACTION;

                        -- 5b. Archive this batch (if a _HIST target exists)
                        IF @HasHist = 1
                        BEGIN
                            SET @SQL = N'
                                INSERT INTO ' + @HistFQN + N' (' + @ArchColList + N')
                                SELECT ' + @ArchColList + N'
                                FROM ' + @SrcFQN + N' AS s
                                JOIN #batch_keys AS k ON ' + @KeyJoinPred + N';';
                            EXEC sp_executesql @SQL;
                            SET @RowsArchivedCfg = @RowsArchivedCfg + @@ROWCOUNT;
                        END;

                        -- 5c. Delete the same batch from source
                        SET @SQL = N'
                            DELETE s
                            FROM ' + @SrcFQN + N' AS s
                            JOIN #batch_keys AS k ON ' + @KeyJoinPred + N';';
                        EXEC sp_executesql @SQL;
                        SET @RowsDeletedCfg = @RowsDeletedCfg + @@ROWCOUNT;

                    COMMIT TRANSACTION;

                    IF OBJECT_ID(N'tempdb..#batch_keys') IS NOT NULL DROP TABLE #batch_keys;
                END TRY
                BEGIN CATCH
                    SET @ErrNum = ERROR_NUMBER();
                    SET @Xstate = XACT_STATE();

                    IF @Xstate <> 0 ROLLBACK TRANSACTION;

                    IF OBJECT_ID(N'tempdb..#batch_keys') IS NOT NULL DROP TABLE #batch_keys;

                    -- Retry on deadlock (1205) or lock timeout (1222)
                    IF (@ErrNum IN (1205, 1222) AND @Retry > 0)
                    BEGIN
                        SET @Retry = @Retry - 1;
                        SET XACT_ABORT OFF;
                        WAITFOR DELAY '00:00:02';   -- backoff
                        GOTO RETRY_BATCH;
                    END;

                    THROW;   -- non-retryable / retries exhausted -> outer CATCH
                END CATCH;

                SET XACT_ABORT OFF;

                -- Yield to concurrent OLTP traffic between batches
                IF @BatchDelaySeconds > 0
                BEGIN
                    DECLARE @delay CHAR(8) =
                        RIGHT('00' + CAST(@BatchDelaySeconds / 3600 AS VARCHAR(2)), 2) + ':' +
                        RIGHT('00' + CAST((@BatchDelaySeconds % 3600) / 60 AS VARCHAR(2)), 2) + ':' +
                        RIGHT('00' + CAST(@BatchDelaySeconds % 60 AS VARCHAR(2)), 2);
                    WAITFOR DELAY @delay;
                END;
            END; -- batch loop

            ------------------------------------------------------------------
            -- 6. Log per-config success
            ------------------------------------------------------------------
            SET @Msg = N'Archived ' + CAST(@RowsArchivedCfg AS NVARCHAR(20)) +
                       N', purged ' + CAST(@RowsDeletedCfg AS NVARCHAR(20)) +
                       N' from ' + @SrcFQN +
                       CASE WHEN @HasHist = 0 THEN N' (purge only)' ELSE N'' END + N'.';
            INSERT dbo.DataRetentionCleanupLog
                (RunBatchID, ConfigID, DatabaseName, SchemaName, TableName, [Action], RowsArchived, RowsDeleted, [Status], [Message], StartTime, EndTime)
            VALUES (@RunBatchID, @ConfigID_cur, @DatabaseName, @SchemaName, @TableName,
                    N'SUCCESS', @RowsArchivedCfg, @RowsDeletedCfg, 'S', @Msg, @ConfigStart, SYSDATETIME());
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            SET XACT_ABORT OFF;
            SET @ErrCount = @ErrCount + 1;

            SET @Msg = N'ERROR ' + CAST(ERROR_NUMBER() AS NVARCHAR(20)) +
                       N' at line ' + CAST(ERROR_LINE() AS NVARCHAR(10)) +
                       N': ' + ERROR_MESSAGE();
            INSERT dbo.DataRetentionCleanupLog
                (RunBatchID, ConfigID, DatabaseName, SchemaName, TableName, [Action], RowsArchived, RowsDeleted, [Status], [Message], StartTime, EndTime)
            VALUES (@RunBatchID, @ConfigID_cur, @DatabaseName, @SchemaName, @TableName,
                    N'ERROR', @RowsArchivedCfg, @RowsDeletedCfg, 'F', @Msg, @ConfigStart, SYSDATETIME());
            -- continue with next config (error isolation)
        END CATCH;

      NEXT_CONFIG:
        FETCH NEXT FROM retention_cursor
            INTO @ConfigID_cur, @DatabaseName, @SchemaName, @TableName,
                 @RetentionColumn, @RetentionDays, @BatchSize;
    END; -- cursor loop

    CLOSE retention_cursor;
    DEALLOCATE retention_cursor;

    -- -------------------------------------------------------------------------
    -- Final run summary
    -- -------------------------------------------------------------------------
    IF @ErrCount > 0
        SET @out_vchMessage = N'COMPLETED WITH ' + CAST(@ErrCount AS NVARCHAR(10)) +
                              N' ERROR(S). See dbo.DataRetentionCleanupLog RunBatchID = ' +
                              CAST(@RunBatchID AS NVARCHAR(40)) + N'.';
    ELSE
        SET @out_vchMessage = N'SUCCESS';

    INSERT dbo.DataRetentionCleanupLog (RunBatchID, [Action], [Status], [Message], StartTime, EndTime)
    VALUES (@RunBatchID, N'END', CASE WHEN @ErrCount > 0 THEN 'F' ELSE 'S' END,
            @out_vchMessage, SYSDATETIME(), SYSDATETIME());

    RETURN CASE WHEN @ErrCount > 0 THEN 1 ELSE 0 END;
END;
GO

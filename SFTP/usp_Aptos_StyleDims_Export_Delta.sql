/*
    Aptos Style Dims - DELTA export
    Database : DBA   (deploy on AZUSW1APSQL03)

    How it works
      1. usp_Aptos_StyleDims_Export builds the full list (same logic as before),
         compares it with dbo.Aptos_StyleDims_Sent and returns ONLY:
            - Codes never sent before, or
            - Codes where Weight / Height / Width / Depth differ from what was last sent.
         The first run (empty Sent table) therefore returns everything.
      2. The returned rows are parked in dbo.Aptos_StyleDims_Pending and a @BatchId
         is returned through the OUTPUT parameter.
      3. ONLY AFTER the file is delivered to Aptos, the PowerShell script calls
         usp_Aptos_StyleDims_Commit @BatchId, which copies the pending rows into Sent.
         If the upload fails, nothing is committed and the next run sends the same
         changes again (nothing is lost).

    Parameters of usp_Aptos_StyleDims_Export
      @WhId             warehouse (default '282999')
      @ExcludeZeroDims  1 = skip styles with all four values 0/NULL (default 1)
      @FullExport       1 = ignore history and return everything (re-seed)
      @BatchId          OUTPUT. NULL when there is nothing to send.

    Reset / re-seed: run with @FullExport = 1, or TRUNCATE TABLE dbo.Aptos_StyleDims_Sent.
*/
USE [DBA];
GO

/* ---------------------------------------------------------------- tables */
IF OBJECT_ID('dbo.Aptos_StyleDims_Sent', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Aptos_StyleDims_Sent
    (
        Code         nvarchar(200) COLLATE Latin1_General_BIN NOT NULL,
        [Weight]     decimal(18,2) NOT NULL,
        [Height]     decimal(18,2) NOT NULL,
        [Width]      decimal(18,2) NOT NULL,
        [Depth]      decimal(18,2) NOT NULL,
        FirstSentUtc datetime2(0)  NOT NULL CONSTRAINT DF_AptosSent_First DEFAULT SYSUTCDATETIME(),
        LastSentUtc  datetime2(0)  NOT NULL CONSTRAINT DF_AptosSent_Last  DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Aptos_StyleDims_Sent PRIMARY KEY CLUSTERED (Code)
    );
END
GO

IF OBJECT_ID('dbo.Aptos_StyleDims_Pending', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Aptos_StyleDims_Pending
    (
        BatchId     uniqueidentifier NOT NULL,
        Code        nvarchar(200) COLLATE Latin1_General_BIN NOT NULL,
        [Weight]    decimal(18,2) NOT NULL,
        [Height]    decimal(18,2) NOT NULL,
        [Width]     decimal(18,2) NOT NULL,
        [Depth]     decimal(18,2) NOT NULL,
        CreatedUtc  datetime2(0)  NOT NULL CONSTRAINT DF_AptosPending_Created DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Aptos_StyleDims_Pending PRIMARY KEY CLUSTERED (Code)
    );
END
GO

/* ------------------------------------------------------------ export proc */
CREATE OR ALTER PROCEDURE [dbo].[usp_Aptos_StyleDims_Export]
    @WhId            varchar(20)      = '282999',
    @ExcludeZeroDims bit              = 1,
    @FullExport      bit              = 0,
    @BatchId         uniqueidentifier = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @BatchId = NULL;

    DROP TABLE IF EXISTS #items;
    DROP TABLE IF EXISTS #styles;
    DROP TABLE IF EXISTS #aptos_style;
    DROP TABLE IF EXISTS #final;
    DROP TABLE IF EXISTS #delta;

    /* 1. Koerber items for the warehouse */
    SELECT  t.item_number,
            style_code  = LEFT(t.description, CHARINDEX(':', t.description) - 1),
            t.length,
            t.width,
            t.height,
            t.unit_weight
    INTO    #items
    FROM    [PHXWAWSSDB2P].[AAD].[dbo].[t_item_master] t WITH (NOLOCK)
    WHERE   t.wh_id = @WhId
      AND   CHARINDEX(':', t.description) > 1;

    /* 2. Existing Aptos styles */
    SELECT  s.style_id,
            s.style_code
    INTO    #styles
    FROM    [EPICORSQL].[me_wsl_01].[dbo].[style] s;

    /* 3. One row per style, max of each dimension */
    SELECT  s.style_id,
            s.style_code,
            length      = MAX(i.length),
            width       = MAX(i.width),
            height      = MAX(i.height),
            unit_weight = MAX(i.unit_weight)
    INTO    #aptos_style
    FROM    (SELECT DISTINCT item_number, style_code, length, width, height, unit_weight
             FROM #items) i
    JOIN    #styles s
            ON i.style_code COLLATE Latin1_General_BIN = s.style_code COLLATE Latin1_General_BIN
    GROUP BY s.style_id, s.style_code;

    /* 4. Full current picture (rounded exactly as it is sent to Aptos) */
    SELECT  Code     = CAST(style_code COLLATE Latin1_General_BIN AS nvarchar(200)),
            [Weight] = CAST(ROUND(ISNULL(unit_weight, 0), 2) AS decimal(18,2)),
            [Height] = CAST(ROUND(ISNULL(height,      0), 2) AS decimal(18,2)),
            [Width]  = CAST(ROUND(ISNULL(width,       0), 2) AS decimal(18,2)),
            [Depth]  = CAST(ROUND(ISNULL(length,      0), 2) AS decimal(18,2))
    INTO    #final
    FROM    #aptos_style
    WHERE   @ExcludeZeroDims = 0
       OR   ISNULL(unit_weight, 0) > 0
       OR   ISNULL(height, 0)      > 0
       OR   ISNULL(width, 0)       > 0
       OR   ISNULL(length, 0)      > 0;

    /* 5. Delta = new codes + codes whose Weight/Height/Width/Depth changed */
    SELECT  f.Code, f.[Weight], f.[Height], f.[Width], f.[Depth]
    INTO    #delta
    FROM    #final f
    LEFT JOIN dbo.Aptos_StyleDims_Sent s
            ON s.Code = f.Code
    WHERE   @FullExport = 1
       OR   s.Code IS NULL
       OR   s.[Weight] <> f.[Weight]
       OR   s.[Height] <> f.[Height]
       OR   s.[Width]  <> f.[Width]
       OR   s.[Depth]  <> f.[Depth];

    /* 6. Park the delta until the file is confirmed delivered */
    BEGIN TRAN;

        DELETE FROM dbo.Aptos_StyleDims_Pending;       -- drop any uncommitted earlier run

        IF EXISTS (SELECT 1 FROM #delta)
        BEGIN
            SET @BatchId = NEWID();

            INSERT dbo.Aptos_StyleDims_Pending (BatchId, Code, [Weight], [Height], [Width], [Depth])
            SELECT @BatchId, Code, [Weight], [Height], [Width], [Depth]
            FROM   #delta;
        END

    COMMIT;

    /* 7. Result set in Aptos import layout (first 3 columns are fixed values) */
    SELECT  [Style]        = 'Style',
            [Action]       = 'update',
            [EntityAction] = CAST(NULL AS varchar(10)),
            [Code]         = Code,
            [Weight],
            [Height],
            [Width],
            [Depth]
    FROM    #delta
    ORDER BY Code;
END
GO

/* ------------------------------------------------------------ commit proc */
CREATE OR ALTER PROCEDURE [dbo].[usp_Aptos_StyleDims_Commit]
    @BatchId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Aptos_StyleDims_Pending WHERE BatchId = @BatchId)
        THROW 50001, 'usp_Aptos_StyleDims_Commit: no pending rows for this BatchId (already committed or superseded by a newer run).', 1;

    BEGIN TRAN;

        UPDATE s
        SET    s.[Weight]    = p.[Weight],
               s.[Height]    = p.[Height],
               s.[Width]     = p.[Width],
               s.[Depth]     = p.[Depth],
               s.LastSentUtc = SYSUTCDATETIME()
        FROM   dbo.Aptos_StyleDims_Sent s
        JOIN   dbo.Aptos_StyleDims_Pending p
               ON p.Code = s.Code
        WHERE  p.BatchId = @BatchId;

        INSERT dbo.Aptos_StyleDims_Sent (Code, [Weight], [Height], [Width], [Depth])
        SELECT p.Code, p.[Weight], p.[Height], p.[Width], p.[Depth]
        FROM   dbo.Aptos_StyleDims_Pending p
        WHERE  p.BatchId = @BatchId
          AND  NOT EXISTS (SELECT 1 FROM dbo.Aptos_StyleDims_Sent s WHERE s.Code = p.Code);

        DELETE FROM dbo.Aptos_StyleDims_Pending WHERE BatchId = @BatchId;

    COMMIT;
END
GO

/* Permissions for the job account (ownership chaining covers the tables) */
-- GRANT EXECUTE ON dbo.usp_Aptos_StyleDims_Export TO [WSS\AzSQLService];
-- GRANT EXECUTE ON dbo.usp_Aptos_StyleDims_Commit TO [WSS\AzSQLService];
GO

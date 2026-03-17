-- =============================================
-- Export CSV + SFTP Upload Combined Procedure
-- =============================================

USE [WSS_ATOS];
GO

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'ExportAndUploadToSFTP' AND type = 'P')
    DROP PROCEDURE dbo.ExportAndUploadToSFTP;
GO

CREATE PROCEDURE dbo.ExportAndUploadToSFTP
    @host NVARCHAR(255),
    @port INT,
    @username NVARCHAR(100),
    @password NVARCHAR(100),
    @localFilePath NVARCHAR(500),
    @remoteFilePath NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @bcpCmd NVARCHAR(4000);
    DECLARE @dbName NVARCHAR(128) = DB_NAME();
    DECLARE @logFile NVARCHAR(500) = REPLACE(@localFilePath, '.csv', '.log');
    DECLARE @logCmd NVARCHAR(4000);
    DECLARE @timestamp NVARCHAR(50) = CONVERT(NVARCHAR(50), GETDATE(), 121);

    -- Temp table to capture xp_cmdshell output
    CREATE TABLE #CmdOutput (LineId INT IDENTITY(1,1), OutputLine NVARCHAR(4000));

    -- Initialize log file
    SET @logCmd = 'echo [' + @timestamp + '] ExportAndUploadToSFTP started > "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    -- Step 1: Export CSV header
    SET @logCmd = 'echo [' + @timestamp + '] Step 1: Writing CSV header >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @headerCmd NVARCHAR(4000);
    SET @headerCmd = 'echo Divisionlabel,Dept,SubDept,Class,ExtendedColDesc,style_code,SKU,long_desc,size_code,Vendor,Brand,season_code,Cost,MSRP,SellingPrice,PriceStatus > "' + @localFilePath + '"';

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @headerCmd;

    IF EXISTS (SELECT 1 FROM #CmdOutput WHERE OutputLine LIKE '%error%' OR OutputLine LIKE '%denied%')
    BEGIN
        SET @logCmd = 'echo [' + @timestamp + '] ERROR: Failed to write CSV header >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        -- Log the actual error details
        DECLARE @headerErr NVARCHAR(4000);
        SELECT TOP 1 @headerErr = OutputLine FROM #CmdOutput WHERE OutputLine IS NOT NULL;
        SET @logCmd = 'echo [' + @timestamp + '] Detail: ' + ISNULL(@headerErr, 'Unknown') + ' >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        SELECT 'ERROR: Failed to write CSV header. See log: ' + @logFile AS Result;
        DROP TABLE #CmdOutput;
        RETURN;
    END

    SET @logCmd = 'echo [' + @timestamp + '] Step 1: CSV header written successfully >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;
    TRUNCATE TABLE #CmdOutput;

    -- Step 2: Export data using bcp via stored procedure
    SET @logCmd = 'echo [' + @timestamp + '] Step 2: Running BCP export >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    SET @bcpCmd = 'bcp "EXEC ' + @dbName + '.mer.MerchHierarchy_Hilco" queryout "' + @localFilePath + '.tmp" -c -t"," -T -S ' + @@SERVERNAME;

    -- Log the bcp command
    SET @logCmd = 'echo [' + @timestamp + '] BCP Command: ' + @bcpCmd + ' >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @bcpCmd;

    -- Log all bcp output
    DECLARE @bcpLine NVARCHAR(4000);
    DECLARE bcpCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT OutputLine FROM #CmdOutput WHERE OutputLine IS NOT NULL;
    OPEN bcpCursor;
    FETCH NEXT FROM bcpCursor INTO @bcpLine;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @logCmd = 'echo [' + @timestamp + '] BCP: ' + @bcpLine + ' >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        FETCH NEXT FROM bcpCursor INTO @bcpLine;
    END
    CLOSE bcpCursor;
    DEALLOCATE bcpCursor;

    IF NOT EXISTS (SELECT 1 FROM #CmdOutput WHERE OutputLine LIKE '%rows copied%')
    BEGIN
        SET @logCmd = 'echo [' + @timestamp + '] ERROR: BCP export failed - no rows copied >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        SELECT 'ERROR: BCP export failed. See log: ' + @logFile AS Result;
        DROP TABLE #CmdOutput;
        RETURN;
    END

    SET @logCmd = 'echo [' + @timestamp + '] Step 2: BCP export completed successfully >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;
    TRUNCATE TABLE #CmdOutput;

    -- Append data to header file and clean up temp file
    SET @logCmd = 'echo [' + @timestamp + '] Step 2b: Appending data to CSV >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @appendCmd NVARCHAR(4000);
    SET @appendCmd = 'type "' + @localFilePath + '.tmp" >> "' + @localFilePath + '" & del "' + @localFilePath + '.tmp"';

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @appendCmd;

    TRUNCATE TABLE #CmdOutput;

    -- Step 3: Zip the CSV file
    DECLARE @zipPath NVARCHAR(500) = REPLACE(@localFilePath, '.csv', '.zip');
    SET @logCmd = 'echo [' + @timestamp + '] Step 3: Zipping CSV to ' + @zipPath + ' >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @zipCmd NVARCHAR(4000);
    SET @zipCmd = 'powershell -Command "Compress-Archive -Path ''' + @localFilePath + ''' -DestinationPath ''' + @zipPath + ''' -Force"';

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @zipCmd;

    IF EXISTS (SELECT 1 FROM #CmdOutput WHERE OutputLine LIKE '%error%' OR OutputLine LIKE '%exception%')
    BEGIN
        DECLARE @zipErr NVARCHAR(4000);
        SELECT TOP 1 @zipErr = OutputLine FROM #CmdOutput WHERE OutputLine IS NOT NULL;
        SET @logCmd = 'echo [' + @timestamp + '] ERROR: Failed to zip - ' + ISNULL(@zipErr, 'Unknown') + ' >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        SELECT 'ERROR: Failed to zip. See log: ' + @logFile AS Result;
        DROP TABLE #CmdOutput;
        RETURN;
    END

    SET @logCmd = 'echo [' + @timestamp + '] Step 3: Zip completed successfully >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;
    TRUNCATE TABLE #CmdOutput;

    -- Step 4: Verify zip file exists
    DECLARE @checkZip NVARCHAR(4000) = 'if exist "' + @zipPath + '" (echo EXISTS) else (echo MISSING)';

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @checkZip;

    IF NOT EXISTS (SELECT 1 FROM #CmdOutput WHERE OutputLine LIKE '%EXISTS%')
    BEGIN
        SET @logCmd = 'echo [' + @timestamp + '] ERROR: Zip file not found at ' + @zipPath + ' >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        SELECT 'ERROR: Zip file not created. See log: ' + @logFile AS Result;
        DROP TABLE #CmdOutput;
        RETURN;
    END

    DROP TABLE #CmdOutput;

    -- Step 5: Upload zip to SFTP
    SET @logCmd = 'echo [' + @timestamp + '] Step 5: Uploading zip to SFTP >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @remoteZipPath NVARCHAR(500) = REPLACE(@remoteFilePath, '.csv', '.zip');

    EXEC dbo.UploadToSFTP
        @host = @host,
        @port = @port,
        @username = @username,
        @password = @password,
        @localFilePath = @zipPath,
        @remoteFilePath = @remoteZipPath;

    SET @timestamp = CONVERT(NVARCHAR(50), GETDATE(), 121);
    SET @logCmd = 'echo [' + @timestamp + '] ExportAndUploadToSFTP completed successfully >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    SELECT 'SUCCESS: File exported, zipped, and uploaded. Log: ' + @logFile AS Result;
END
GO

PRINT 'ExportAndUploadToSFTP procedure created successfully!';
GO

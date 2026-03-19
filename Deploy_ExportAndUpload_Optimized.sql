-- =============================================
-- Export CSV + SFTP Upload Combined Procedure
-- OPTIMIZED APPROACH: Streaming I/O (faster for large files)
-- =============================================

USE [WSS_APTOS];
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
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @bcpCmd NVARCHAR(4000);
    DECLARE @dbName NVARCHAR(128) = DB_NAME();
    DECLARE @logFile NVARCHAR(500) = 'H:\SFTP_CLR\SFTP_UPLOAD_SO_058_WSS_MerchHierarchyHilco.log';
    DECLARE @logCmd NVARCHAR(4000);
    DECLARE @timestamp NVARCHAR(50) = CONVERT(NVARCHAR(50), GETDATE(), 121);
    DECLARE @executionTime NVARCHAR(50) = 'ExecutionTime: ' + CONVERT(NVARCHAR(50), GETDATE(), 108);
    DECLARE @executionDate NVARCHAR(100) = 'Executed: ' + DATENAME(WEEKDAY, GETDATE()) + ', ' + DATENAME(MONTH, GETDATE()) + ' ' + CAST(DAY(GETDATE()) AS NVARCHAR) + ', ' + CAST(YEAR(GETDATE()) AS NVARCHAR);

    -- Temp table to capture xp_cmdshell output
    CREATE TABLE #CmdOutput (LineId INT IDENTITY(1,1), OutputLine NVARCHAR(4000));

    -- Initialize log file
    SET @logCmd = 'echo [' + @timestamp + '] ExportAndUploadToSFTP started > "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    -- Step 1: Write execution details and CSV header
    SET @logCmd = 'echo [' + @timestamp + '] Step 1: Writing execution details and CSV header >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    -- Write execution time (first row)
    DECLARE @execTimeCmd NVARCHAR(4000);
    SET @execTimeCmd = 'echo ' + @executionTime + ' > "' + @localFilePath + '"';
    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @execTimeCmd;

    -- Write execution date (second row)
    DECLARE @execDateCmd NVARCHAR(4000);
    SET @execDateCmd = 'echo ' + @executionDate + ' >> "' + @localFilePath + '"';
    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @execDateCmd;

    -- Write empty row (third row)
    DECLARE @emptyRowCmd NVARCHAR(4000);
    SET @emptyRowCmd = 'echo. >> "' + @localFilePath + '"';
    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @emptyRowCmd;

    -- Write header row (fourth row)
    DECLARE @headerCmd NVARCHAR(4000);
    SET @headerCmd = 'echo Divisionlabel,Dept,SubDept,Class,ExtendedColDesc,style_code,size_code,SKU,long_desc,Vendor1,Brand,season_code,Cost,MSRP,SellingPrice,PriceStatus >> "' + @localFilePath + '"';
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

    -- Verify CSV file was created
    TRUNCATE TABLE #CmdOutput;
    DECLARE @checkCsv NVARCHAR(4000) = 'if exist "' + @localFilePath + '" (echo EXISTS) else (echo MISSING)';

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @checkCsv;

    IF NOT EXISTS (SELECT 1 FROM #CmdOutput WHERE OutputLine LIKE '%EXISTS%')
    BEGIN
        SET @logCmd = 'echo [' + @timestamp + '] ERROR: CSV file was not created at ' + @localFilePath + ' >> "' + @logFile + '"';
        EXEC xp_cmdshell @logCmd, no_output;
        SELECT 'ERROR: CSV file not created. See log: ' + @logFile AS Result;
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

    -- Step 2b: Left-align, quote fields with commas, and add $ to price columns (OPTIMIZED STREAMING APPROACH)
    SET @logCmd = 'echo [' + @timestamp + '] Step 2b: Left-aligning fields, quoting commas, and formatting prices >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @alignCmd NVARCHAR(4000);
    SET @alignCmd = 'powershell -Command "$reader = [System.IO.File]::OpenText(''' + @localFilePath + '.tmp''); $writer = [System.IO.StreamWriter]::new(''' + @localFilePath + '.tmp2''); while ($null -ne ($line = $reader.ReadLine())) { $f = $line -split '',''; for ($i=0; $i -lt $f.Length; $i++) { $f[$i] = $f[$i].TrimStart(); if ($f[$i] -like ''*,*'') { $f[$i] = '''''''''' + $f[$i] + '''''''''' }; if ($i -eq 12 -or $i -eq 13 -or $i -eq 14) { if ($f[$i]) { if ($f[$i] -like '''''''''''*'''''''''''') { $f[$i] = '''''''''''$'''' + $f[$i].Substring(1, $f[$i].Length-2) + '''''''''' } else { $f[$i] = ''''''''$'''' + $f[$i] } } } }; $writer.WriteLine($f -join '','') }; $reader.Close(); $writer.Close()"';

    INSERT INTO #CmdOutput (OutputLine)
    EXEC xp_cmdshell @alignCmd;

    TRUNCATE TABLE #CmdOutput;

    -- Append aligned data to header file and clean up temp files
    SET @logCmd = 'echo [' + @timestamp + '] Step 2c: Appending data to CSV >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @appendCmd NVARCHAR(4000);
    SET @appendCmd = 'type "' + @localFilePath + '.tmp2" >> "' + @localFilePath + '" & del "' + @localFilePath + '.tmp" & del "' + @localFilePath + '.tmp2"';

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

    -- Step 6: Delete the CSV file after successful upload
    SET @logCmd = 'echo [' + @timestamp + '] Step 6: Deleting CSV file >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    DECLARE @deleteCmd NVARCHAR(4000) = 'del "' + @localFilePath + '"';
    EXEC xp_cmdshell @deleteCmd, no_output;

    SET @logCmd = 'echo [' + @timestamp + '] Step 6: CSV file deleted successfully >> "' + @logFile + '"';
    EXEC xp_cmdshell @logCmd, no_output;

    SELECT 'SUCCESS: File exported, zipped, and uploaded. CSV deleted. Log: ' + @logFile AS Result;
END
GO

PRINT 'ExportAndUploadToSFTP procedure created successfully!';
GO

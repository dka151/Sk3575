-- =============================================
-- Export CSV + SFTP Upload Combined Procedure
-- =============================================

USE [YourDatabaseName]; -- CHANGE THIS TO YOUR DATABASE NAME
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
    DECLARE @result INT;
    DECLARE @dbName NVARCHAR(128) = DB_NAME();
    DECLARE @errorLog NVARCHAR(500) = REPLACE(@localFilePath, '.csv', '_error.log');

    -- Step 1: Export CSV header
    DECLARE @headerCmd NVARCHAR(4000);
    SET @headerCmd = 'echo Divisionlabel,Dept,SubDept,Class,ExtendedColDesc,style_code,SKU,long_desc,size_code,Vendor,Brand,season_code,Cost,MSRP,SellingPrice,PriceStatus > "' + @localFilePath + '"';

    EXEC @result = xp_cmdshell @headerCmd, no_output;
    IF @result <> 0
    BEGIN
        SELECT 'ERROR: Failed to write CSV header' AS Result;
        RETURN;
    END

    -- Step 2: Export data using bcp via stored procedure
    SET @bcpCmd = 'bcp "EXEC ' + @dbName + '.mer.MerchHierarchy_Hilco" queryout "' + @localFilePath + '.tmp" -c -t"," -T -S ' + @@SERVERNAME + ' -e "' + @errorLog + '"';

    EXEC @result = xp_cmdshell @bcpCmd;
    IF @result <> 0
    BEGIN
        SELECT 'ERROR: BCP export failed. Check ' + @errorLog AS Result;
        RETURN;
    END

    -- Append data to header file and clean up temp file
    DECLARE @appendCmd NVARCHAR(4000);
    SET @appendCmd = 'type "' + @localFilePath + '.tmp" >> "' + @localFilePath + '" & del "' + @localFilePath + '.tmp"';
    EXEC xp_cmdshell @appendCmd, no_output;

    -- Step 3: Zip the CSV file
    DECLARE @zipPath NVARCHAR(500) = REPLACE(@localFilePath, '.csv', '.zip');
    DECLARE @zipCmd NVARCHAR(4000);
    SET @zipCmd = 'powershell -Command "Compress-Archive -Path ''' + @localFilePath + ''' -DestinationPath ''' + @zipPath + ''' -Force"';

    EXEC @result = xp_cmdshell @zipCmd;
    IF @result <> 0
    BEGIN
        SELECT 'ERROR: Failed to zip CSV file' AS Result;
        RETURN;
    END

    -- Step 4: Upload zip to SFTP
    DECLARE @remoteZipPath NVARCHAR(500) = REPLACE(@remoteFilePath, '.csv', '.zip');

    EXEC dbo.UploadToSFTP
        @host = @host,
        @port = @port,
        @username = @username,
        @password = @password,
        @localFilePath = @zipPath,
        @remoteFilePath = @remoteZipPath;

    SELECT 'SUCCESS: File exported, zipped, and uploaded' AS Result;
END
GO

PRINT 'ExportAndUploadToSFTP procedure created successfully!';
GO

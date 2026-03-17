-- =============================================
-- SQL CLR SFTP Upload Deployment Script
-- =============================================

USE [YourDatabaseName]; -- CHANGE THIS TO YOUR DATABASE NAME
GO

-- Step 1: Enable CLR Integration
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;
GO

-- Step 2: Set database to TRUSTWORTHY (required for EXTERNAL_ACCESS)
ALTER DATABASE [YourDatabaseName] SET TRUSTWORTHY ON; -- CHANGE THIS TO YOUR DATABASE NAME
GO

-- Step 3: Drop existing objects if they exist
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'UploadToSFTP' AND type = 'PC')
    DROP PROCEDURE dbo.UploadToSFTP;
GO

IF EXISTS (SELECT * FROM sys.assemblies WHERE name = 'SFTPUploader')
    DROP ASSEMBLY SFTPUploader;
GO

IF EXISTS (SELECT * FROM sys.assemblies WHERE name = 'SshNet')
    DROP ASSEMBLY SshNet;
GO

-- Step 4: Create SSH.NET assembly (dependency)
-- NOTE: Update the path to where your SSH.NET DLL is located after building
CREATE ASSEMBLY SshNet
FROM 'C:\GITLAB_Clone_Repos\SFTP_CLR\bin\Debug\net48\Renci.SshNet.dll'
WITH PERMISSION_SET = UNSAFE;
GO

-- Step 5: Create the main SFTP Uploader assembly
-- NOTE: Update the path to where your compiled DLL is located
CREATE ASSEMBLY SFTPUploader
FROM 'C:\GITLAB_Clone_Repos\SFTP_CLR\bin\Debug\net48\SFTPUploader.dll'
WITH PERMISSION_SET = UNSAFE;
GO

-- Step 6: Create the stored procedure
CREATE PROCEDURE dbo.UploadToSFTP
    @host NVARCHAR(255),
    @port INT,
    @username NVARCHAR(100),
    @password NVARCHAR(100),
    @localFilePath NVARCHAR(500),
    @remoteFilePath NVARCHAR(500)
AS EXTERNAL NAME SFTPUploader.[SFTPOperations].[UploadToSFTP];
GO

-- Step 7: Test the stored procedure
-- EXEC dbo.UploadToSFTP 
--     @host = 'wssftp.files.com',
--     @port = 22,
--     @username = 'hilco_sftp',
--     @password = 'R7$kT9!vL2@pQ4zM',
--     @localFilePath = 'C:\Reports\test.txt',
--     @remoteFilePath = '/Hilco Global/test.txt';
-- GO

PRINT 'CLR SFTP Upload deployment completed successfully!';
GO

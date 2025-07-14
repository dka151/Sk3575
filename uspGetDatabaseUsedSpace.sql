USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[uspGetDatabaseUsedSpace]    Script Date: 7/14/2025 12:36:36 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[uspGetDatabaseUsedSpace] @ServerName NVARCHAR(128)  
AS  
/************************************************************************  
* This procedure returns used space for all databases in a given server *  
************************************************************************/  
DECLARE @SQL NVARCHAR(MAX)  
SET @SQL='  
 DECLARE @SQL1 VARCHAR(MAX)  
 DECLARE @SQL2 VARCHAR(MAX)  
 DECLARE @SQL3 VARCHAR(MAX)  
  
 DECLARE @Database TABLE (DatabaseName NVARCHAR(128) PRIMARY KEY CLUSTERED)  
  
 SET @SQL1=''DECLARE  @DBSize TABLE  
 (ServerDatabaseID INT,  
 DatabaseName NVARCHAR(128),  
 ServerFileID INT,  
 FileGroup NVARCHAR(128),  
 FileName NVARCHAR(128),  
 PhysicalName NVARCHAR(260),  
 FileType TINYINT,  
 TotalSizeMB DEC (18,6),  
 UsedSizeMB DEC (18,6),  
 AvailableSpaceMB DEC (18,6) );  
 ---------------------------------------''  
 SET @SQL2=  
 ''USE [DBNAME];  
 INSERT INTO @DBSize (ServerDatabaseID,DatabaseName,ServerFileID,FileGroup,FileName,PhysicalName,FileType,TotalSizeMB,UsedSizeMB,AvailableSpaceMB)  
 SELECT DBID AS ServerDatabaseID, ''''DBNAME'''' AS DatabaseName, DF.file_id AS ServerFileID, CASE WHEN DF.[type] = 1 THEN ''''LOG'''' ELSE DS.name END AS FileGroup, DF.name AS FileName, DF.physical_name AS PhysicalName, DF.type AS FileType, DF.size/128.0
 as TotalSizeMB, CAST(FILEPROPERTY(DF.name, ''''SpaceUsed'''') AS int)/128.0 as UsedSizeMB, size/128.0 - CAST(FILEPROPERTY(DF.name, ''''SpaceUsed'''') AS int)/128.0 AS AvailableSpaceMB  
 FROM sys.database_files DF  
 LEFT JOIN sys.data_spaces DS ON DF.data_space_id=DS.data_space_id  
 ;''  
  
 SET @SQL3=@SQL1+CHAR(13)  
  
 SELECT @SQL3=@SQL3+REPLACE(REPLACE (@SQL2,''DBNAME'',name),''DBID'',CONVERT(VARCHAR(5),database_id)) +CHAR(13)  
  FROM   
   master.sys.databases D  
   LEFT JOIN sys.dm_hadr_availability_replica_states hars ON d.replica_id = hars.replica_id  
   WHERE (hars.role IS NULL or hars.role = 1)  
   AND D.state_desc=''ONLINE''  
    
 SET @SQL3=@SQL3+''---------------------------------------''+CHAR(13)  
  +''SELECT * FROM @DBSize ORDER BY AvailableSpaceMB DESC''  
 EXEC (@SQL3)  
' 

IF NOT (SELECT COUNT(*) FROM tServer WHERE ServerName=@ServerName AND Active=1 AND IsLinked=0)>0 
	SET @SQL='EXEC ('''+REPLACE (@SQL,'''','''''')+''') AT ['+@ServerName+']'
  
EXEC (@SQL)  
  
GO



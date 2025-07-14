USE [DBA]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER   PROCEDURE [dbo].[uspRefreshServer] 
AS  
/********************************************************  
* Keeps track of Linked Servers and their current state *  
********************************************************/  

SET NOCOUNT ON;
DECLARE  @Date DATETIME = CURRENT_TIMESTAMP  
        ,@SQL NVARCHAR(MAX)  
        ,@ServerID INT  
        ,@ServerName NVARCHAR(128)  
        ,@IsLinked BIT  
        ,@ReturnValue INT  
        ,@ErrorMessage NVARCHAR(MAX)  
        ,@IsErrorCritical BIT  
        ,@MicrosftVersion BIGINT  
        ,@ProductMajorVersion INT  
        ,@ServiceAccountServer NVARCHAR(256)  
        ,@ServiceAccountAgent NVARCHAR(256)  
        ,@RaiseErrorLevel INT;

DROP TABLE IF EXISTS #ServerError;
CREATE TABLE #ServerError  
(  
    ServerID INT PRIMARY KEY CLUSTERED  
    ,ErrorMessage NVARCHAR(MAX)  
    ,IsErrorCritical BIT  
);

DROP TABLE IF EXISTS #ServerConfiguration;
CREATE TABLE #ServerConfiguration  
(  
    ConfigurationName NVARCHAR(35)   
    ,ConfigurationValue SQL_VARIANT NULL  
    ,PRIMARY KEY CLUSTERED (ConfigurationName)  
);

DROP TABLE IF EXISTS #SPN;
CREATE TABLE #SPN (ServerPropertyName NVARCHAR(128) PRIMARY KEY CLUSTERED);
INSERT INTO #SPN (ServerPropertyName) VALUES  
        ('BuildClrVersion')  
        ,('Collation')  
        ,('CollationID')  
        ,('ComparisonStyle')  
        ,('ComputerNamePhysicalNetBIOS')  
        ,('Edition')  
        ,('EditionID')  
        ,('EngineEdition')  
        ,('FilestreamConfiguredLevel')  
        ,('FilestreamEffectiveLevel')  
        ,('FilestreamShareName')  
        ,('HadrManagerStatus')  
        ,('InstanceDefaultDataPath')  
        ,('InstanceDefaultLogPath')  
        ,('InstanceName')  
        ,('IsAdvancedAnalyticsInstalled')  
        ,('IsClustered')  
        ,('IsFullTextInstalled')  
        ,('IsHadrEnabled')  
        ,('IsIntegratedSecurityOnly')  
        ,('IsLocalDB')  
        ,('IsPolybaseInstalled')  
        ,('IsSingleUser')  
        ,('IsXTPSupported')  
        ,('LCID')  
        ,('LicenseType')  
        ,('MachineName')  
        ,('NumLicenses')  
        ,('ProcessID')  
        ,('ProductBuild')  
        ,('ProductBuildType')  
        ,('ProductLevel')  
        ,('ProductMajorVersion')  
        ,('ProductMinorVersion')  
        ,('ProductUpdateLevel')  
        ,('ProductUpdateReference')  
        ,('ProductVersion')  
        ,('ResourceLastUpdateDateTime')  
        ,('ResourceVersion')  
        ,('ServerName')  
        ,('SqlCharSet')  
        ,('SqlCharSetName')  
        ,('SqlSortOrder')  
        ,('SqlSortOrderName');

DROP TABLE IF EXISTS #SVN;
CREATE TABLE #SVN (ServerVariableName NVARCHAR(128) PRIMARY KEY CLUSTERED);
INSERT INTO #SVN (ServerVariableName) VALUES  
        ('@@MICROSOFTVERSION');
 
DROP TABLE IF EXISTS #OSInfo;
CREATE TABLE #OSInfo (  
    CPUCount int NULL  
    ,HyperthreadRatio int NULL  
    ,MaxOSWorkersCount int NULL  
    ,ServerStartTime datetime NULL  
    ,VirtualMachineType int NULL  
    ,VirtualMachineTypeDesc varchar(60) NULL  
    ,PhysicalMemoryMB INT  
    );

DROP TABLE IF EXISTS #AGState;
CREATE TABLE #AGState 
    (ConfigurationName NVARCHAR(35) NOT NULL 
    ,ConfigurationValue TINYINT NOT NULL 
    ,ConfigurationValueDesc VARCHAR(255) NOT NULL 
    PRIMARY KEY CLUSTERED (ConfigurationName, ConfigurationValue) 
    ) 
 
INSERT INTO #AGState (ConfigurationName, ConfigurationValue, ConfigurationValueDesc) 
VALUES 
 (N'primary_recovery_health',0,'IN PROGRESS') 
,(N'primary_recovery_health',1,'ONLINE') 
,(N'secondary_recovery_health',0,'IN PROGRESS') 
,(N'secondary_recovery_health',1,'ONLINE') 
,(N'synchronization_health',0,'NOT HEALTHY') 
,(N'synchronization_health',1,'PARTIALLY HEALTHY') 
,(N'synchronization_health',2,'HEALTHY');
 
/*******************************************  
* Refresh server list using linked servers *  
********************************************/  
IF NOT EXISTS (SELECT 1 FROM tServerGroup WHERE ServerGroupID=0)  
BEGIN  
    SET IDENTITY_INSERT tServerGroup ON;
    INSERT INTO tServerGroup (ServerGroupID, ServerGroupName, ServerNamePattern) VALUES (0,'DEFAULT','*');
    SET IDENTITY_INSERT tServerGroup OFF;
END;
  
INSERT INTO tServer (  
     ServerGroupID  
    ,LinkedServerID  
    ,ServerName  
    ,IsLinked  
    ,IsSQLServer  
    ,IsSysServer  
    ,Active  
    ,IsProduction  
    ,DefaultBackupStrategyID  
    ,EnableServerBackup  
    ,EnableServerRestore  
    ,EnableServerDBTrack  
    ,EnableServerLog  
    ,EnableCounterLog  
    ,EnableIOLog  
    ,EnableMultiExecNotification  
    ,EnableLongExecNotification  
    ,EnablePwdPolicyCheckNotification  
    ,EnableHighCPUNotification  
    ,HighCPUSQLTreshold  
    ,HighCPUOtherTreshold  
    ,EnableMemoryManagement  
    ,EnableSessionCountNotification  
    ,SessionCountThreshold  
    ,EnableBlockNotification  
    ,BlockNotificationSecThreshold  
    ,EnablePingNotification  
    ,EnableServerLogNotification  
    ,EnableAgentNotification  
    ,EnableServerStateNotification  
    ,DefaultEnableIndexMaintenance  
    ,DefaultReindexStrategyID  
    ,DefaultEnableStatisticsMaintenance  
    ,DefaultStatisticsMaintenanceStrategyID  
    ,DefaultEnableSpaceMaintenance  
    ,DefaultEnableBackup  
    ,DefaultEnableRestore  
    ,DefaultEnableRestoreKillSession  
    ,DefaultEnableLogQueryHistory  
    ,DefaultEnablePartitionMaintenance  
    ,DefaultPartitionStrategyID  
    )
SELECT   
    ISNULL(G.ServerGroupID,0) AS ServerGroupID  
    ,MS.server_id AS LinkedServerID  
    ,MS.name AS ServerName  
    ,MS.is_linked AS IsLinked  
    ,CASE MS.provider 
        WHEN 'SQLNCLI' THEN 1 
        WHEN 'SQLNCLI11' THEN 1 
        ELSE 0 
        END AS IsSQLServer  
    ,1 AS IsSysServer  
    ,CASE WHEN MS.name LIKE 'rds%'
          THEN 0
          ELSE 1 
     END AS Active
    ,G.IsProduction  
    ,G.DefaultBackupStrategyID  
    ,G.DefaultEnableServerBackup  
    ,G.DefaultEnableServerRestore  
    ,G.DefaultEnableServerDBTrack  
    ,G.DefaultEnableServerLog  
    ,G.DefaultEnableCounterLog  
    ,G.DefaultEnableIOLog  
    ,G.DefaultEnableMultiExecNotification  
    ,G.DefaultEnableLongExecNotification  
    ,G.DefaultEnablePwdPolicyCheckNotification  
    ,G.DefaultEnableHighCPUNotification  
    ,G.DefaultHighCPUSQLTreshold  
    ,G.DefaultHighCPUOtherTreshold  
    ,G.DefaultEnableMemoryManagement  
    ,G.DefaultEnableSessionCountNotification  
    ,G.DefaultSessionCountThreshold  
    ,G.DefaultEnableBlockNotification  
    ,G.DefaultBlockNotificationSecThreshold  
    ,G.DefaultEnablePingNotification  
    ,G.DefaultEnableServerLogNotification  
    ,G.DefaultEnableAgentNotification  
    ,G.DefaultEnableServerStateNotification  
    ,G.DefaultEnableIndexMaintenance  
    ,G.DefaultReindexStrategyID  
    ,G.DefaultEnableStatisticsMaintenance  
    ,G.DefaultStatisticsMaintenanceStrategyID  
    ,G.DefaultEnableSpaceMaintenance  
    ,G.DefaultEnableBackup  
    ,G.DefaultEnableRestore  
    ,G.DefaultEnableRestoreKillSession  
    ,G.DefaultEnableLogQueryHistory  
    ,G.DefaultEnablePartitionMaintenance  
    ,G.DefaultPartitionStrategyID  
FROM master.sys.servers MS  
    LEFT JOIN tServer S  
        ON MS.name = S.ServerName   
    OUTER APPLY (SELECT TOP 1 * FROM tServerGroup SG WHERE (MS.name LIKE SG.ServerNamePattern OR SG.ServerGroupID=0) ORDER BY CASE WHEN MS.name=SG.ServerNamePattern THEN 1 ELSE 0 END DESC, CASE WHEN SG.ServerGroupID=0 THEN 0 ELSE 1 END DESC, SG.ServerGroupID) G  
WHERE   
    S.ServerName IS NULL AND ( server_id=0 OR (is_data_access_enabled=1 AND is_linked = 1))
    AND MS.modify_date<=DATEADD(MINUTE,-5,CURRENT_TIMESTAMP) --Ignore servers being configured this very moment  
    AND MS.provider <> 'MSDASQL'
ORDER BY   
    MS.server_id;
  
UPDATE S
SET  S.LinkedServerID = SS.server_id  
    ,IsLinked = SS.is_linked  
    ,IsSQLServer = CASE SS.provider WHEN 'SQLNCLI' THEN 1  WHEN 'SQLNCLI11' THEN 1 ELSE 0 END  
    ,IsSysServer = 1  
FROM dbo.tServer AS S 
    INNER JOIN master.sys.servers SS ON SS.name = S.ServerName;

DECLARE @MyTableVar TABLE (Servername sysname);  
DECLARE @SvrList NVARCHAR(512);

UPDATE S  
SET  S.IsSysServer = 0  
    ,S.Active = 0  
    ,S.date_inactive = CONVERT(DATE, GETDATE())
OUTPUT INSERTED.servername INTO @MyTableVar
FROM dbo.tServer AS S  
    LEFT JOIN master.sys.servers SS  
    ON SS.name = S.ServerName  
WHERE SS.name IS NULL AND (S.Active = 1 OR S.IsSysServer = 1);

IF @@ROWCOUNT > 0
 BEGIN
    DECLARE @ServerList varchar(500)
    DECLARE @ProfileName SYSNAME
    DECLARE @Recipients VARCHAR(MAX)
    DECLARE @Subject nvarchar(1000)

    select @SvrList = stuff(list,1,1,'')
    from    (
            select  ',' + cast(Servername as varchar(16)) as [text()]
            from    @MyTableVar
            for     xml path('')
            ) as Sub(list)

    select @ServerList = coalesce(@ServerList + ',', '') +  convert(varchar(16),servername) from @MyTableVar order by servername
    SET @Recipients = 'vikashkumar.s@tra-augment.com'
    SELECT TOP 1 @ProfileName=P.name FROM msdb..sysmail_principalprofile PP RIGHT JOIN msdb..sysmail_profile P ON PP.profile_id=P.profile_id ORDER BY PP.is_default DESC, P.profile_id
    SET @Subject = N'Deactivated Servers on DB Monitor: ' + @SvrList;

    --EXEC msdb.dbo.sp_send_dbmail
    --    @profile_name=@ProfileName,
    --    @recipients = @Recipients,
    --    @body = N'Deactivated Servers on DBMonitor',
    --    @subject = @Subject,
    --    @body_format='TEXT'
 END

/***************************  
* Loop through all servers *  
***************************/  
DECLARE cServer CURSOR   
     FOR   
        SELECT   
            ServerID, ServerName, IsLinked  
        FROM   
            tServer   
        WHERE   
            IsSQLServer=1 AND IsSysServer=1 AND (active = 1  OR (active = 0 AND ISNULL(date_inactive, '1900-01-01') > DATEADD(dd, -7, GETDATE())))
        ORDER BY   
            ServerID  
          
OPEN cServer     
  
WHILE 1=1  
    BEGIN  
    SET @ErrorMessage=NULL  
    SET @IsErrorCritical=0 
    SET @Date=CURRENT_TIMESTAMP 
    TRUNCATE TABLE #ServerConfiguration 
    TRUNCATE TABLE #OSInfo 
  
    FETCH NEXT FROM cServer  
        INTO @ServerID, @ServerName, @IsLinked  
    IF @@FETCH_STATUS<>0 BREAK  
        RAISERROR ('%s', 0, 1, @ServerName) WITH NOWAIT  
    BEGIN TRY  
        --Enforce connection timeouts  
        IF NOT (SELECT connect_timeout FROM sys.servers WHERE name=@ServerName) BETWEEN 1 AND 60  
            EXEC master.dbo.sp_serveroption @server=@ServerName, @optname=N'connect timeout', @optvalue=N'15'  
        --Ping server  
        SET @SQL='SELECT ''Pinging ['+@ServerName+']'' AS PingResult'  
        IF @ServerID>0  
            SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        EXEC (@SQL)  
        --Set formerly Inactive Servers Active 
         UPDATE tServer SET Active=1 WHERE ServerID=@ServerID AND Active=0  
     END TRY  
    BEGIN CATCH  
        SET @ErrorMessage=@ServerName + ': ' + ERROR_MESSAGE()  
        SET @IsErrorCritical=1  
        UPDATE tServer SET Active=0, date_inactive = CONVERT(DATE, GETDATE()) WHERE ServerID=@ServerID AND Active=1 
    END CATCH 
     
    /*********************** 
    * SERVER CONFIGURATION * 
    **********************/ 
    IF @IsErrorCritical=0 
    BEGIN TRY 
        --Server Property 
        SET @SQL=NULL  
        SELECT @SQL=ISNULL(@SQL+CHAR(13)+CHAR(10)+'UNION ALL ','')+'SELECT '''+ServerPropertyName+''' AS N,SERVERPROPERTY('''+ServerPropertyName+''') AS V' FROM #SPN 
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
        DELETE FROM #ServerConfiguration WHERE ConfigurationValue IS NULL 
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get Server Property: ' + ERROR_MESSAGE();  
    END CATCH  
     
    IF @IsErrorCritical=0 
    BEGIN TRY 
        --Get Server Global Variables  
        SET @SQL=NULL  
        SELECT @SQL=ISNULL(@SQL+CHAR(13)+CHAR(10)+'UNION ALL ','')+'SELECT '''+ServerVariableName+''' AS N,'+ServerVariableName+' AS V' FROM #SVN  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get Global Variables: ' + ERROR_MESSAGE();  
    END CATCH 
     
    --Consider PDW as a Critical Error to bypass any other checks since they are not supported 
    IF EXISTS (SELECT 1 FROM #ServerConfiguration WHERE ConfigurationName='ServerName' AND CONVERT(NVARCHAR(128),ConfigurationValue)=N'PDW') SET @IsErrorCritical=1 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
        --Get Server Configurations  
        SET @SQL='SELECT [name], [value] FROM master.sys.configurations'  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get sys.configurations: ' + ERROR_MESSAGE();  
    END CATCH 
     
    IF @IsErrorCritical=0 
    BEGIN TRY  
         --Is Agent Running 
        SET @SQL='SELECT ''IsAgentRunning'' AS [name], CASE WHEN EXISTS (SELECT 1 FROM master.sys.dm_exec_sessions ES WHERE ES.program_name = N''SQLAgent - Generic Refresher'') THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END AS [value]'  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL) 
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get IsAgentRunning: ' + ERROR_MESSAGE();  
    END CATCH 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
         --AG Status 
        SET @SQL= 
        'SELECT ConfigurationName AS [name],
                   NULLIF(ConfigurationValue, 5) - 1 AS [value]
            FROM
            (
                SELECT MIN(ISNULL(   CASE
                                         WHEN primary_recovery_health IS NULL THEN
                                             4
                                         ELSE
                                             primary_recovery_health
                                     END + 1,
                                     0
                                 )
                          ) AS primary_recovery_health,
                       MIN(ISNULL(   CASE
                                         WHEN secondary_recovery_health IS NULL THEN
                                             4
                                         ELSE
                                             secondary_recovery_health
                                     END + 1,
                                     0
                                 )
                          ) AS secondary_recovery_health,
                       MIN(ISNULL(agr.synchronization_health + 1, 0)) AS synchronization_health
                FROM sys.dm_hadr_availability_group_states agr
                INNER JOIN sys.dm_hadr_availability_replica_states asr 
                ON agr.group_id = asr.group_id
            ) AGS
                UNPIVOT
                (
                    ConfigurationValue
                    FOR ConfigurationName IN (primary_recovery_health, secondary_recovery_health, synchronization_health)
                ) AS UNPVT' 
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
         
        --AG State Description 
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue) 
        SELECT  
            SC.ConfigurationName+'_desc'  
            ,AGS.ConfigurationValueDesc 
            FROM 
        #ServerConfiguration SC 
        LEFT JOIN #AGState AGS 
            ON SC.ConfigurationName=AGS.ConfigurationName 
            AND SC.ConfigurationValue=AGS.ConfigurationValue             
        WHERE 
            SC.ConfigurationName IN ('primary_recovery_health','secondary_recovery_health','synchronization_health') 
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get AG Status: ' + ERROR_MESSAGE();  
    END CATCH 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
        --Get Default Backup Path  
        SET @SQL='DECLARE @BackupDirectory nvarchar(512)  
            EXEC master.dbo.xp_instance_regread N''HKEY_LOCAL_MACHINE'', N''Software\Microsoft\MSSQLServer\MSSQLServer'', N''BackupDirectory'', @BackupDirectory OUTPUT  
            SELECT ''InstanceDefaultBackupPath'' [name], @BackupDirectory AS [value] WHERE @BackupDirectory IS NOT NULL'  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL) 
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ': ' + ERROR_MESSAGE();  
    END CATCH 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
        --Get Authentication Mode: 1 = Windows Only, 2 =  Mixed 
        SET @SQL='DECLARE @LoginMode INT 
            EXEC master.dbo.xp_instance_regread N''HKEY_LOCAL_MACHINE'', N''Software\Microsoft\MSSQLServer\MSSQLServer'', N''LoginMode'', @LoginMode OUTPUT  
            SELECT ''LoginMode'' [name], CONVERT(VARCHAR(5),@LoginMode) AS [value] WHERE @LoginMode IS NOT NULL'  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get Authentication Mode: ' + ERROR_MESSAGE();  
    END CATCH 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
        --Get Service Account Server 
        SET @SQL='DECLARE @ServiceAccountServer NVARCHAR(256) 
            EXEC master.dbo.xp_instance_regread N''HKEY_LOCAL_MACHINE'', N''SYSTEM\CurrentControlSet\Services\MSSQLServer'', N''ObjectName'', @ServiceAccountServer OUTPUT  
            SELECT ''ServiceAccountServer'' [name], @ServiceAccountServer AS [value] WHERE @ServiceAccountServer IS NOT NULL'  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get Service Account Server: ' + ERROR_MESSAGE();  
    END CATCH 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
        --Get Service Account Agent 
        SET @SQL='DECLARE @ServiceAccountAgent NVARCHAR(256) 
            EXEC master.dbo.xp_instance_regread N''HKEY_LOCAL_MACHINE'', N''SYSTEM\CurrentControlSet\Services\SQLServerAgent'', N''ObjectName'', @ServiceAccountAgent OUTPUT  
            SELECT ''ServiceAccountAgent'' [name], @ServiceAccountAgent AS [value] WHERE @ServiceAccountAgent IS NOT NULL'  
        IF @IsLinked=1  
        SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']'  
        INSERT INTO #ServerConfiguration (ConfigurationName,ConfigurationValue)   
            EXEC (@SQL)  
    END TRY 
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get Service Account Agent: ' + ERROR_MESSAGE();  
    END CATCH 
 
    IF @IsErrorCritical=0 
    BEGIN TRY  
        -- Get OS Stats - different between versions 
        SET @ProductMajorVersion=(SELECT CONVERT(BIGINT,ConfigurationValue) FROM #ServerConfiguration WHERE ConfigurationName='@@MICROSOFTVERSION') / 0x01000000;
  
        SET @SQL=NULL;
        IF @ProductMajorVersion=9 --2005  
            SET @SQL='SELECT cpu_count, hyperthread_ratio, max_workers_count, NULL AS sqlserver_start_time, NULL AS virtual_machine_type, NULL AS virtual_machine_type_desc, ROUND(physical_memory_in_bytes/1024.0/1024,0) AS PhysicalMemoryMB FROM sys.dm_os_sys_info';
        IF @ProductMajorVersion=10 --2008 or 2008R2  
            SET @SQL='SELECT cpu_count, hyperthread_ratio, max_workers_count, sqlserver_start_time, NULL AS virtual_machine_type, NULL AS virtual_machine_type_desc, ROUND(physical_memory_in_bytes/1024.0/1024,0) AS PhysicalMemoryMB FROM sys.dm_os_sys_info';
        ELSE IF @ProductMajorVersion>=11 --2012  
            SET @SQL='SELECT cpu_count, hyperthread_ratio, max_workers_count, sqlserver_start_time, virtual_machine_type, virtual_machine_type_desc, ROUND(physical_memory_kb/1024.0,0) AS PhysicalMemoryMB FROM sys.dm_os_sys_info';
         
        IF @SQL IS NOT NULL  
        BEGIN  
            IF @IsLinked=1  
                SET @SQL='EXEC('''+REPLACE(@SQL,'''','''''')+''') AT ['+@ServerName+']';
             INSERT INTO #OSInfo 
                EXEC (@SQL);
  
            INSERT INTO #ServerConfiguration (ConfigurationValue, ConfigurationName) 
            SELECT * FROM 
            ( 
            SELECT  
                CONVERT(VARCHAR(255),[CPUCount]) AS [CPUCount] 
                ,CONVERT(VARCHAR(255),[HyperthreadRatio]) AS [HyperthreadRatio] 
                ,CONVERT(VARCHAR(255),[MaxOSWorkersCount]) AS [MaxOSWorkersCount] 
                ,CONVERT(VARCHAR(255),[ServerStartTime],121) AS [ServerStartTime] 
                ,CONVERT(VARCHAR(255),[VirtualMachineType]) AS [VirtualMachineType] 
                ,CONVERT(VARCHAR(255),[VirtualMachineTypeDesc]) AS [VirtualMachineTypeDesc] 
                ,CONVERT(VARCHAR(255),[PhysicalMemoryMB]) AS [PhysicalMemoryMB] 
            FROM #OSInfo) TS 
            UNPIVOT (ConfigurationValue  
            FOR ConfigurationName IN ( 
                CPUCount 
                ,HyperthreadRatio 
                ,MaxOSWorkersCount 
                ,ServerStartTime 
                ,VirtualMachineType 
                ,VirtualMachineTypeDesc 
                ,PhysicalMemoryMB 
                ) 
            ) AS UNPVT;
 
        END  
    END TRY  
    BEGIN CATCH  
        SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Get sys.dm_os_sys_info: ' + ERROR_MESSAGE();  
    END CATCH  
     
    --Store Error Result 
    INSERT INTO #ServerConfiguration (ConfigurationName, ConfigurationValue) 
    VALUES ('Error', CONVERT(VARCHAR(8000),@ErrorMessage));
 
    /***************************  
    * COMPLETE STORING RESULTS *  
    ***************************/  
    BEGIN TRY 
        --Use Temp Table to temporary store values to insert due to SQL2012 limitations  
        DROP TABLE IF EXISTS #ServerConfigurationTemp  
        SELECT TOP 0 * INTO #ServerConfigurationTemp FROM tServerConfiguration;
        BEGIN TRAN  
            ;WITH   
            Tgt AS(SELECT TC.* FROM tServerConfiguration TC WHERE TC.ServerID=@ServerID AND TC.EndDate IS NULL)  
            ,Src AS(SELECT @ServerID AS ServerID, SC.ConfigurationName, SC.ConfigurationValue FROM #ServerConfiguration SC)  
  
             --Insert new values records that had its values changed (End Date updated to Timestamp, Source Server ID is not null)  
            --Use temp table because direct insert only works in SQL2014  
            INSERT INTO #ServerConfigurationTemp (ServerID, ConfigurationName, StartDate, EndDate, ConfigurationValue)  
            SELECT ServerID, ConfigurationName, @Date AS StartDate, NULL AS EndDate, ConfigurationValue  
            FROM  
            (  
                MERGE Tgt  
                USING Src  
                    ON Tgt.ServerID=Src.ServerID AND Tgt.ConfigurationName=Src.ConfigurationName  
                --Any new configuration names  
                WHEN NOT MATCHED   
                    THEN INSERT (ServerID,ConfigurationName,ConfigurationValue,StartDate,EndDate) 
                    VALUES (ServerID,ConfigurationName,ConfigurationValue,@Date,NULL)  
                --Configuration no longer exists and no error reported 
                WHEN NOT MATCHED BY SOURCE AND @ErrorMessage IS NULL 
                    THEN UPDATE SET Tgt.EndDate=@Date  
                --Configuration values changed; Source Server ID is not null in this case  
                WHEN MATCHED AND EXISTS (SELECT Tgt.ConfigurationValue EXCEPT SELECT Src.ConfigurationValue) 
                    THEN UPDATE SET Tgt.EndDate=@Date  
                OUTPUT $ACTION AS [Action], Src.*  
            ) Mrg  
            --See Insert comment above  
            WHERE Mrg.[Action]='UPDATE' AND Mrg.ServerID IS NOT NULL  
            ;  
            INSERT INTO tServerConfiguration (ServerID, ConfigurationName, StartDate, EndDate, ConfigurationValue)  
                SELECT ServerID, ConfigurationName, StartDate, EndDate, ConfigurationValue FROM #ServerConfigurationTemp  
        COMMIT  
            END TRY  
        BEGIN CATCH  
            IF @@TRANCOUNT>0 ROLLBACK 
            SET @ErrorMessage=ISNULL (@ErrorMessage+';'+CHAR(13),'') + ISNULL(@ServerName,'Unknown Server') + ' - Store Results: ' + ERROR_MESSAGE();  
            THROW 
        END CATCH 
        IF @ErrorMessage IS NOT NULL INSERT INTO #ServerError (ServerID, ErrorMessage, IsErrorCritical) 
        VALUES (@ServerID, @ErrorMessage, @IsErrorCritical) 
END          
CLOSE cServer  
DEALLOCATE cServer  
  
/************************  
* Refresh ServerPingLog *  
***********************/  
MERGE tServerPingLog Tgt  
USING tServer Src  
    ON Tgt.ServerID=Src.ServerID  
WHEN NOT MATCHED   
THEN INSERT (ServerID) VALUES (ServerID)  
WHEN NOT MATCHED BY SOURCE  
THEN DELETE;

/*****************  
* ERROR HANDLING *  
*****************/  
SET @ErrorMessage=NULL;
SELECT * FROM #ServerError;
 
SELECT   
    @ErrorMessage=ISNULL(@ErrorMessage+';'+CHAR(13),'')+ SE.ErrorMessage  
FROM   
    #ServerError SE  
WHERE  
    SE.ErrorMessage IS NOT NULL;
  
IF  @ErrorMessage IS NOT NULL 
BEGIN  
    SELECT @RaiseErrorLevel=CASE WHEN MAX(CONVERT(INT,IsErrorCritical))=1 THEN 18 ELSE 1 END FROM #ServerError;
    IF 1=0 RAISERROR (@ErrorMessage,@RaiseErrorLevel,1); --DISABLED 
END
GO



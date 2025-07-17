USE [DBMonitor]
GO
/****** Object:  StoredProcedure [dbo].[uspCheckSQLInstanceVolumeCapacityStatus]    Script Date: 7/17/2025 3:11:23 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[uspCheckSQLInstanceVolumeCapacityStatus]
AS
BEGIN
declare @servers table (servername sysname,
                        serverid int)

insert  @servers
        (serverid,servername)
select  serverid, servername
from    dbo.tServer
where islinked=1 and active = 1

declare @query nvarchar(max) = 'INSERT INTO tSQLInstanceStorageVolumeStatus ([ServerID], [SQLInstanceName], [VolumeMountPoint],[LogicalVolumeName], [TotalSize(GB)], [AvailableSize(GB)], [SpaceFreePercent]) '
declare @union BIT
set @union = 'FALSE'
while 1=1
    begin
    declare @server sysname,
        @serverid int

    select  top 1 @server = servername, @serverid = serverid
    from    @servers

    if @@rowcount = 0
        break

    if @union = 'TRUE'
        set  @query = @query + ' union all ' + char(13) + char(10)

    set @query = @query + 
    'SELECT ' + cast(@serverid as VARCHAR(10)) +',' + '* FROM OPENQUERY (' + quotename(@server) +',' +'''SELECT DISTINCT @@SERVERNAME, vs.volume_mount_point,  
    vs.logical_volume_name, CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0) AS [Total Size (GB)],
    CONVERT(DECIMAL(18,2),vs.available_bytes/1073741824.0) AS [Available Size (GB)],  
    CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,2)) * 100 AS [Space Free %] 
    FROM [master].[sys].[master_files] AS f --WITH (NOLOCK)
    CROSS APPLY [master].[sys].[dm_os_volume_stats](f.database_id, f.[file_id]) AS vs 
    where CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,2)) * 100 < 15
    AND vs.logical_volume_name NOT LIKE ''''%tempdb%'''' '')'
     +   char(13) + char(10)
SET @union = 'TRUE' 
    delete FROM @servers
    where   servername = @server
    end

--print @query -- For debugging
exec (@query)--
--SELECT * FROM DBA.dbo.SQLInstanceStorageVolumestatus
--TRUNCATE TABLE DBA.dbo.SQLInstanceStorageVolumestatus
END

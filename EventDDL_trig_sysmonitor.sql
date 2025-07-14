CREATE OR ALTER TRIGGER [EventDDL_trig_sysmonitor]
ON DATABASE 
FOR DDL_DATABASE_LEVEL_EVENTS
AS

set nocount on
SET ANSI_PADDING on

declare @xml_data XML
SET @xml_data = EVENTDATA()

INSERT INTO 
dbo.DDL_Log (
	[EventType] ,
	[ServerName] ,
	[DatabaseName] ,
	[SchemaName] ,
	[ObjectName] ,
	[ObjectType] ,
	[EventDDL] ,
	[LoginName] ,
	[LoginTime] ,
	[ExecTime] ,
	[HostName],
	[HostProcess],
	[SessionID] ,
	[Timestamp] ,
	[ProgramName] 
)

SELECT 
@xml_data.value('(/EVENT_INSTANCE/EventType)[1]','nvarchar(128)')    EventType
,@@servername ServerName
,@xml_data.value('(/EVENT_INSTANCE/DatabaseName)[1]','nvarchar(128)') DatabaseName
,@xml_data.value('(/EVENT_INSTANCE/SchemaName)[1]','nvarchar(128)')  SchemaName
,@xml_data.value('(/EVENT_INSTANCE/ObjectName)[1]','nvarchar(128)')   ObjectName
,@xml_data.value('(/EVENT_INSTANCE/ObjectType)[1]','nvarchar(128)')   ObjectType
,@xml_data.value('(/EVENT_INSTANCE/TSQLCommand)[1]','nvarchar(max)')  EventDDL

,s.original_login_name LoginName
,s.login_time LoginTime
,s.last_request_start_time ExecTime
,s.host_name HostName
,HOST_ID () HostProcess
,s.session_id SessionID
,CURRENT_TIMESTAMP Timestamp
,s.program_name ProgramName

 FROM 
   sys.dm_exec_sessions s
   LEFT JOIN sys.dm_exec_requests r
        ON  r.session_id = s.session_id
WHERE s.session_id = @xml_data.value('(/EVENT_INSTANCE/SPID)[1]','int')
  AND @xml_data.value('(/EVENT_INSTANCE/EventType)[1]','nvarchar(128)') NOT LIKE '%STATISTICS%';
GO

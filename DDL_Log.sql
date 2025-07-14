USE [DBMonitor]
GO

/****** Object:  Table [dbo].[DDL_Log]    Script Date: 7/14/2025 11:05:26 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[DDL_Log](
	[EventId] [int] IDENTITY(1,1) NOT NULL,
	[EventType] [nvarchar](128) NOT NULL,
	[ServerName] [nvarchar](128) NOT NULL,
	[DatabaseName] [nvarchar](128) NOT NULL,
	[SchemaName] [nvarchar](128) NULL,
	[ObjectName] [nvarchar](128) NOT NULL,
	[ObjectType] [nvarchar](128) NOT NULL,
	[EventDDL] [nvarchar](max) NOT NULL,
	[LoginName] [nvarchar](128) NOT NULL,
	[LoginTime] [datetime] NOT NULL,
	[ExecTime] [datetime] NOT NULL,
	[HostName] [nvarchar](128) NOT NULL,
	[HostProcess] [varchar](10) NOT NULL,
	[SessionID] [smallint] NOT NULL,
	[Timestamp] [datetime] NOT NULL,
	[ProgramName] [nvarchar](128) NOT NULL,
 CONSTRAINT [PK_DDL_Log] PRIMARY KEY CLUSTERED 
(
	[EventId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
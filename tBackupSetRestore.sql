USE [DBA]
GO

/****** Object:  Table [dbo].[tBackupSetRestore]    Script Date: 7/13/2025 12:48:25 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tBackupSetRestore](
	[ServerID] [int] NOT NULL,
	[ServerRestoreHistoryID] [int] NOT NULL,
	[RestoreDate] [datetime] NULL,
	[ServerDestinationDatabaseName] [nvarchar](128) NULL,
	[UserName] [nvarchar](128) NULL,
	[ServerBackupSetID] [int] NOT NULL,
	[RestoreType] [char](1) NULL,
	[Replace] [bit] NULL,
	[Recovery] [bit] NULL,
	[Restart] [bit] NULL,
	[StopAt] [datetime] NULL,
	[DeviceCount] [tinyint] NULL,
	[StopAtMarkName] [nvarchar](128) NULL,
	[StopBefore] [bit] NULL,
 CONSTRAINT [PK_tBackupSetRestore] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC,
	[ServerRestoreHistoryID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO


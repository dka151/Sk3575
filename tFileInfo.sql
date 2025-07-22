USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tFileInfo]    Script Date: 7/22/2025 11:30:59 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tFileInfo](
	[FileInfoID] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[FileID] [int] NOT NULL,
	[Type] [tinyint] NOT NULL,
	[DriveLetter] [nvarchar](1) NULL,
	[LogicalFileName] [sysname] NOT NULL,
	[PhysicalFileName] [nvarchar](260) NOT NULL,
	[SizeMB] [decimal](38, 2) NULL,
	[SpaceUsedMB] [decimal](38, 2) NULL,
	[FreeSpaceMB] [decimal](38, 2) NULL,
	[MaxSize] [decimal](38, 2) NULL,
	[IsPercentGrowth] [bit] NULL,
	[Growth] [decimal](38, 2) NULL,
	[CaptureDate] [datetime] NOT NULL,
 CONSTRAINT [PK__tFileInfo__7F60ED59] PRIMARY KEY CLUSTERED 
(
	[FileInfoID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [DailyChecks].[tFileInfo] ADD  CONSTRAINT [DF_FileInfo_CaptureDate]  DEFAULT (getdate()) FOR [CaptureDate]
GO



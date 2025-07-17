USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tSQLInstanceStorageVolumeStatus]    Script Date: 7/17/2025 3:14:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tSQLInstanceStorageVolumeStatus](
	[IdSQLVolumetatus] [int] IDENTITY(1,1) NOT NULL,
	[TimeStamp] [datetime2](7) NOT NULL,
	[ServerID] [int] NOT NULL,
	[SQLInstanceName] [varchar](50) NOT NULL,
	[VolumeMountPoint] [varchar](70) NOT NULL,
	[LogicalVolumeName] [varchar](70) NOT NULL,
	[TotalSize(GB)] [int] NOT NULL,
	[AvailableSize(GB)] [int] NOT NULL,
	[SpaceFreePercent] [decimal](5, 2) NOT NULL,
 CONSTRAINT [PK_SQLInstanceStorageVolumestatus] PRIMARY KEY CLUSTERED 
(
	[IdSQLVolumetatus] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tSQLInstanceStorageVolumeStatus] ADD  CONSTRAINT [DF_tSQLInstanceStorageVolumestatus_TimeStamp]  DEFAULT (getdate()) FOR [TimeStamp]
GO



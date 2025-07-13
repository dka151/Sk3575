USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabaseFile]    Script Date: 7/13/2025 1:53:30 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabaseFile](
	[DatabaseID] [int] NOT NULL,
	[FileID] [int] IDENTITY(1,1) NOT NULL,
	[ServerDatabaseID] [int] NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[ServerFileID] [int] NOT NULL,
	[Type] [tinyint] NOT NULL,
	[FileGroup] [nvarchar](128) NOT NULL,
	[FileName] [nvarchar](128) NOT NULL,
	[PhysicalName] [nvarchar](260) NOT NULL,
	[CurrentFileSizeMB] [decimal](12, 3) NULL,
	[CurrentUsedSizeMB] [decimal](12, 3) NULL,
	[LastNumberReads] [bigint] NULL,
	[LastBytesRead] [bigint] NULL,
	[LastIoStallReadMS] [bigint] NULL,
	[LastNumberWrites] [bigint] NULL,
	[LastBytesWritten] [bigint] NULL,
	[LastIoStallWriteMS] [bigint] NULL,
	[LastSampleDateIO] [datetime] NULL,
	[LastSampleMSIO] [bigint] NULL,
 CONSTRAINT [PK_tDatabaseFile] PRIMARY KEY CLUSTERED 
(
	[FileID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tDatabaseFile]  WITH CHECK ADD  CONSTRAINT [FK_tDatabaseFile_tDatabase] FOREIGN KEY([DatabaseID])
REFERENCES [dbo].[tDatabase] ([DatabaseID])
GO

ALTER TABLE [dbo].[tDatabaseFile] CHECK CONSTRAINT [FK_tDatabaseFile_tDatabase]
GO



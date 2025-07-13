USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabaseFileStats]    Script Date: 7/13/2025 1:53:42 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabaseFileStats](
	[FileId] [int] NOT NULL,
	[SampleDateID] [int] NOT NULL,
	[SampleDate] [datetime] NULL,
	[SampleMS] [bigint] NOT NULL,
	[NumberReads] [bigint] NOT NULL,
	[BytesRead] [bigint] NOT NULL,
	[IoStallReadMS] [bigint] NOT NULL,
	[NumberWrites] [bigint] NOT NULL,
	[BytesWritten] [bigint] NOT NULL,
	[IoStallWriteMS] [bigint] NOT NULL,
	[DeltaSampleMS] [bigint] NOT NULL,
	[DeltaNumberReads] [bigint] NOT NULL,
	[DeltaBytesRead] [bigint] NOT NULL,
	[DeltaIoStallReadMS] [bigint] NOT NULL,
	[DeltaNumberWrites] [bigint] NOT NULL,
	[DeltaBytesWritten] [bigint] NOT NULL,
	[DeltaIoStallWriteMS] [bigint] NOT NULL,
 CONSTRAINT [PK_tDatabaseFileStats] PRIMARY KEY CLUSTERED 
(
	[SampleDateID] ASC,
	[FileId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tDatabaseFileStats]  WITH CHECK ADD  CONSTRAINT [FK_tDatabaseFileStats_tDatabaseFile] FOREIGN KEY([FileId])
REFERENCES [dbo].[tDatabaseFile] ([FileID])
GO

ALTER TABLE [dbo].[tDatabaseFileStats] CHECK CONSTRAINT [FK_tDatabaseFileStats_tDatabaseFile]
GO

ALTER TABLE [dbo].[tDatabaseFileStats]  WITH CHECK ADD  CONSTRAINT [FK_tDatabaseFileStats_tDatabaseFileStats_SampleDate] FOREIGN KEY([SampleDateID])
REFERENCES [dbo].[tDatabaseFileStats_SampleDate] ([SampleDateID])
GO

ALTER TABLE [dbo].[tDatabaseFileStats] CHECK CONSTRAINT [FK_tDatabaseFileStats_tDatabaseFileStats_SampleDate]
GO



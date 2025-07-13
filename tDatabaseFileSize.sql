USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabaseFileSize]    Script Date: 7/13/2025 1:53:36 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabaseFileSize](
	[FileID] [int] NOT NULL,
	[StartDate] [smalldatetime] NOT NULL,
	[EndDate] [smalldatetime] NULL,
	[FileSizeMB] [decimal](12, 3) NULL,
	[UsedSizeMB] [decimal](12, 3) NULL,
 CONSTRAINT [PK_tDatabaseFileSize] PRIMARY KEY CLUSTERED 
(
	[FileID] ASC,
	[StartDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tDatabaseFileSize]  WITH CHECK ADD  CONSTRAINT [FK_tDatabaseFileSize_tDatabaseFile] FOREIGN KEY([FileID])
REFERENCES [dbo].[tDatabaseFile] ([FileID])
GO

ALTER TABLE [dbo].[tDatabaseFileSize] CHECK CONSTRAINT [FK_tDatabaseFileSize_tDatabaseFile]
GO



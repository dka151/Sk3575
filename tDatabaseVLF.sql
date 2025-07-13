USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabaseVLF]    Script Date: 7/13/2025 1:53:52 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabaseVLF](
	[ServerID] [int] NOT NULL,
	[DatabaseName] [sysname] NOT NULL,
	[VLFCount] [int] NOT NULL,
	[AverageVLFSizeMB] [decimal](10, 2) NOT NULL,
	[MinVLFSizeMB] [decimal](10, 2) NOT NULL,
	[MaxVLFSizeMB] [decimal](10, 2) NOT NULL,
	[CapturedDate] [datetime] NULL,
 CONSTRAINT [PK_tDatabaseVLF] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC,
	[DatabaseName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tDatabaseVLF] ADD  DEFAULT (getutcdate()) FOR [CapturedDate]
GO

ALTER TABLE [dbo].[tDatabaseVLF]  WITH CHECK ADD  CONSTRAINT [FK_tDatabaseVLF_tServer] FOREIGN KEY([ServerID])
REFERENCES [dbo].[tServer] ([ServerID])
GO

ALTER TABLE [dbo].[tDatabaseVLF] CHECK CONSTRAINT [FK_tDatabaseVLF_tServer]
GO



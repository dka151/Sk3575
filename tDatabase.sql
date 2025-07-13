USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabase]    Script Date: 7/13/2025 1:53:05 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabase](
	[ServerID] [int] NOT NULL,
	[DatabaseID] [int] IDENTITY(1,1) NOT NULL,
	[ParentDatabaseID] [int] NULL,
	[ServerDatabaseID] [int] NULL,
	[DatabaseGUID] [uniqueidentifier] NULL,
	[DatabaseName] [nvarchar](128) NULL,
	[BackupStrategyID] [int] NULL,
	[EnableIndexMaintenance] [bit] NOT NULL,
	[ReindexStrategyID] [int] NULL,
	[EnableStatisticsMaintenance] [bit] NOT NULL,
	[StatisticsMaintenanceStrategyID] [int] NULL,
	[EnableSpaceMaintenance] [bit] NOT NULL,
	[EnableBackup] [bit] NOT NULL,
	[EnableRestore] [bit] NOT NULL,
	[EnableRestoreKillSession] [bit] NOT NULL,
	[EnableLogQueryHistory] [bit] NOT NULL,
	[EnablePartitionMaintenance] [bit] NOT NULL,
	[PartitionMaintenanceStrategyID] [int] NULL,
	[Active] [bit] NOT NULL,
 CONSTRAINT [PK_tServerDatabase] PRIMARY KEY CLUSTERED 
(
	[DatabaseID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 85, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tDatabase] ADD  CONSTRAINT [DF_tDatabase_EnablePartitionMaintenance]  DEFAULT ((0)) FOR [EnablePartitionMaintenance]
GO

ALTER TABLE [dbo].[tDatabase] ADD  CONSTRAINT [DF_tServerDatabase_Active]  DEFAULT ((1)) FOR [Active]
GO

ALTER TABLE [dbo].[tDatabase]  WITH CHECK ADD  CONSTRAINT [FK_tServerDatabase_tServer] FOREIGN KEY([ServerID])
REFERENCES [dbo].[tServer] ([ServerID])
GO

ALTER TABLE [dbo].[tDatabase] CHECK CONSTRAINT [FK_tServerDatabase_tServer]
GO



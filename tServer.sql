USE [DBA]
GO

/****** Object:  Table [dbo].[tServer]    Script Date: 7/13/2025 12:46:54 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServer](
	[ServerID] [int] IDENTITY(0,1) NOT NULL,
	[ServerGroupID] [int] NOT NULL,
	[LinkedServerID] [int] NOT NULL,
	[ServerName] [nvarchar](128) NOT NULL,
	[IsLinked] [bit] NOT NULL,
	[IsSQLServer] [bit] NOT NULL,
	[IsProduction] [bit] NOT NULL,
	[DefaultBackupStrategyID] [int] NULL,
	[EnableServerBackup] [bit] NOT NULL,
	[EnableServerRestore] [bit] NOT NULL,
	[EnableServerDBTrack] [bit] NOT NULL,
	[EnableServerLog] [bit] NOT NULL,
	[EnableCounterLog] [bit] NOT NULL,
	[EnableIOLog] [bit] NOT NULL,
	[EnableMultiExecNotification] [bit] NOT NULL,
	[EnableLongExecNotification] [bit] NOT NULL,
	[EnablePwdPolicyCheckNotification] [bit] NOT NULL,
	[EnableHighCPUNotification] [bit] NOT NULL,
	[HighCPUSQLTreshold] [tinyint] NULL,
	[HighCPUOtherTreshold] [tinyint] NULL,
	[EnableMemoryManagement] [bit] NOT NULL,
	[EnableSessionCountNotification] [bit] NOT NULL,
	[SessionCountThreshold] [int] NULL,
	[EnableBlockNotification] [bit] NOT NULL,
	[BlockNotificationSecThreshold] [int] NULL,
	[EnablePingNotification] [bit] NULL,
	[EnableServerLogNotification] [bit] NOT NULL,
	[LogNotificationLastID] [int] NULL,
	[EnableAgentNotification] [bit] NOT NULL,
	[AgentNotificationLastID] [int] NULL,
	[EnableServerStateNotification] [bit] NOT NULL,
	[ServerStateNotificationLastDate] [datetime] NULL,
	[EnableReplicationMaintenance] [bit] NOT NULL,
	[DefaultEnableIndexMaintenance] [bit] NOT NULL,
	[DefaultReindexStrategyID] [int] NULL,
	[DefaultEnableStatisticsMaintenance] [bit] NOT NULL,
	[DefaultStatisticsMaintenanceStrategyID] [int] NULL,
	[DefaultEnableSpaceMaintenance] [bit] NOT NULL,
	[DefaultEnableBackup] [bit] NOT NULL,
	[DefaultEnableRestore] [bit] NOT NULL,
	[DefaultEnableRestoreKillSession] [bit] NOT NULL,
	[DefaultEnableLogQueryHistory] [bit] NOT NULL,
	[DefaultEnablePartitionMaintenance] [bit] NOT NULL,
	[DefaultPartitionStrategyID] [int] NULL,
	[IsSysServer] [bit] NOT NULL,
	[Active] [bit] NOT NULL,
	[ClusterID] [int] NULL,
	[ISAG] [bit] NULL,
	[EnableTraceFlagNotification] [bit] NULL,
	[EnableIPv4ChangeNotification] [bit] NULL,
	[IPv4ChangeNotificationLastDate] [datetime] NULL,
	[MaxMemoryPctg] [tinyint] NOT NULL,
	[long_exec_threshold_seconds] [int] NULL,
	[date_inactive] [date] NULL,
 CONSTRAINT [pk_tServer] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_ServerGroupID]  DEFAULT ((0)) FOR [ServerGroupID]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerIsLinked]  DEFAULT ((0)) FOR [IsLinked]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerIsSQLServer]  DEFAULT ((0)) FOR [IsSQLServer]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerIsProduction]  DEFAULT ((1)) FOR [IsProduction]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultBackupStrategy]  DEFAULT ((1)) FOR [DefaultBackupStrategyID]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerEnableServerBackup]  DEFAULT ((0)) FOR [EnableServerBackup]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerEnableServerRestore]  DEFAULT ((0)) FOR [EnableServerRestore]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerEnableServerDBCheck]  DEFAULT ((1)) FOR [EnableServerDBTrack]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableServerLog]  DEFAULT ((1)) FOR [EnableServerLog]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerServerDefaultEnableCounterLog]  DEFAULT ((1)) FOR [EnableCounterLog]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableIOLog]  DEFAULT ((1)) FOR [EnableIOLog]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableMultiProcNotification]  DEFAULT ((0)) FOR [EnableMultiExecNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableHighCPUNotification1]  DEFAULT ((1)) FOR [EnableLongExecNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableCheckPolicyNotification]  DEFAULT ((0)) FOR [EnablePwdPolicyCheckNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableHighCPUNotification]  DEFAULT ((1)) FOR [EnableHighCPUNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_HighCPUNotificationTreshold]  DEFAULT ((75)) FOR [HighCPUSQLTreshold]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_HighCPUOtherTreshold]  DEFAULT ((75)) FOR [HighCPUOtherTreshold]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableMemoryManagement]  DEFAULT ((0)) FOR [EnableMemoryManagement]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableConnectionCountNotification]  DEFAULT ((1)) FOR [EnableSessionCountNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_SessionCountThreshold]  DEFAULT ((1500)) FOR [SessionCountThreshold]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableBlockNotification]  DEFAULT ((1)) FOR [EnableBlockNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_BlockNotificationSecThreshold]  DEFAULT ((30)) FOR [BlockNotificationSecThreshold]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnablePingNotification]  DEFAULT ((1)) FOR [EnablePingNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableLogNotification]  DEFAULT ((1)) FOR [EnableServerLogNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableAgentNotification]  DEFAULT ((1)) FOR [EnableAgentNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableServerStateNotification]  DEFAULT ((1)) FOR [EnableServerStateNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableReplicationMaintenance]  DEFAULT ((1)) FOR [EnableReplicationMaintenance]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerServerDefaultEnableIndexMaintenance]  DEFAULT ((1)) FOR [DefaultEnableIndexMaintenance]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_DefaultReindexStrategyID]  DEFAULT ((1)) FOR [DefaultReindexStrategyID]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultEnableStatisticMaintenance]  DEFAULT ((1)) FOR [DefaultEnableStatisticsMaintenance]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_DefaultStatisticsMaintenanceStrategyID]  DEFAULT ((1)) FOR [DefaultStatisticsMaintenanceStrategyID]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultEnableSpaceMaintenance]  DEFAULT ((0)) FOR [DefaultEnableSpaceMaintenance]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultEnableBackup]  DEFAULT ((0)) FOR [DefaultEnableBackup]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultEnableRestore]  DEFAULT ((0)) FOR [DefaultEnableRestore]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultEnableRestoreKillSession]  DEFAULT ((0)) FOR [DefaultEnableRestoreKillSession]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerDefaultEnableLogQueryHistory]  DEFAULT ((0)) FOR [DefaultEnableLogQueryHistory]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServerServerDefaultEnablePartitionMaintenance]  DEFAULT ((1)) FOR [DefaultEnablePartitionMaintenance]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_DefaultPartitionStrategyID]  DEFAULT ((1)) FOR [DefaultPartitionStrategyID]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_IsSysServer]  DEFAULT ((0)) FOR [IsSysServer]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_Active]  DEFAULT ((1)) FOR [Active]
GO

ALTER TABLE [dbo].[tServer] ADD  DEFAULT ((0)) FOR [ISAG]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_EnableTraceFlagNotification]  DEFAULT ((1)) FOR [EnableTraceFlagNotification]
GO

ALTER TABLE [dbo].[tServer] ADD  CONSTRAINT [DF_tServer_MaxMemoryPctg]  DEFAULT ((50)) FOR [MaxMemoryPctg]
GO

ALTER TABLE [dbo].[tServer]  WITH CHECK ADD  CONSTRAINT [FK_tServer_tServerGroup] FOREIGN KEY([ServerGroupID])
REFERENCES [dbo].[tServerGroup] ([ServerGroupID])
GO

ALTER TABLE [dbo].[tServer] CHECK CONSTRAINT [FK_tServer_tServerGroup]
GO



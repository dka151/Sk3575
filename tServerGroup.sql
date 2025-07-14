USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tServerGroup]    Script Date: 7/14/2025 12:20:14 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServerGroup](
	[ServerGroupID] [int] IDENTITY(0,1) NOT NULL,
	[ServerGroupName] [nvarchar](128) NULL,
	[ServerNamePattern] [nvarchar](128) NOT NULL,
	[ServerNamePatternPriority] [tinyint] NULL,
	[IsProduction] [bit] NOT NULL,
	[DefaultBackupStrategyID] [int] NULL,
	[DefaultEnableServerBackup] [bit] NOT NULL,
	[DefaultEnableServerRestore] [bit] NOT NULL,
	[DefaultEnableServerDBTrack] [bit] NOT NULL,
	[DefaultEnableServerLog] [bit] NOT NULL,
	[DefaultEnableCounterLog] [bit] NOT NULL,
	[DefaultEnableIOLog] [bit] NOT NULL,
	[DefaultEnableMultiExecNotification] [bit] NOT NULL,
	[DefaultEnableLongExecNotification] [bit] NOT NULL,
	[DefaultEnablePwdPolicyCheckNotification] [bit] NOT NULL,
	[DefaultEnableHighCPUNotification] [bit] NOT NULL,
	[DefaultHighCPUSQLTreshold] [tinyint] NULL,
	[DefaultHighCPUOtherTreshold] [tinyint] NULL,
	[DefaultEnableMemoryManagement] [bit] NOT NULL,
	[DefaultEnableSessionCountNotification] [bit] NOT NULL,
	[DefaultSessionCountThreshold] [int] NULL,
	[DefaultEnableBlockNotification] [bit] NOT NULL,
	[DefaultBlockNotificationSecThreshold] [int] NULL,
	[DefaultEnablePingNotification] [bit] NULL,
	[DefaultEnableServerLogNotification] [bit] NOT NULL,
	[DefaultEnableAgentNotification] [bit] NOT NULL,
	[DefaultEnableServerStateNotification] [bit] NOT NULL,
	[DefaultEnableReplicationMaintenance] [bit] NOT NULL,
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
 CONSTRAINT [pk_tServerGroup] PRIMARY KEY CLUSTERED 
(
	[ServerGroupID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupIsProduction]  DEFAULT ((1)) FOR [IsProduction]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultBackupStrategy]  DEFAULT ((1)) FOR [DefaultBackupStrategyID]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupEnableServerBackup]  DEFAULT ((0)) FOR [DefaultEnableServerBackup]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupEnableServerRestore]  DEFAULT ((0)) FOR [DefaultEnableServerRestore]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupEnableServerDBCheck]  DEFAULT ((1)) FOR [DefaultEnableServerDBTrack]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableServerLog]  DEFAULT ((1)) FOR [DefaultEnableServerLog]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupServerDefaultEnableCounterLog]  DEFAULT ((1)) FOR [DefaultEnableCounterLog]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableIOLog]  DEFAULT ((1)) FOR [DefaultEnableIOLog]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableMultiProcNotification]  DEFAULT ((0)) FOR [DefaultEnableMultiExecNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableHighCPUNotification1]  DEFAULT ((1)) FOR [DefaultEnableLongExecNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableCheckPolicyNotification]  DEFAULT ((0)) FOR [DefaultEnablePwdPolicyCheckNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableHighCPUNotification]  DEFAULT ((1)) FOR [DefaultEnableHighCPUNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_HighCPUNotificationTreshold]  DEFAULT ((75)) FOR [DefaultHighCPUSQLTreshold]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_HighCPUOtherTreshold]  DEFAULT ((75)) FOR [DefaultHighCPUOtherTreshold]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableMemoryManagement]  DEFAULT ((0)) FOR [DefaultEnableMemoryManagement]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableConnectionCountNotification]  DEFAULT ((1)) FOR [DefaultEnableSessionCountNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_SessionCountThreshold]  DEFAULT ((1500)) FOR [DefaultSessionCountThreshold]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableBlockNotification]  DEFAULT ((1)) FOR [DefaultEnableBlockNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_BlockNotificationSecThreshold]  DEFAULT ((30)) FOR [DefaultBlockNotificationSecThreshold]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnablePingNotification]  DEFAULT ((1)) FOR [DefaultEnablePingNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableLogNotification]  DEFAULT ((1)) FOR [DefaultEnableServerLogNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableAgentNotification]  DEFAULT ((1)) FOR [DefaultEnableAgentNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_EnableServerStateNotification]  DEFAULT ((1)) FOR [DefaultEnableServerStateNotification]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_DefaultEnableReplicationMaintenance]  DEFAULT ((1)) FOR [DefaultEnableReplicationMaintenance]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupServerDefaultEnableIndexMaintenance]  DEFAULT ((1)) FOR [DefaultEnableIndexMaintenance]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_DefaultReindexStrategyID]  DEFAULT ((1)) FOR [DefaultReindexStrategyID]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultEnableStatisticMaintenance]  DEFAULT ((1)) FOR [DefaultEnableStatisticsMaintenance]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_DefaultStatisticsMaintenanceStrategyID]  DEFAULT ((1)) FOR [DefaultStatisticsMaintenanceStrategyID]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultEnableSpaceMaintenance]  DEFAULT ((0)) FOR [DefaultEnableSpaceMaintenance]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultEnableBackup]  DEFAULT ((0)) FOR [DefaultEnableBackup]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultEnableRestore]  DEFAULT ((0)) FOR [DefaultEnableRestore]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultEnableRestoreKillSession]  DEFAULT ((0)) FOR [DefaultEnableRestoreKillSession]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupDefaultEnableLogQueryHistory]  DEFAULT ((0)) FOR [DefaultEnableLogQueryHistory]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroupServerDefaultEnablePartitionMaintenance]  DEFAULT ((1)) FOR [DefaultEnablePartitionMaintenance]
GO

ALTER TABLE [dbo].[tServerGroup] ADD  CONSTRAINT [DF_tServerGroup_DefaultPartitionStrategyID]  DEFAULT ((1)) FOR [DefaultPartitionStrategyID]
GO



USE [DBA]
GO

/****** Object:  Table [dbo].[tBackupSet]    Script Date: 7/13/2025 12:42:44 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tBackupSet](
	[ServerID] [int] NOT NULL,
	[ServerDatabaseName] [nvarchar](128) NOT NULL,
	[ServerBackupSetID] [int] NOT NULL,
	[ServerBackupSetUUID] [uniqueidentifier] NOT NULL,
	[DatabaseGUID] [uniqueidentifier] NOT NULL,
	[DatabaseFamilyGUID] [uniqueidentifier] NOT NULL,
	[BackupStartDate] [datetime] NOT NULL,
	[BackupFinishDate] [datetime] NOT NULL,
	[BackupType] [char](1) NOT NULL,
	[CompressedBackupSize] [decimal](20, 0) NULL,
	[BackupSize] [decimal](20, 0) NULL,
	[BackupName] [nvarchar](128) NULL,
	[UserName] [nvarchar](128) NULL,
	[SoftwareMajorVersion] [tinyint] NULL,
	[SoftwareMinorVersion] [tinyint] NULL,
	[SoftwareBuildVersion] [smallint] NULL,
	[TimeZone] [smallint] NULL,
	[FirstLSN] [decimal](25, 0) NOT NULL,
	[LastLSN] [decimal](25, 0) NULL,
	[CheckpointLSN] [decimal](25, 0) NULL,
	[DatabaseBackupLSN] [decimal](25, 0) NULL,
	[DifferentialBaseLSN] [decimal](25, 0) NULL,
	[DifferentialBaseGUID] [uniqueidentifier] NULL,
	[FirstRecoveryForkGUID] [uniqueidentifier] NOT NULL,
	[LastRecoveryForkGUID] [uniqueidentifier] NOT NULL,
	[ForkPointLSN] [decimal](25, 0) NULL,
	[IsDamaged] [bit] NOT NULL,
	[IsChecksum] [bit] NOT NULL,
	[IsCopyOnly] [bit] NOT NULL,
	[IsReadOnly] [bit] NOT NULL,
	[IsBeginsLogChain] [bit] NOT NULL,
	[IsBulkLoggedData] [bit] NOT NULL,
 CONSTRAINT [PK_tBackupSet] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC,
	[ServerDatabaseName] ASC,
	[BackupType] ASC,
	[BackupStartDate] ASC,
	[FirstLSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = ON, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



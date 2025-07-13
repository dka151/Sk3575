USE [DBA]
GO

/****** Object:  Table [dbo].[tBackupSetMedia]    Script Date: 7/13/2025 12:42:53 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tBackupSetMedia](
	[ServerID] [int] NOT NULL,
	[ServerBackupSetUUID] [uniqueidentifier] NOT NULL,
	[FamilySequenceNumber] [tinyint] NOT NULL,
	[Mirror] [tinyint] NOT NULL,
	[PhyicalDeviceName] [nvarchar](260) NULL,
	[DeviceType] [tinyint] NULL,
	[PhysicalBlockSize] [int] NULL,
 CONSTRAINT [PK_tBackupSetMedia] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC,
	[ServerBackupSetUUID] ASC,
	[FamilySequenceNumber] ASC,
	[Mirror] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



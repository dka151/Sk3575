USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tAGDetails]    Script Date: 7/13/2025 2:31:39 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tAGDetails](
	[IdAGDetails] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NOT NULL,
	[GroupID] [nvarchar](128) NOT NULL,
	[AGName] [nvarchar](128) NOT NULL,
	[ServerName] [nvarchar](128) NOT NULL,
	[SQLInstance] [nvarchar](128) NOT NULL,
	[PrimaryReplica] [nvarchar](128) NOT NULL,
	[ReplicaServerName] [nvarchar](128) NOT NULL,
	[RoleDescription] [nvarchar](128) NULL,
	[TimeStamp] [datetime2](7) NOT NULL,
 CONSTRAINT [PK_tAGDetails] PRIMARY KEY CLUSTERED 
(
	[IdAGDetails] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tAGDetails] ADD  CONSTRAINT [DF_tAGDetails_TimeStamp]  DEFAULT (getdate()) FOR [TimeStamp]
GO



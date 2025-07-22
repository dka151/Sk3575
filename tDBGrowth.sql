USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDBGrowth]    Script Date: 7/22/2025 11:30:32 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDBGrowth](
	[DBGrowthID] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NOT NULL,
	[DateCreated] [datetime] NOT NULL,
	[strDBName] [varchar](255) NOT NULL,
	[DBSize_MB] [decimal](15, 2) NOT NULL,
	[UnAllocatedSize_MB] [decimal](15, 2) NOT NULL,
	[Reserved_MB] [decimal](15, 2) NOT NULL,
	[DataUsed_MB] [decimal](15, 2) NOT NULL,
	[IndexUsed_MB] [decimal](15, 2) NOT NULL,
	[UnUsed_MB] [decimal](15, 2) NOT NULL,
 CONSTRAINT [PK_tDBGrowth] PRIMARY KEY CLUSTERED 
(
	[DBGrowthID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [DailyChecks].[tDBGrowth] ADD  CONSTRAINT [DF_tDBGrowth_DateCreated]  DEFAULT (getdate()) FOR [DateCreated]
GO



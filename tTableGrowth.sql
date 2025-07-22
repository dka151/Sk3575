USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tTableGrowth]    Script Date: 7/22/2025 11:31:21 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tTableGrowth](
	[TableGrowthID] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NULL,
	[DateCreated] [datetime] NOT NULL,
	[strDBName] [varchar](255) NOT NULL,
	[strTableNAME] [varchar](255) NOT NULL,
	[Reserved_KB] [bigint] NULL,
	[Data_KB] [bigint] NULL,
	[Index_size_KB] [bigint] NULL,
	[Unused_KB] [bigint] NULL,
	[NumberofRows] [bigint] NULL,
 CONSTRAINT [PK__tTableGrowth__7F60ED59] PRIMARY KEY CLUSTERED 
(
	[TableGrowthID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [DailyChecks].[tTableGrowth] ADD  CONSTRAINT [DF_tTableGrowth_DateCreated]  DEFAULT (getdate()) FOR [DateCreated]
GO



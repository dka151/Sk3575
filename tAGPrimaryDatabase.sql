USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tAGPrimaryDatabase]    Script Date: 7/13/2025 2:31:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tAGPrimaryDatabase](
	[PrimaryDBID] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NOT NULL,
	[ServerDatabaseID] [int] NOT NULL,
	[IsDBPrimary] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[PrimaryDBID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



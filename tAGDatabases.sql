USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tAGDatabases]    Script Date: 7/13/2025 2:31:18 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tAGDatabases](
	[AGID] [int] IDENTITY(1,1) NOT NULL,
	[AGListerName] [nvarchar](128) NOT NULL,
	[AGName] [nvarchar](128) NOT NULL,
	[ServerName] [nvarchar](128) NOT NULL,
	[DatabaseName] [nvarchar](128) NOT NULL,
	[ServerID] [int] NULL,
	[DatabaseID] [int] NULL,
 CONSTRAINT [PK_tAGDatabases] PRIMARY KEY CLUSTERED 
(
	[AGID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF, DATA_COMPRESSION = PAGE) ON [PRIMARY]
) ON [PRIMARY]
GO



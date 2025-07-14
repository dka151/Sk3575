USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tSchema]    Script Date: 7/14/2025 11:01:11 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tSchema](
	[DatabaseID] [int] NOT NULL,
	[SchemaID] [int] IDENTITY(1,1) NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[SchemaName] [sysname] NOT NULL,
	[ServerSchemaID] [int] NOT NULL,
 CONSTRAINT [PK_tSchema] PRIMARY KEY NONCLUSTERED 
(
	[SchemaID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tSchemaState]    Script Date: 7/14/2025 11:01:18 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tSchemaState](
	[SchemaID] [int] NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[ServerPrincipalID] [int] NULL,
 CONSTRAINT [PK_tSchemaState] PRIMARY KEY NONCLUSTERED 
(
	[SchemaID] ASC,
	[StartDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



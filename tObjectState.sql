USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tObjectState]    Script Date: 7/14/2025 10:55:13 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tObjectState](
	[ObjectID] [int] NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[ServerPrincipalID] [int] NULL,
	[ObjectCreateDate] [datetime] NOT NULL,
	[ObjectModifyDate] [datetime] NOT NULL,
	[IsMSShipped] [bit] NOT NULL,
	[IsSchemaPublished] [bit] NOT NULL,
 CONSTRAINT [PK_tObjectState] PRIMARY KEY NONCLUSTERED 
(
	[ObjectID] ASC,
	[StartDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



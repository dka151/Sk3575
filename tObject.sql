USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tObject]    Script Date: 7/14/2025 10:55:03 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tObject](
	[SchemaID] [int] NOT NULL,
	[ObjectID] [int] IDENTITY(1,1) NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[ObjectName] [nvarchar](128) NOT NULL,
	[ObjectType] [varchar](50) NOT NULL,
	[ServerSchemaID] [int] NOT NULL,
	[ServerObjectID] [int] NOT NULL,
	[ServerParentObjectID] [int] NOT NULL,
 CONSTRAINT [PK_tObject] PRIMARY KEY NONCLUSTERED 
(
	[ObjectID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



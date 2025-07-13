USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabaseConfiguration]    Script Date: 7/13/2025 1:53:24 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabaseConfiguration](
	[DatabaseID] [int] NOT NULL,
	[ConfigurationName] [nvarchar](128) NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[ConfigurationValue] [sql_variant] NOT NULL,
 CONSTRAINT [PK_tDatabaseConfiguration] PRIMARY KEY CLUSTERED 
(
	[DatabaseID] ASC,
	[ConfigurationName] ASC,
	[StartDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tDatabaseConfiguration]  WITH CHECK ADD  CONSTRAINT [FK_tDatabaseConfiguration_tDatabase] FOREIGN KEY([DatabaseID])
REFERENCES [dbo].[tDatabase] ([DatabaseID])
GO

ALTER TABLE [dbo].[tDatabaseConfiguration] CHECK CONSTRAINT [FK_tDatabaseConfiguration_tDatabase]
GO



USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tServerConfiguration]    Script Date: 7/14/2025 10:38:56 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServerConfiguration](
	[ServerID] [int] NOT NULL,
	[ConfigurationName] [nvarchar](35) NOT NULL,
	[StartDate] [datetime] NOT NULL,
	[EndDate] [datetime] NULL,
	[ConfigurationValue] [sql_variant] NULL,
 CONSTRAINT [PK_tServerConfiguration] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC,
	[ConfigurationName] ASC,
	[StartDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServerConfiguration]  WITH CHECK ADD  CONSTRAINT [FK_tServerConfiguration_tServer] FOREIGN KEY([ServerID])
REFERENCES [dbo].[tServer] ([ServerID])
GO

ALTER TABLE [dbo].[tServerConfiguration] CHECK CONSTRAINT [FK_tServerConfiguration_tServer]
GO



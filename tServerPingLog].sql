USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tServerPingLog]    Script Date: 7/14/2025 10:39:42 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServerPingLog](
	[ServerID] [int] NOT NULL,
	[LastPingSource] [varchar](255) NULL,
	[LastPingDate] [datetime] NULL,
	[LastNotificationDate] [datetime] NULL,
 CONSTRAINT [PK_tServerPingProcessLog_1] PRIMARY KEY CLUSTERED 
(
	[ServerID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServerPingLog]  WITH CHECK ADD  CONSTRAINT [FK_tServerPingLog_tServer] FOREIGN KEY([ServerID])
REFERENCES [dbo].[tServer] ([ServerID])
GO

ALTER TABLE [dbo].[tServerPingLog] CHECK CONSTRAINT [FK_tServerPingLog_tServer]
GO



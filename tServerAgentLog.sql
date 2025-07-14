USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tServerAgentLog]    Script Date: 7/14/2025 10:38:51 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServerAgentLog](
	[LogID] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NOT NULL,
	[LogDate] [datetime] NOT NULL,
	[ErrorLevel] [tinyint] NULL,
	[Text] [nvarchar](max) NOT NULL,
	[Error] [int] NULL,
	[ErrorPrefix] [char](3) NULL,
	[State] [int] NULL,
 CONSTRAINT [pk_tServerAgentLog] PRIMARY KEY NONCLUSTERED 
(
	[LogID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServerAgentLog]  WITH CHECK ADD  CONSTRAINT [FK_tServerAgentLog_tServer] FOREIGN KEY([ServerID])
REFERENCES [dbo].[tServer] ([ServerID])
GO

ALTER TABLE [dbo].[tServerAgentLog] CHECK CONSTRAINT [FK_tServerAgentLog_tServer]
GO



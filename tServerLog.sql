USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tServerLog]    Script Date: 7/14/2025 10:39:23 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServerLog](
	[LogID] [int] IDENTITY(1,1) NOT NULL,
	[ServerID] [int] NOT NULL,
	[LogDate] [datetime] NOT NULL,
	[ProcessInfo] [varchar](128) NOT NULL,
	[Text] [nvarchar](max) NOT NULL,
	[Error] [int] NULL,
	[Severity] [int] NULL,
	[State] [int] NULL,
	[ParentError] [int] NULL,
	[ParentSeverity] [int] NULL,
	[ParentState] [nchar](10) NULL,
	[TextCnt] [int] NOT NULL,
 CONSTRAINT [pk_tServerLog] PRIMARY KEY NONCLUSTERED 
(
	[LogID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 85, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServerLog] ADD  CONSTRAINT [DF_tServerLog_TextCnt]  DEFAULT ((1)) FOR [TextCnt]
GO

ALTER TABLE [dbo].[tServerLog]  WITH CHECK ADD  CONSTRAINT [FK_tServerLog_tServer] FOREIGN KEY([ServerID])
REFERENCES [dbo].[tServer] ([ServerID])
GO

ALTER TABLE [dbo].[tServerLog] CHECK CONSTRAINT [FK_tServerLog_tServer]
GO



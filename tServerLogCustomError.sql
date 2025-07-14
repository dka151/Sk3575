USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tServerLogCustomError]    Script Date: 7/14/2025 10:56:34 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tServerLogCustomError](
	[Error] [int] NOT NULL,
	[TextPattern] [nvarchar](255) NOT NULL,
	[Severity] [int] NOT NULL,
	[State] [int] NOT NULL,
	[NotificationPriority] [tinyint] NULL,
 CONSTRAINT [PK_tServerLogCustomError] PRIMARY KEY CLUSTERED 
(
	[Error] ASC,
	[TextPattern] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[tServerLogCustomError] ADD  CONSTRAINT [DF_tServerLogCustomError_Severity]  DEFAULT ((99)) FOR [Severity]
GO

ALTER TABLE [dbo].[tServerLogCustomError] ADD  CONSTRAINT [DF_tServerLogCustomError_State]  DEFAULT ((1)) FOR [State]
GO

ALTER TABLE [dbo].[tServerLogCustomError] ADD  CONSTRAINT [DF_tServerLogCustomError_NotificationPriority]  DEFAULT ((0)) FOR [NotificationPriority]
GO



USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tAgentJobSummary]    Script Date: 7/17/2025 2:37:01 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tAgentJobSummary](
	[CaptureDate] [datetime] NOT NULL,
	[ServerName] [sysname] NOT NULL,
	[JobName] [nvarchar](128) NOT NULL,
	[ScheduleName] [nvarchar](128) NOT NULL,
	[LastStartTime] [datetime] NULL,
	[RunDurationHHMMSS] [nvarchar](30) NULL,
	[LastCompletionTime] [datetime] NULL,
	[JobStartTime] [time](7) NULL,
	[JobEndTime] [time](7) NULL,
	[JobFrequency] [varchar](35) NULL,
	[JobFrequencyType] [varchar](25) NULL,
	[JobFrequencyInterval] [int] NULL,
	[Recurrence] [nvarchar](240) NULL,
	[LastRunStatus] [varchar](25) NULL,
	[SummaryInfoID] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [PKtAgentJobSummary] PRIMARY KEY CLUSTERED 
(
	[SummaryInfoID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

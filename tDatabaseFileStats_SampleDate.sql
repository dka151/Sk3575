USE [DBMonitor]
GO

/****** Object:  Table [dbo].[tDatabaseFileStats_SampleDate]    Script Date: 7/13/2025 1:55:00 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[tDatabaseFileStats_SampleDate](
	[SampleDateID] [int] IDENTITY(1,1) NOT NULL,
	[GlobalSampleDate] [datetime] NOT NULL,
 CONSTRAINT [PK_tDatabaseFileStats_SampleDate] PRIMARY KEY CLUSTERED 
(
	[SampleDateID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO



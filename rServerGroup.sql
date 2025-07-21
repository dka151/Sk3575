USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rServerGroup]    Script Date: 7/21/2025 10:54:27 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[rServerGroup] AS
SELECT ServerGroupID, ServerGroupName FROM tServerGroup

GO
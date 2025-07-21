USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rVolumeStatusLog]    Script Date: 7/21/2025 12:27:59 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[rVolumeStatusLog] @ServerIDs Int AS

declare @SID int = @ServerIDs

Select * from tSQLInstanceStorageVolumeStatus SISV
where (@sid = 0 or SISV.serverid = @SID)
and (DAY(SISV.TimeStamp)=day(GETDATE()) AND month(SISV.TimeStamp)=month(GETDATE()) AND Year(SISV.TimeStamp)=year(GETDATE()))
order by sisv.timestamp DESC


GO

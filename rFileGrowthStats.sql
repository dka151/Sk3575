USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[c]    Script Date: 7/22/2025 11:27:40 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



----EXEC  [dbo].[rFileGrowthStats]  @serverid = 127


CREATE OR ALTER PROCEDURE [dbo].[rFileGrowthStats]  
@DateFrom DATE = NULL,
@DateTo DATE = NULL,
@ServerID INT 
AS

BEGIN


IF OBJECT_ID ('tempdb..#FileGrowthStatus','U') IS NOT NULL DROP TABLE #FileGrowthStatus  
CREATE TABLE #FileGrowthStatus    
 ([ServerID] INT NOT NULL      
 ,[ServerName] sysname NOT NULL      
 ,[DatabaseName] NVARCHAR(255) NOT NULL  
 ,[LogicalFileName] sysname NOT NULL
 ,[PhysicalFileName] sysname NOT NULL
 ,[SpaceUsedGB] BIGINT
 ,[CaptureDate] DATETIME      
 )    
IF @DateTo IS NULL 
	SET @DateTo = CONVERT(date, GETUTCDATE());
IF @DateFrom IS NULL 
	SET @DateFrom = DATEADD(DAY, -7, @DateTo);


DECLARE @sql nvarchar(MAX) = N'';
SET @sql = N'
     SELECT [FG].[ServerID], 
			[t].servername, 
            [FG].[DatabaseName], 
			[FG].[LogicalFileName],
			[FG].[PhysicalFileName],
            ([FG].[SpaceUsedMB]/1024) - LAG(([FG].[SpaceUsedMB]/1024)) OVER(PARTITION BY [FG].[ServerID], [FG].[DatabaseName], [FG].[LogicalFileName],[FG].[PhysicalFileName]  ORDER BY [FG].[CaptureDate]) AS [SpaceUsedGB], 
            CONVERT(date, [FG].[CaptureDate]) AS [CaptureDate]
    FROM    [DBMonitor].[dbo].[tFileInfo] [FG]
	join tserver t on t.serverid = fG.serverid
    WHERE   (@ServerID = 0 OR [FG].[ServerID] = @ServerID)
            AND [FG].[CaptureDate] >= DATEADD(DAY, -1, @DateFrom) AND [FG].[CaptureDate] < DATEADD(DAY, 1, @DateTo)
';

INSERT INTO #FileGrowthStatus ([ServerID], [ServerName], [DatabaseName], [LogicalFileName], [PhysicalFileName], [SpaceUsedGB], [CaptureDate])   
EXEC sp_executesql @sql, N'@ServerID int, @DateFrom date, @DateTo date', @ServerID=@ServerID, @DateFrom=@DateFrom, @DateTo=@DateTo;

SELECT 
			d.[ServerID], 
			d.[ServerName], 
            d.[DatabaseName], 
			d.[LogicalFileName],
			d.[PhysicalFileName],
			d.[SpaceUsedGB],
			d.[CaptureDate]
	FROM #FileGrowthStatus d
WHERE d.[SpaceUsedGB] > 0


END


GO



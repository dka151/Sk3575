USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rDBGrowthStat]    Script Date: 7/22/2025 3:50:35 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


--Exec [dbo].[rDBGrowthStat] 

CREATE OR ALTER   PROCEDURE [dbo].[rDBGrowthStat]
    @DateFrom DATE = NULL
   ,@DateTo DATE = NULL
   ,@ServerID INT = 0
   --,@dboType INT = 1
   --,@ServerRegion NVARCHAR(50) = N'EU'
AS
BEGIN

--DECLARE     @DateFrom DATE = '20200901'
--   ,@DateTo DATE = '20211101'a
--   ,@ServerID INT = 0
--   ,@dboType INT = 1
--   ,@ServerRegion NVARCHAR(50) = 'EU';

   --DROP TABLE IF EXISTS #DBGrowthStatus;

    SET NOCOUNT ON;

    IF @DateTo IS NULL
        SET @DateTo = CONVERT(DATE, GETUTCDATE());
    IF @DateFrom IS NULL
        SET @DateFrom = DATEADD(DAY, -7, @DateTo);

    SELECT      d.ServerID
               ,d.ServerName
               ,d.DateofGrowth
               ,d.DatabaseName
               ,SUM(d.DBGrowthGB) AS DBGrowthGB
               ,SUM(SUM(d.DBGrowthGB)) OVER (PARTITION BY d.ServerName, d.DatabaseName ORDER BY d.DateofGrowth) AS CumulativeGrowthGB
    FROM        (   SELECT  [DG].[ServerID]
                           ,[t].[servername]
                           ,[DG].[strDBName] AS [DatabaseName]
                           ,CAST([DG].[DBSize_MB] / 1024.0 - LAG([DG].[DBSize_MB] / 1024.0) OVER (PARTITION BY [DG].[ServerID]
                                                                                                              ,[DG].[strDBName]
                                                                                                   ORDER BY [DG].[DateCreated]
                                                                                                 ) AS INT) AS [DBGrowthGB]
                           ,CONVERT(DATE, [DG].[DateCreated]) AS [DateofGrowth]
                    FROM    [dbo].[tDBGrowth] AS [DG]
                            INNER JOIN [dbo].[tserver] AS [t] ON [t].[serverid] = [DG].[serverid]
                    WHERE   (@ServerID = 0
                             OR  [DG].[ServerID] = @ServerID
                            )
                            AND [DG].[DateCreated] >= DATEADD(DAY, -1, @DateFrom)
                            AND [DG].[DateCreated] < DATEADD(DAY, 1, @DateTo)
    ) AS d 
    WHERE       d.DBGrowthGB >= 0
    GROUP BY    d.ServerID
               ,d.ServerName
               ,d.DateofGrowth
               ,d.DatabaseName;
END;
GO



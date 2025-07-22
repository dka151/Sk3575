USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rTableGrowthStats]    Script Date: 7/22/2025 3:50:43 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


--EXEC [dbo].[rTableGrowthStats]  @serverid=9, @DateFrom = '2021-12-01', @DATETO = '2021-12-08'

CREATE OR ALTER PROCEDURE [dbo].[rTableGrowthStats]  
@DateFrom DATE = NULL,
@DateTo DATE = NULL,
@ServerID INT 
AS

BEGIN

IF OBJECT_ID ('tempdb..#TableGrowthStatus','U') IS NOT NULL DROP TABLE #TableGrowthStatus  
CREATE TABLE #TableGrowthStatus    
 ([ServerID] INT NOT NULL      
 ,[ServerName] sysname NOT NULL      
 ,[DatabaseName] NVARCHAR(255) NOT NULL  
 ,[TableName] sysname NOT NULL
 ,[ReservedGB] BIGINT
 ,[DataGB] BIGINT
 ,[IndexSizeGB] bigint 
 ,[DateofGrowth] DATETIME      
 )    
IF @DateTo IS NULL 
	SET @DateTo = CONVERT(date, GETUTCDATE());
IF @DateFrom IS NULL 
	SET @DateFrom = DATEADD(DAY, -7, @DateTo);

	DECLARE @sql nvarchar(MAX) = N'';
	SET @sql = N'
    SELECT  [tG].[ServerID], 
			t.servername, 
            [tG].[strDBName], 
			[TG].[strTableNAME],
            ([tG].[Reserved_KB]/1024/1024) - LAG(([tG].[Reserved_KB]/1024/1024)) OVER(PARTITION BY [tG].[ServerID], [tG].[strDBName], [tG].[strTableNAME]  ORDER BY [tG].[DateCreated]) AS [ReservedGB], 
            ([tG].[Data_KB]/1024/1024) - LAG(([tG].[Data_KB]/1024/1024)) OVER(PARTITION BY [tG].[ServerID], [tG].[strDBName], [tG].[strTableNAME] ORDER BY [tG].[DateCreated]) AS [DataGB], 
            ([tG].[Index_size_KB]/1024/1024) - LAG(([tG].[Index_size_KB]/1024/1024)) OVER(PARTITION BY [tG].[ServerID], [tG].[strDBName], [tG].[strTableNAME] ORDER BY [tG].[DateCreated]) AS [IndexSizeGB], 
            CONVERT(date, [tG].[DateCreated]) AS [DateCreated]
    FROM    [DBMonitor].[dbo].[tTableGrowth] [TG]
	join tserver t on t.serverid = tG.serverid
    WHERE   (@ServerID = 0 OR [tG].[ServerID] = @ServerID)
            AND [tG].[DateCreated] >= DATEADD(DAY, -1, @DateFrom) AND [tG].[DateCreated] < DATEADD(DAY, 1, @DateTo)

';

INSERT INTO #TableGrowthStatus ([ServerID], [ServerName], [DatabaseName], [TableName], [ReservedGB], [DataGB], [IndexSizeGB], [DateofGrowth])   
EXEC sp_executesql @sql, N'@ServerID int, @DateFrom date, @DateTo date', @ServerID=@ServerID, @DateFrom=@DateFrom, @DateTo=@DateTo;


SELECT x.*,
SUM(x.TableGrowthGB) OVER (PARTITION BY x.serverid,x.DatabaseName,x.TableName ORDER BY x.DateofGrowth) AS CumulativeGrowth
 FROM 
(
SELECT 
			d.ServerID, 
			d.servername, 
            d.DatabaseName, 
			d.TableName,
			d.ReservedGB + d.IndexSizeGB AS TableGrowthGB,
			d.DateofGrowth
	FROM #TableGrowthStatus d
	) x
WHERE  x.TableGrowthGB  > 0

END




GO



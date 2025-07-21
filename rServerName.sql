USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rServerName]    Script Date: 7/21/2025 10:54:41 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[rServerName] @ServerGroupIDs VARCHAR(MAX) AS

DECLARE @X XML
--Get a list of Servers
SET @X='<r>'+REPLACE(@ServerGroupIDs,',','</r>'+'<r>')+'</r>'
;WITH SX AS
	(SELECT DISTINCT
			Tbl.Col.value('.', 'INT') AS ServerGroupID
	FROM   @X.nodes('//r') Tbl(Col)
)
	
SELECT 
	S.ServerID, S.ServerName
FROM 
	tServer S
	JOIN SX ON S.ServerGroupID=SX.ServerGroupID
--WHERE 
--	S.Active=1

GO



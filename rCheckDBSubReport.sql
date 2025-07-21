USE [DBMonitor]
GO

/****** Object:  StoredProcedure [dbo].[rCheckDBSubReport]    Script Date: 7/21/2025 1:41:45 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE OR ALTER PROCEDURE [dbo].[rCheckDBSubReport] @ServerIDs INT
AS

BEGIN

;WITH CheckDB
AS (SELECT D.DatabaseName,
           CONVERT(DATETIME, DCT.ConfigurationValue) AS CREATE_DATE,
           CONVERT(INT, DCE.ConfigurationValue) AS CHECKDB_Errors,
           CONVERT(DATETIME, DCD.ConfigurationValue) AS CHECKDB_Date,
           CASE
               WHEN CONVERT(INT, DCE.ConfigurationValue) > 0 THEN
                   'R' --Errors Found   
               WHEN
               (
                   CONVERT(DATETIME, DCD.ConfigurationValue) <= CURRENT_TIMESTAMP - 15
                   AND CONVERT(DATETIME, DCD.ConfigurationValue) <> 0
               ) THEN
                   'O' --Expired
               WHEN
               (
                   CONVERT(DATETIME, DCD.ConfigurationValue) = 0
                   AND CONVERT(INT, DCE.ConfigurationValue) = -1
                   AND CONVERT(DATETIME, DCT.ConfigurationValue) >= CURRENT_TIMESTAMP - 15
               ) THEN
                   'G' --New Database
               WHEN
               (
                   CONVERT(DATETIME, DCD.ConfigurationValue) = 0
                   AND CONVERT(INT, DCE.ConfigurationValue) = -1
                   AND CONVERT(DATETIME, DCT.ConfigurationValue) < CURRENT_TIMESTAMP - 15
               ) THEN
                   'O' --DBCC CheckDB Never happened  
			   WHEN CONVERT(INT, DCE.ConfigurationValue) = 0 THEN
                   'G' --No Erros Found		
               ELSE
                   'R'
           END --Unknown Reason    
           AS Severity
    FROM dbo.tServer S
        JOIN dbo.tDatabase D
            ON D.ServerID = S.ServerID
               AND S.ServerID = @ServerIDs
        JOIN dbo.tDatabaseConfiguration DCS
            ON DCS.DatabaseID = D.DatabaseID
               AND DCS.ConfigurationName = N'is_in_standby'
               AND DCS.EndDate IS NULL
               AND CONVERT(BIT, DCS.ConfigurationValue) = 0
        JOIN dbo.tDatabaseConfiguration DCD
            ON DCD.DatabaseID = D.DatabaseID
               AND DCD.ConfigurationName = N'CHECKDB_Date'
               AND DCD.EndDate IS NULL
        JOIN dbo.tDatabaseConfiguration DCE
            ON DCE.DatabaseID = D.DatabaseID
               AND DCE.ConfigurationName = N'CHECKDB_Errors'
               AND DCE.EndDate IS NULL
        JOIN dbo.tDatabaseConfiguration DCT
            ON DCT.DatabaseID = D.DatabaseID
               AND DCT.ConfigurationName = N'CREATE_DATE'
               AND DCT.EndDate IS NULL
    WHERE S.Active = 1
          AND D.Active = 1
		  ),
      A
AS (SELECT SUBSTRING([Text], 15, CHARINDEX(N')', [Text]) - 15) AS DatabaseName,
           L.Text AS [CheckDBOutput],
           L.LogDate AS [LastCheckDate]
    FROM dbo.tServerLog L
    WHERE L.ServerID = @ServerIDs
          AND L.LogDate >= CURRENT_TIMESTAMP - 365
          AND [Text] LIKE N'DBCC CHECKDB % found [0-9]% errors and repaired % errors%'),
      D
AS (SELECT *,
           ROW_NUMBER() OVER (PARTITION BY DatabaseName ORDER BY LastCheckDate DESC) RN
    FROM A),
      E
AS (SELECT [DatabaseName],
           [CheckDBOutput],
           CONVERT(VARCHAR(20), LastCheckDate, 100) AS [LastCheckDate]
    FROM D
    WHERE RN = 1
    )
SELECT CB.DatabaseName,
       CASE 
	   WHEN CB.CREATE_DATE>= CURRENT_TIMESTAMP-15 THEN ISNULL(E.[CheckDBOutput],'NEW DATABASE CREATED WITHIN LAST 14 DAYS')
	   WHEN CB.CREATE_DATE< CURRENT_TIMESTAMP-15 THEN ISNULL(E.[CheckDBOutput],'NO DATA WAS FOUND WITHIN LAST 365 DAYS') 
	   ELSE ''
	   END AS CheckDBOutput,
       ISNULL(E.LastCheckDate, '') AS LastCheckDate,
       CB.[Severity]
FROM CheckDB CB
    LEFT JOIN E
        ON E.DatabaseName = CB.DatabaseName;

END

GO



/*=============================================================================
  dbo.usp_BlueYonderAptos_SendTransferReport

  Builds an HTML File Transfer Audit Report from
  dbo.BlueYonderAptos_TransferAudit and emails it via Database Mail.

  Designed to be called from a SQL Agent job (e.g. one step per schedule) or
  manually. Reports on files whose transfer STARTED within the last N hours.

  PARAMETERS
    @LookbackHours   Window size in hours. Intended values 8, 12 or 24, but any
                     1..168 is accepted. Default 24.
    @Recipients      Semicolon-separated email list (To). Required.
    @CopyRecipients  Semicolon-separated email list (Cc). Optional.
    @ProfileName     Database Mail profile. Defaults to 'DBAAlert'. Pass NULL to
                     use the server's default profile instead.
    @SubjectPrefix   Text prepended to the subject line. Default 'BlueYonder<->Aptos'.
    @IncludeDetail   1 = include the per-file detail table (default). 0 = summary only.
    @MaxDetailRows   Cap on detail rows rendered (newest first). Default 500.
    @SendIfEmpty     1 = still send when no files in window (default). 0 = skip send.
    @Debug           1 = PRINT the HTML and skip the actual send. Default 0.

  TIME ZONE
    Audit timestamps are stored in UTC (TransferStartUtc). The report shows both
    the UTC window and the equivalent local time using AT TIME ZONE so recipients
    aren't confused. Adjust @DisplayTimeZone for your server's locale.

  SECURITY
    EXECUTE requires membership in msdb role DatabaseMailUserRole (to call
    sp_send_dbmail) plus SELECT on the audit table. Grant EXECUTE to the Agent
    service / proxy account that runs the reporting job.
=============================================================================*/
IF OBJECT_ID('dbo.usp_BlueYonderAptos_SendTransferReport', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_BlueYonderAptos_SendTransferReport;
GO

CREATE PROCEDURE dbo.usp_BlueYonderAptos_SendTransferReport
    @LookbackHours    INT            = 24,
    @Recipients       NVARCHAR(4000),
    @CopyRecipients   NVARCHAR(4000) = NULL,
    @ProfileName      SYSNAME        = N'DBAAlert',
    @SubjectPrefix    NVARCHAR(200)  = N'BlueYonder<->Aptos',
    @IncludeDetail    BIT            = 1,
    @MaxDetailRows    INT            = 500,
    @SendIfEmpty      BIT            = 1,
    @DisplayTimeZone  SYSNAME        = N'GMT Standard Time',
    @Debug            BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ------------------------------------------------------------------
    -- 1. Validate inputs
    ------------------------------------------------------------------
    IF @Recipients IS NULL OR LTRIM(RTRIM(@Recipients)) = N''
    BEGIN
        RAISERROR('@Recipients is required (semicolon-separated email list).', 16, 1);
        RETURN;
    END

    IF @LookbackHours IS NULL OR @LookbackHours < 1 OR @LookbackHours > 168
    BEGIN
        RAISERROR('@LookbackHours must be between 1 and 168. Typical values: 8, 12, 24.', 16, 1);
        RETURN;
    END

    IF @MaxDetailRows IS NULL OR @MaxDetailRows < 1 SET @MaxDetailRows = 500;

    ------------------------------------------------------------------
    -- 2. Window boundaries (UTC) + local display strings
    ------------------------------------------------------------------
    DECLARE @NowUtc   DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @FromUtc  DATETIME2(3) = DATEADD(HOUR, -@LookbackHours, @NowUtc);

    DECLARE @FromLocal NVARCHAR(30) =
        CONVERT(NVARCHAR(30), (@FromUtc AT TIME ZONE 'UTC' AT TIME ZONE @DisplayTimeZone), 120);
    DECLARE @NowLocal  NVARCHAR(30) =
        CONVERT(NVARCHAR(30), (@NowUtc  AT TIME ZONE 'UTC' AT TIME ZONE @DisplayTimeZone), 120);

    ------------------------------------------------------------------
    -- 3. Snapshot the window into a temp table (queried several times)
    ------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#win') IS NOT NULL DROP TABLE #win;

    SELECT
        a.AuditId,
        a.Direction,
        a.FlowName,
        a.FileName,
        a.SizeBytes,
        a.SourceHost,
        a.DestHost,
        a.Status,
        a.ErrorMessage,
        a.DurationMs,
        a.TransferStartUtc,
        a.TransferEndUtc,
        -- local time for display
        LocalStart = CONVERT(NVARCHAR(23),
                     (a.TransferStartUtc AT TIME ZONE 'UTC' AT TIME ZONE @DisplayTimeZone), 121)
    INTO #win
    FROM dbo.BlueYonderAptos_TransferAudit AS a
    WHERE a.TransferStartUtc >= @FromUtc
      AND a.TransferStartUtc <= @NowUtc;

    DECLARE @Total      INT = (SELECT COUNT(*) FROM #win);
    DECLARE @Success    INT = (SELECT COUNT(*) FROM #win WHERE Status = 'Success');
    DECLARE @Warning    INT = (SELECT COUNT(*) FROM #win WHERE Status = 'Warning');
    DECLARE @Failed     INT = (SELECT COUNT(*) FROM #win WHERE Status = 'Failed');
    DECLARE @Stranded   INT = (SELECT COUNT(*) FROM #win WHERE Status = 'Stranded');
    DECLARE @InProgress INT = (SELECT COUNT(*) FROM #win WHERE Status = 'InProgress');
    DECLARE @Problem    INT = @Failed + @Stranded + @InProgress;

    ------------------------------------------------------------------
    -- 4. Optionally skip sending when the window is empty
    ------------------------------------------------------------------
    IF @Total = 0 AND @SendIfEmpty = 0
    BEGIN
        IF @Debug = 1 PRINT 'No rows in window and @SendIfEmpty = 0; nothing sent.';
        RETURN;
    END

    ------------------------------------------------------------------
    -- 5. Build the HTML. Everything user/data-derived is HTML-encoded.
    ------------------------------------------------------------------
    DECLARE @CRLF CHAR(2) = CHAR(13) + CHAR(10);
    DECLARE @srv  NVARCHAR(256) = CONVERT(NVARCHAR(256), SERVERPROPERTY('MachineName'));

    -- Health banner colour: red if any problem, amber if only warnings, else green.
    DECLARE @bannerColor VARCHAR(7) =
        CASE WHEN @Problem > 0 THEN '#c0392b'
             WHEN @Warning > 0 THEN '#d68910'
             ELSE '#1e8449' END;
    DECLARE @bannerText NVARCHAR(100) =
        CASE WHEN @Problem > 0 THEN N'ATTENTION REQUIRED'
             WHEN @Warning > 0 THEN N'COMPLETED WITH WARNINGS'
             ELSE N'ALL TRANSFERS HEALTHY' END;

    DECLARE @style NVARCHAR(MAX) = N'
<style>
  body   { font-family:Segoe UI, Arial, sans-serif; color:#2c3e50; font-size:13px; }
  h2     { margin:0 0 4px 0; }
  .sub   { color:#7f8c8d; font-size:12px; margin-bottom:14px; }
  .banner{ color:#fff; padding:10px 14px; border-radius:4px; font-weight:bold;
           letter-spacing:.5px; margin-bottom:16px; }
  table  { border-collapse:collapse; width:100%; margin-bottom:18px; }
  th     { background:#34495e; color:#fff; text-align:left; padding:6px 8px; font-size:12px; }
  td     { border:1px solid #dcdde1; padding:5px 8px; font-size:12px; vertical-align:top; }
  tr:nth-child(even) td { background:#f7f9fa; }
  .cards td { text-align:center; font-size:12px; border:none; padding:0 6px; }
  .num   { font-size:22px; font-weight:bold; display:block; }
  .ok      { color:#1e8449; }
  .warn    { color:#d68910; }
  .bad     { color:#c0392b; }
  .st-Success  { color:#1e8449; font-weight:bold; }
  .st-Warning  { color:#d68910; font-weight:bold; }
  .st-Failed   { color:#c0392b; font-weight:bold; }
  .st-Stranded { color:#c0392b; font-weight:bold; }
  .st-InProgress { color:#8e44ad; font-weight:bold; }
  .foot  { color:#95a5a6; font-size:11px; margin-top:10px; }
</style>';

    DECLARE @html NVARCHAR(MAX) =
        N'<html><head>' + @style + N'</head><body>' +
        N'<h2>Blue Yonder &#8596; Aptos &ndash; File Transfer Audit Report</h2>' +
        N'<div class="sub">Window: last ' + CAST(@LookbackHours AS NVARCHAR(10)) + N' hour(s) &nbsp;|&nbsp; '
            + @FromLocal + N' to ' + @NowLocal + N' (' + @DisplayTimeZone + N')'
            + N' &nbsp;|&nbsp; Server: ' + @srv + N'</div>' +
        N'<div class="banner" style="background:' + @bannerColor + N';">' + @bannerText + N'</div>';

    -- Summary "cards" row
    SET @html = @html +
        N'<table class="cards"><tr>' +
        N'<td><span class="num">'      + CAST(@Total      AS NVARCHAR(10)) + N'</span>Total</td>' +
        N'<td><span class="num ok">'   + CAST(@Success    AS NVARCHAR(10)) + N'</span>Success</td>' +
        N'<td><span class="num warn">' + CAST(@Warning    AS NVARCHAR(10)) + N'</span>Warning</td>' +
        N'<td><span class="num bad">'  + CAST(@Failed     AS NVARCHAR(10)) + N'</span>Failed</td>' +
        N'<td><span class="num bad">'  + CAST(@Stranded   AS NVARCHAR(10)) + N'</span>Stranded</td>' +
        N'<td><span class="num">'      + CAST(@InProgress AS NVARCHAR(10)) + N'</span>In&nbsp;Progress</td>' +
        N'</tr></table>';

    -- Breakdown by direction + status
    DECLARE @byDir NVARCHAR(MAX) = N'';
    SELECT @byDir = @byDir +
        N'<tr><td>' + CASE Direction WHEN 'BY_TO_APTOS' THEN N'Blue Yonder &rarr; Aptos'
                                     WHEN 'APTOS_TO_BY' THEN N'Aptos &rarr; Blue Yonder'
                                     ELSE Direction END + N'</td>' +
        N'<td style="text-align:right">' + CAST(COUNT(*)                                        AS NVARCHAR(10)) + N'</td>' +
        N'<td style="text-align:right">' + CAST(SUM(CASE WHEN Status='Success'  THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>' +
        N'<td style="text-align:right">' + CAST(SUM(CASE WHEN Status='Warning'  THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>' +
        N'<td style="text-align:right">' + CAST(SUM(CASE WHEN Status='Failed'   THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td>' +
        N'<td style="text-align:right">' + CAST(SUM(CASE WHEN Status='Stranded' THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N'</td></tr>'
    FROM #win
    GROUP BY Direction;

    IF @byDir <> N''
        SET @html = @html +
            N'<table><tr><th>Direction</th><th style="text-align:right">Total</th>'
            + N'<th style="text-align:right">Success</th><th style="text-align:right">Warning</th>'
            + N'<th style="text-align:right">Failed</th><th style="text-align:right">Stranded</th></tr>'
            + @byDir + N'</table>';

    ------------------------------------------------------------------
    -- 6. Per-file detail (newest first), HTML-encoded, capped
    ------------------------------------------------------------------
    IF @IncludeDetail = 1 AND @Total > 0
    BEGIN
        DECLARE @rows NVARCHAR(MAX) = N'';

        ;WITH ranked AS
        (
            SELECT TOP (@MaxDetailRows)
                LocalStart, Direction, FlowName, FileName, SizeBytes,
                SourceHost, DestHost, Status, DurationMs, ErrorMessage
            FROM #win
            ORDER BY TransferStartUtc DESC
        )
        SELECT @rows = @rows +
            N'<tr>' +
            N'<td>' + LocalStart + N'</td>' +
            N'<td>' + CASE Direction WHEN 'BY_TO_APTOS' THEN N'BY &rarr; Aptos'
                                     WHEN 'APTOS_TO_BY' THEN N'Aptos &rarr; BY'
                                     ELSE (SELECT Direction FOR XML PATH(''), TYPE).value('.','nvarchar(max)') END + N'</td>' +
            N'<td>' + (SELECT FlowName  FOR XML PATH(''), TYPE).value('.','nvarchar(max)') + N'</td>' +
            N'<td>' + (SELECT FileName  FOR XML PATH(''), TYPE).value('.','nvarchar(max)') + N'</td>' +
            N'<td style="text-align:right">' + ISNULL(CONVERT(NVARCHAR(20), SizeBytes), N'') + N'</td>' +
            N'<td>' + (SELECT SourceHost FOR XML PATH(''), TYPE).value('.','nvarchar(max)') + N'</td>' +
            N'<td>' + (SELECT DestHost   FOR XML PATH(''), TYPE).value('.','nvarchar(max)') + N'</td>' +
            N'<td class="st-' + Status + N'">' + Status + N'</td>' +
            N'<td style="text-align:right">' + ISNULL(CONVERT(NVARCHAR(20), DurationMs), N'') + N'</td>' +
            N'<td>' + ISNULL((SELECT ErrorMessage FOR XML PATH(''), TYPE).value('.','nvarchar(max)'), N'') + N'</td>' +
            N'</tr>'
        FROM ranked;

        SET @html = @html +
            N'<table>' +
            N'<tr><th>Time (' + @DisplayTimeZone + N')</th><th>Direction</th><th>Flow</th><th>File</th>' +
            N'<th style="text-align:right">Bytes</th><th>Source</th><th>Dest</th><th>Status</th>' +
            N'<th style="text-align:right">ms</th><th>Error</th></tr>' +
            ISNULL(@rows, N'') + N'</table>';

        IF @Total > @MaxDetailRows
            SET @html = @html +
                N'<div class="sub">Showing newest ' + CAST(@MaxDetailRows AS NVARCHAR(10))
                + N' of ' + CAST(@Total AS NVARCHAR(10)) + N' file(s).</div>';
    END

    SET @html = @html +
        N'<div class="foot">Generated ' + @NowLocal + N' (' + @DisplayTimeZone
        + N') by dbo.usp_BlueYonderAptos_SendTransferReport. Source table: dbo.BlueYonderAptos_TransferAudit.</div>' +
        N'</body></html>';

    ------------------------------------------------------------------
    -- 7. Subject line (status-aware) and send
    ------------------------------------------------------------------
    DECLARE @subject NVARCHAR(255) =
        @SubjectPrefix + N' transfer report (last ' + CAST(@LookbackHours AS NVARCHAR(10)) + N'h): '
        + CAST(@Total AS NVARCHAR(10)) + N' file(s), '
        + CAST(@Success AS NVARCHAR(10)) + N' ok'
        + CASE WHEN @Problem > 0
               THEN N', ' + CAST(@Problem AS NVARCHAR(10)) + N' NEED ATTENTION'
               WHEN @Warning > 0
               THEN N', ' + CAST(@Warning AS NVARCHAR(10)) + N' warning(s)'
               ELSE N'' END;

    DECLARE @importance VARCHAR(6) = CASE WHEN @Problem > 0 THEN 'High' ELSE 'Normal' END;

    IF @Debug = 1
    BEGIN
        PRINT 'Subject: ' + @subject;
        PRINT 'Window (UTC): ' + CONVERT(NVARCHAR(30), @FromUtc, 120) + ' .. ' + CONVERT(NVARCHAR(30), @NowUtc, 120);
        -- HTML can exceed PRINT's 8000-char limit; emit in chunks.
        DECLARE @i INT = 1, @len INT = LEN(@html);
        WHILE @i <= @len
        BEGIN
            PRINT SUBSTRING(@html, @i, 8000);
            SET @i = @i + 8000;
        END
        RETURN;
    END

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name           = @ProfileName,     -- defaults to 'DBAAlert'
        @recipients             = @Recipients,
        @copy_recipients        = @CopyRecipients,
        @subject                = @subject,
        @body                   = @html,
        @body_format            = 'HTML',
        @importance             = @importance,
        @exclude_query_output   = 1;
END
GO

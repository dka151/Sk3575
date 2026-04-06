USE [AAD]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
================================================================================
  Stored Procedure : [dbo].[usp_notify_outbound_message_errors]
  Database         : AAD
  Author           : DBA Team
  Created          : 2026-04-06
  Description      : Sends an HTML-formatted email alert for any outbound
                     message log records with status = 'E' inserted within
                     the last 30 minutes. Uses Database Mail (sp_send_dbmail).

  Dependencies     : Database Mail must be configured and enabled.
                     A valid mail profile must exist.

  Parameters       :
    @MailProfileName   - Database Mail profile name (default: NULL = server default)
    @Recipients        - Semicolon-delimited recipient list (required)
    @CopyRecipients    - Optional CC list
    @LookbackMinutes   - Minutes to look back from GETDATE() (default: 30)
    @Debug             - 1 = print HTML and skip sending; 0 = send email

  Execution Example :
    EXEC [dbo].[usp_notify_outbound_message_errors]
        @Recipients = '[email];[email]',
        @LookbackMinutes = 30,
        @Debug = 0;

  Change History    :
    Date        Author      Description
    ----------  ----------  ---------------------------------------------------
    2026-04-06  DBA Team    Initial creation.
================================================================================
*/
CREATE OR ALTER PROCEDURE [dbo].[usp_notify_outbound_message_errors]
    @MailProfileName   NVARCHAR(128)  = NULL,
    @Recipients        NVARCHAR(MAX),
    @CopyRecipients    NVARCHAR(MAX)  = NULL,
    @LookbackMinutes   INT            = 30,
    @Debug             BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* -------------------------------------------------------------------
       Variable declarations
    ------------------------------------------------------------------- */
    DECLARE @ErrorCount     INT            = 0,
            @HtmlBody       NVARCHAR(MAX),
            @HtmlHeader     NVARCHAR(MAX),
            @HtmlRows       NVARCHAR(MAX),
            @HtmlFooter     NVARCHAR(MAX),
            @Subject        NVARCHAR(255),
            @CutoffTime     DATETIME,
            @ServerName     NVARCHAR(128)  = @@SERVERNAME,
            @DatabaseName   NVARCHAR(128)  = DB_NAME(),
            @ExecutionTime  DATETIME       = GETDATE(),
            @ReturnCode     INT            = 0;

    BEGIN TRY

        /* -------------------------------------------------------------------
           Input validation
        ------------------------------------------------------------------- */
        IF @Recipients IS NULL OR LTRIM(RTRIM(@Recipients)) = ''
        BEGIN
            RAISERROR('Parameter @Recipients is required and cannot be empty.', 16, 1);
            RETURN 1;
        END

        IF @LookbackMinutes < 1 OR @LookbackMinutes > 1440
        BEGIN
            RAISERROR('Parameter @LookbackMinutes must be between 1 and 1440.', 16, 1);
            RETURN 1;
        END

        /* -------------------------------------------------------------------
           Calculate the cutoff time
        ------------------------------------------------------------------- */
        SET @CutoffTime = DATEADD(MINUTE, -@LookbackMinutes, @ExecutionTime);

        /* -------------------------------------------------------------------
           Check for qualifying error records
        ------------------------------------------------------------------- */
        SELECT @ErrorCount = COUNT(*)
        FROM [dbo].[t_message_log_outbound] WITH (NOLOCK)
        WHERE [status] = N'E'
          AND [date_inserted] >= @CutoffTime;

        /* If no errors, exit gracefully */
        IF @ErrorCount = 0
        BEGIN
            IF @Debug = 1
                PRINT 'No error records found in the last '
                      + CAST(@LookbackMinutes AS VARCHAR(10))
                      + ' minutes. No email sent.';
            RETURN 0;
        END

        /* -------------------------------------------------------------------
           Build the email subject
        ------------------------------------------------------------------- */
        SET @Subject = N'ALERT: ' + CAST(@ErrorCount AS NVARCHAR(10))
                     + N' Outbound Message Error(s) on ['
                     + @ServerName + N'].['
                     + @DatabaseName + N'] - '
                     + CONVERT(NVARCHAR(20), @ExecutionTime, 120);

        /* -------------------------------------------------------------------
           Build HTML header with inline CSS
        ------------------------------------------------------------------- */
        SET @HtmlHeader = N'
<html>
<head>
<style>
    body   { font-family: Segoe UI, Arial, sans-serif; font-size: 12px; color: #333; }
    h2     { color: #c0392b; margin-bottom: 4px; }
    .meta  { font-size: 11px; color: #666; margin-bottom: 12px; }
    table  { border-collapse: collapse; width: 100%; font-size: 11px; }
    th     { background-color: #2c3e50; color: #fff; padding: 6px 8px;
             text-align: left; white-space: nowrap; }
    td     { padding: 5px 8px; border-bottom: 1px solid #ddd; vertical-align: top; }
    tr:nth-child(even) { background-color: #f9f9f9; }
    tr:hover           { background-color: #ffeaea; }
    .fail  { color: #c0392b; font-weight: bold; }
    .wrap  { max-width: 300px; word-wrap: break-word; overflow-wrap: break-word; }
</style>
</head>
<body>
<h2>Outbound Message Errors</h2>
<div class="meta">
    Server: <strong>' + @ServerName + N'</strong> &nbsp;|&nbsp;
    Database: <strong>' + @DatabaseName + N'</strong> &nbsp;|&nbsp;
    Lookback: <strong>' + CAST(@LookbackMinutes AS NVARCHAR(10)) + N' min</strong> &nbsp;|&nbsp;
    Error Count: <strong>' + CAST(@ErrorCount AS NVARCHAR(10)) + N'</strong> &nbsp;|&nbsp;
    Generated: <strong>' + CONVERT(NVARCHAR(20), @ExecutionTime, 120) + N'</strong>
</div>
<table>
<tr>
    <th>unique_id</th>
    <th>date_inserted</th>
    <th>status</th>
    <th>processing_start</th>
    <th>processing_end</th>
    <th>url</th>
    <th>http_headers</th>
    <th>time_out</th>
    <th>message_data</th>
    <th>results</th>
    <th>message_id</th>
    <th>message_type</th>
    <th>environment</th>
    <th>attempted_connections</th>
    <th>max_attempts</th>
    <th>server_response_time</th>
    <th>server_response_code</th>
    <th>wh_id</th>
    <th>failed</th>
</tr>';


        /* -------------------------------------------------------------------
           Build HTML table rows via FOR XML PATH
           Truncate large columns to keep email readable.
        ------------------------------------------------------------------- */
        SET @HtmlRows = (
            SELECT
                td_uid          = [unique_id],
                td_di           = CONVERT(VARCHAR(23), [date_inserted], 121),
                td_st           = [status],
                td_ps           = ISNULL(CONVERT(VARCHAR(23), [processing_start], 121), ''),
                td_pe           = ISNULL(CONVERT(VARCHAR(23), [processing_end], 121), ''),
                td_url          = ISNULL(LEFT([url], 300)
                                  + CASE WHEN LEN([url]) > 300 THEN N'...' ELSE N'' END, ''),
                td_hdr          = ISNULL(LEFT([http_headers], 200)
                                  + CASE WHEN LEN([http_headers]) > 200 THEN N'...' ELSE N'' END, ''),
                td_to           = [time_out],
                td_md           = ISNULL(LEFT([message_data], 300)
                                  + CASE WHEN LEN(CAST([message_data] AS NVARCHAR(MAX))) > 300
                                         THEN N'...' ELSE N'' END, ''),
                td_res          = ISNULL(LEFT(CAST([results] AS NVARCHAR(MAX)), 300)
                                  + CASE WHEN LEN(CAST([results] AS NVARCHAR(MAX))) > 300
                                         THEN N'...' ELSE N'' END, ''),
                td_mid          = ISNULL([message_id], ''),
                td_mt           = ISNULL([message_type], ''),
                td_env          = ISNULL([environment], ''),
                td_ac           = [attempted_connections],
                td_ma           = [max_attempts],
                td_srt          = ISNULL(CAST([server_response_time] AS NVARCHAR(10)), ''),
                td_src          = ISNULL([server_response_code], ''),
                td_wh           = [wh_id],
                td_fail         = CASE WHEN [failed] = 1 THEN 'YES' ELSE 'NO' END
            FROM [dbo].[t_message_log_outbound] WITH (NOLOCK)
            WHERE [status] = N'E'
              AND [date_inserted] >= @CutoffTime
            ORDER BY [date_inserted] DESC
            FOR XML RAW('row'), ELEMENTS
        );

        /* -------------------------------------------------------------------
           Transform the raw XML into proper HTML table rows
        ------------------------------------------------------------------- */
        IF @HtmlRows IS NOT NULL
        BEGIN
            -- Open each row
            SET @HtmlRows = REPLACE(@HtmlRows, N'<row>',  N'<tr>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</row>', N'</tr>');

            -- Map each element to <td>
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_uid>',  N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_uid>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_di>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_di>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_st>',   N'<td class="fail">');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_st>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_ps>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_ps>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_pe>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_pe>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_url>',  N'<td class="wrap">');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_url>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_hdr>',  N'<td class="wrap">');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_hdr>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_to>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_to>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_md>',   N'<td class="wrap">');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_md>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_res>',  N'<td class="wrap">');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_res>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_mid>',  N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_mid>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_mt>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_mt>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_env>',  N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_env>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_ac>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_ac>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_ma>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_ma>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_srt>',  N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_srt>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_src>',  N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_src>', N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_wh>',   N'<td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_wh>',  N'</td>');
            SET @HtmlRows = REPLACE(@HtmlRows, N'<td_fail>', N'<td class="fail">');
            SET @HtmlRows = REPLACE(@HtmlRows, N'</td_fail>', N'</td>');
        END
        ELSE
        BEGIN
            SET @HtmlRows = N'<tr><td colspan="19" style="text-align:center;">No records found.</td></tr>';
        END

        /* -------------------------------------------------------------------
           Build HTML footer
        ------------------------------------------------------------------- */
        SET @HtmlFooter = N'
</table>
<br/>
<div class="meta">
    This is an automated alert generated by [dbo].[usp_notify_outbound_message_errors]
    on ' + @ServerName + N'. Do not reply to this email.
</div>
</body>
</html>';

        /* -------------------------------------------------------------------
           Assemble the full HTML body
        ------------------------------------------------------------------- */
        SET @HtmlBody = @HtmlHeader + @HtmlRows + @HtmlFooter;

        /* -------------------------------------------------------------------
           Debug mode: print and exit
        ------------------------------------------------------------------- */
        IF @Debug = 1
        BEGIN
            PRINT '--- Subject ---';
            PRINT @Subject;
            PRINT '--- HTML Body (first 4000 chars) ---';
            PRINT LEFT(@HtmlBody, 4000);
            RETURN 0;
        END

        /* -------------------------------------------------------------------
           Send the email via Database Mail
        ------------------------------------------------------------------- */
        EXEC @ReturnCode = msdb.dbo.sp_send_dbmail
            @profile_name    = @MailProfileName,
            @recipients      = @Recipients,
            @copy_recipients = @CopyRecipients,
            @subject         = @Subject,
            @body            = @HtmlBody,
            @body_format     = 'HTML',
            @importance      = 'High';

        IF @ReturnCode <> 0
        BEGIN
            RAISERROR('sp_send_dbmail returned error code %d.', 16, 1, @ReturnCode);
            RETURN 1;
        END

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage  NVARCHAR(4000) = ERROR_MESSAGE(),
                @ErrorSeverity INT            = ERROR_SEVERITY(),
                @ErrorState    INT            = ERROR_STATE(),
                @ErrorLine     INT            = ERROR_LINE();

        /* Re-raise so callers and SQL Agent can detect the failure */
        RAISERROR(
            'usp_notify_outbound_message_errors failed at line %d: %s',
            @ErrorSeverity,
            @ErrorState,
            @ErrorLine,
            @ErrorMessage
        );

        RETURN 1;
    END CATCH

    RETURN 0;
END
GO

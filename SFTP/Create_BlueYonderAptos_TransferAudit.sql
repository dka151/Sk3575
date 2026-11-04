/*
    dbo.BlueYonderAptos_TransferAudit
    One row per file per transfer attempt between Blue Yonder and Aptos,
    written by Sync-BlueYonder-Aptos.ps1.
    The script inserts the row as 'InProgress' BEFORE moving the file, then
    updates it to Success / Failed / Warning.

    Status values:
      InProgress - row written, transfer underway (stays this way only if the
                   run crashed mid-file -- investigate these)
      Success    - delivered and verified on destination
      Warning    - delivered, but source delete failed (-DeleteSourceAfter);
                   the file may be re-sent on the next run
      Failed     - failed BEFORE the source was claimed (download/claim step);
                   source file is untouched and the next run retries it
      Stranded   - source was claimed (renamed to .RN) but delivery did not
                   complete. The .RN is deliberately KEPT on the source (no
                   rollback) so the file is never pushed twice. It will NOT be
                   retried automatically: review the destination, then reprocess
                   manually. Alert on this status.

    Child table dbo.BlueYonderAptos_TransferAuditStepDetail holds one row per
    step (download, claim, rename, upload, ...) for each file.

    Grant the service account INSERT, UPDATE and SELECT on both tables.
*/
IF OBJECT_ID('dbo.BlueYonderAptos_TransferAudit', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BlueYonderAptos_TransferAudit
    (
        AuditId           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BlueYonderAptos_TransferAudit PRIMARY KEY,
        RunId             UNIQUEIDENTIFIER     NOT NULL,
        Direction         VARCHAR(20)          NOT NULL,   -- BY_TO_APTOS | APTOS_TO_BY
        FlowName          NVARCHAR(100)        NOT NULL,
        FileName          NVARCHAR(260)        NOT NULL,
        SizeBytes         BIGINT               NULL,
        SourceHost        NVARCHAR(255)        NOT NULL,
        SourcePath        NVARCHAR(500)        NOT NULL,
        DestHost          NVARCHAR(255)        NOT NULL,
        DestPath          NVARCHAR(500)        NOT NULL,
        Status            VARCHAR(20)          NOT NULL,
        ErrorMessage      NVARCHAR(MAX)        NULL,
        TransferStartUtc  DATETIME2(3)         NOT NULL,
        TransferEndUtc    DATETIME2(3)         NULL,
        DurationMs        INT                  NULL,
        RunHost           NVARCHAR(128)        NULL,
        RunUser           NVARCHAR(256)        NULL,
        CONSTRAINT CK_BlueYonderAptos_TransferAudit_Direction CHECK (Direction IN ('BY_TO_APTOS', 'APTOS_TO_BY')),
        CONSTRAINT CK_BlueYonderAptos_TransferAudit_Status    CHECK (Status IN ('InProgress', 'Success', 'Warning', 'Failed', 'Stranded'))
    );

    CREATE INDEX IX_BlueYonderAptos_TransferAudit_Start  ON dbo.BlueYonderAptos_TransferAudit (TransferStartUtc DESC)
        INCLUDE (Direction, Status, FileName);
    CREATE INDEX IX_BlueYonderAptos_TransferAudit_Status ON dbo.BlueYonderAptos_TransferAudit (Status, TransferStartUtc DESC);
    CREATE INDEX IX_BlueYonderAptos_TransferAudit_Run    ON dbo.BlueYonderAptos_TransferAudit (RunId);
END
GO

/*
    dbo.BlueYonderAptos_TransferAuditStepDetail
    One row per step per file, linked to dbo.BlueYonderAptos_TransferAudit.
    Written step by step so the trail shows exactly where a file stopped.

    StepName values (in order):
      DownloadToLocalTmp      source  -> local   <file>.TMP
      ClaimSourceRN           source: <file> -> <file>.RN
      RenameLocalTmpToFinal   local:  <file>.TMP -> <file>
      UploadToRemoteTmp       local   -> dest    <file>.TMP
      RenameRemoteTmpToFinal  dest:   <file>.TMP -> <file>
      VerifyDestination       dest:   final file exists
      DeleteSourceRN          source: delete <file>.RN (only with -DeleteSourceAfter;
                              recorded as Skipped when the .RN is kept)
    There is no rollback step: the .RN is never renamed back.

    Status values: InProgress | Success | Failed | Skipped
*/
IF OBJECT_ID('dbo.BlueYonderAptos_TransferAuditStepDetail', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BlueYonderAptos_TransferAuditStepDetail
    (
        StepId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BlueYonderAptos_TransferAuditStepDetail PRIMARY KEY,
        AuditId       BIGINT               NOT NULL,
        StepNo        TINYINT              NOT NULL,
        StepName      VARCHAR(40)          NOT NULL,
        Host          NVARCHAR(255)        NULL,       -- server (or staging host) where the step ran
        FromPath      NVARCHAR(500)        NULL,
        ToPath        NVARCHAR(500)        NULL,
        Status        VARCHAR(12)          NOT NULL,
        ErrorMessage  NVARCHAR(MAX)        NULL,
        StepStartUtc  DATETIME2(3)         NOT NULL,
        StepEndUtc    DATETIME2(3)         NULL,
        DurationMs    INT                  NULL,
        CONSTRAINT FK_BlueYonderAptos_TransferAuditStepDetail_Audit
            FOREIGN KEY (AuditId) REFERENCES dbo.BlueYonderAptos_TransferAudit (AuditId),
        CONSTRAINT CK_BlueYonderAptos_TransferAuditStepDetail_Status
            CHECK (Status IN ('InProgress', 'Success', 'Failed', 'Skipped')),
        CONSTRAINT CK_BlueYonderAptos_TransferAuditStepDetail_StepName
            CHECK (StepName IN ('DownloadToLocalTmp', 'ClaimSourceRN', 'RenameLocalTmpToFinal',
                                'UploadToRemoteTmp', 'RenameRemoteTmpToFinal', 'VerifyDestination',
                                'DeleteSourceRN'))
    );

    CREATE INDEX IX_BlueYonderAptos_TransferAuditStepDetail_Audit
        ON dbo.BlueYonderAptos_TransferAuditStepDetail (AuditId, StepNo);
    CREATE INDEX IX_BlueYonderAptos_TransferAuditStepDetail_Failed
        ON dbo.BlueYonderAptos_TransferAuditStepDetail (Status, StepStartUtc DESC)
        WHERE Status = 'Failed';
END
GO

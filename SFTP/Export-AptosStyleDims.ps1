<#
.SYNOPSIS
    Runs dbo.usp_Aptos_StyleDims_Export on AZUSW1APSQL03, builds the Aptos
    style dims import CSV, and uploads it to the Aptos SFTP folder via WinSCP.

.OUTPUT FORMAT (mirrors Aptos_styledims_20261028_v6.csv)
    Style,Action,EntityAction,Code,Weight,Height,Width,Depth
    Style,update,,DQ8423-406,1.35,3.9,8,10.4
    - CRLF line endings, UTF-8 without BOM
    - Numbers use '.' and have trailing zeros dropped (8.00 -> 8, 3.90 -> 3.9)
    - Fields are only quoted if they contain a comma or quote

.DELTA LOGIC
    Only new codes, or codes whose Weight/Height/Width/Depth changed since the last
    successful delivery, are exported. State lives in DBA.dbo.Aptos_StyleDims_Sent
    and is updated by dbo.usp_Aptos_StyleDims_Commit AFTER the upload succeeds.
    First run (empty Sent table) sends everything. Use -FullExport $true to re-seed.
    Deploy usp_Aptos_StyleDims_Export_Delta.sql before running.

.IMPORTANT - SFTP CREDENTIALS (DPAPI)
    The SFTP user/password are read from a DPAPI-encrypted file (-CredFile) that
    can only be decrypted by the same Windows account on the same server.
    Create it ONCE, logged on as the account that runs the SQL Agent step:
        .\New-AptosSftpCredential.ps1
    The password is passed to WinSCP through a temporary script file (not the
    command line) which is deleted right after the upload.

.NOTES
    Called by SQL Agent job "Aptos - Style Dims Export (PROD)" (CmdExec step).
    Exits 0 on success, 1 on failure.
#>
param(
    [string]$SqlServer       = 'AZUSW1APSQL03',
    [string]$Database        = 'DBA',
    [string]$WhId            = '282999',
    [string]$RemoteDir       = '/Transfer/IN/MERCH/Style',
    [string]$WinScpPath      = 'C:\Program Files (x86)\WinSCP\winscp.com',
    [string]$SftpHost        = '10.252.17.100',   # Aptos SFTP host
    [int]$SftpPort           = 22,
    [string]$CredFile        = 'D:\Jobs\AptosStyleDims\Secrets\aptos_sftp.cred',
    [string]$HostKey         = 'ssh-rsa 2048 lp0au9aqsK5yF2hlSef33/6PWNOKEzxxSUuNlN46OJk',  # server host key fingerprint (SHA-256)
    [string]$BaseDir         = 'D:\Jobs\AptosStyleDims',
    [string]$FilePrefix      = 'Aptos_styledims',
    [string]$DateFormat      = 'yyyyMMdd_HHmmss',        # 'yyyyMMdd' for one file per day
    [bool]$SkipEmptyFile     = $true,
    [bool]$FullExport        = $false,                   # $true = ignore history, send every code (re-seed)
    [int]$QueryTimeoutSec    = 1800,
    [int]$UploadRetries      = 3,
    [int]$RetainDays         = 30
)

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

$archiveDir = Join-Path $BaseDir 'Archive'
$logDir     = Join-Path $BaseDir 'Logs'
$workDir    = Join-Path $BaseDir 'Work'
$fileName   = "{0}_{1}.csv" -f $FilePrefix, (Get-Date -Format $DateFormat)
$workFile   = Join-Path $workDir $fileName
$logFile    = Join-Path $logDir ("{0}_{1}.log" -f $FilePrefix, (Get-Date -Format 'yyyyMMdd'))

foreach ($d in $archiveDir, $logDir, $workDir) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Write-Log([string]$msg, [string]$level = 'INFO') {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
    Add-Content -Path $logFile -Value $line
    Write-Host $line   # also shows in SQL Agent step history
}

function ConvertTo-CsvField($value) {
    if ($null -eq $value -or $value -is [System.DBNull]) { return '' }
    if ($value -is [decimal] -or $value -is [double] -or $value -is [single]) {
        $s = ([decimal]$value).ToString('0.##', $inv)      # 8.00 -> 8, 3.90 -> 3.9
    } else {
        $s = [System.Convert]::ToString($value, $inv)
    }
    if ($s -match '[,"\r\n]') { return '"' + $s.Replace('"', '""') + '"' }
    return $s
}

try {
    Write-Log "Start. Server=$SqlServer DB=$Database WhId=$WhId Remote=$RemoteDir FullExport=$FullExport"

    # ---- 1. Run extract ---------------------------------------------------
    $connStr = "Server=$SqlServer;Database=$Database;Integrated Security=SSPI;Application Name=AptosStyleDimsExport"
    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    $cmd  = $conn.CreateCommand()
    $cmd.CommandType    = [System.Data.CommandType]::StoredProcedure
    $cmd.CommandText    = 'dbo.usp_Aptos_StyleDims_Export'
    $cmd.CommandTimeout = $QueryTimeoutSec
    [void]$cmd.Parameters.AddWithValue('@WhId', $WhId)
    [void]$cmd.Parameters.AddWithValue('@FullExport', [bool]$FullExport)
    $pBatch = $cmd.Parameters.Add('@BatchId', [System.Data.SqlDbType]::UniqueIdentifier)
    $pBatch.Direction = [System.Data.ParameterDirection]::Output
    $table   = New-Object System.Data.DataTable
    $batchId = $null
    try {
        $conn.Open()
        $reader = $cmd.ExecuteReader()
        try { $table.Load($reader) } finally { $reader.Dispose() }
        # OUTPUT parameters are only available after the reader is closed
        if ($pBatch.Value -isnot [System.DBNull]) { $batchId = [guid]$pBatch.Value }
    } finally {
        $cmd.Dispose()
        $conn.Dispose()
    }
    Write-Log ("Rows returned (new/changed): {0}  BatchId={1}" -f $table.Rows.Count, $batchId)

    if ($table.Rows.Count -eq 0 -and $SkipEmptyFile) {
        Write-Log 'No new or changed styles - no file created.'
        exit 0
    }

    # ---- 2. Build CSV (header = proc column names, CRLF, UTF-8 no BOM) ---
    $sb = New-Object System.Text.StringBuilder
    $header = ($table.Columns | ForEach-Object { $_.ColumnName }) -join ','
    [void]$sb.Append($header).Append("`r`n")
    foreach ($row in $table.Rows) {
        $fields = for ($i = 0; $i -lt $table.Columns.Count; $i++) { ConvertTo-CsvField $row[$i] }
        [void]$sb.Append(($fields -join ',')).Append("`r`n")
    }
    [System.IO.File]::WriteAllText($workFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Log "CSV built: $workFile"

    # ---- 3. Upload via WinSCP (upload as .tmp, then rename) ---------------
    if (-not (Test-Path -LiteralPath $WinScpPath)) { throw "WinSCP not found: $WinScpPath" }

    $remoteDirClean = $RemoteDir.TrimEnd('/')
    $remoteTmp      = "$remoteDirClean/$fileName.tmp"
    $remoteFinal    = "$remoteDirClean/$fileName"
    $winscpLog      = Join-Path $logDir ("winscp_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

    if (-not (Test-Path -LiteralPath $CredFile)) {
        throw "Credential file not found: $CredFile (run New-AptosSftpCredential.ps1 as the job account)"
    }
    if ($SftpHost -like 'REPLACE_*') { throw 'Set -SftpHost to the Aptos SFTP host name.' }

    # Decrypts only for the same Windows user on the same machine (DPAPI)
    $cred   = Import-Clixml -LiteralPath $CredFile
    $urlUsr = [System.Uri]::EscapeDataString($cred.UserName)
    $urlPwd = [System.Uri]::EscapeDataString($cred.GetNetworkCredential().Password)

    $openCmd = "open sftp://${urlUsr}:${urlPwd}@${SftpHost}:${SftpPort}/"
    if ($HostKey) { $openCmd += " -hostkey=`"$HostKey`"" }

    $scriptFile = Join-Path $workDir ("winscp_{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    $scriptText = @(
        'option batch abort'
        'option confirm off'
        $openCmd
        "put -transfer=binary -nopreservetime -resume=off `"$workFile`" `"$remoteTmp`""
        "mv `"$remoteTmp`" `"$remoteFinal`""
        'exit'
    ) -join "`r`n"

    try {
        [System.IO.File]::WriteAllText($scriptFile, $scriptText, (New-Object System.Text.UTF8Encoding($false)))

        $attempt = 0
        while ($true) {
            $attempt++
            $out = & $WinScpPath "/script=$scriptFile" "/log=$winscpLog" 2>&1
            $rc  = $LASTEXITCODE
            if ($rc -eq 0) { break }
            Write-Log ("WinSCP exit code {0}: {1}" -f $rc, (($out | Out-String).Trim())) 'WARN'
            if ($attempt -ge $UploadRetries) { throw "WinSCP upload failed after $attempt attempts (last exit code $rc)" }
            Write-Log "Upload attempt $attempt failed. Retrying in 30s." 'WARN'
            Start-Sleep -Seconds 30
        }
    } finally {
        if (Test-Path -LiteralPath $scriptFile) { Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue }
        $urlPwd = $null; $scriptText = $null; $openCmd = $null
    }
    Write-Log "File delivered: $remoteFinal"

    # ---- 3b. Mark the delta as sent (only after successful delivery) ------
    if ($batchId) {
        $conn2 = New-Object System.Data.SqlClient.SqlConnection $connStr
        $cmd2  = $conn2.CreateCommand()
        try {
            $cmd2.CommandType    = [System.Data.CommandType]::StoredProcedure
            $cmd2.CommandText    = 'dbo.usp_Aptos_StyleDims_Commit'
            $cmd2.CommandTimeout = 300
            $p = $cmd2.Parameters.Add('@BatchId', [System.Data.SqlDbType]::UniqueIdentifier)
            $p.Value = $batchId
            $conn2.Open()
            [void]$cmd2.ExecuteNonQuery()
            Write-Log "Delta committed (BatchId=$batchId)."
        } catch {
            throw "File was delivered but commit failed: $($_.Exception.Message). The same rows will be re-sent on the next run."
        } finally {
            $cmd2.Dispose()
            $conn2.Dispose()
        }
    }

    # ---- 4. Archive + housekeeping ---------------------------------------
    Move-Item -LiteralPath $workFile -Destination (Join-Path $archiveDir $fileName) -Force
    $cutoff = (Get-Date).AddDays(-$RetainDays)
    Get-ChildItem $archiveDir, $logDir -File |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Log 'Completed successfully.'
    exit 0
}
catch {
    Write-Log ("FAILED: {0}" -f $_.Exception.Message) 'ERROR'
    exit 1
}

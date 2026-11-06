<#
.SYNOPSIS
    Runs dbo.usp_Aptos_StyleDims_Export on AZUSW1APSQL03QA, builds the Aptos
    style dims import CSV, and uploads it to the Aptos SFTP folder via WinSCP.

.OUTPUT FORMAT (mirrors Aptos_styledims_20261028_v6.csv)
    Style,Action,EntityAction,Code,Weight,Height,Width,Depth
    Style,update,,DQ8423-406,1.35,3.9,8,10.4
    - CRLF line endings, UTF-8 without BOM
    - Numbers use '.' and have trailing zeros dropped (8.00 -> 8, 3.90 -> 3.9)
    - Fields are only quoted if they contain a comma or quote

.IMPORTANT - WINSCP SESSION
    The upload uses a WinSCP *saved session* (-WinScpSession) so no password or
    key is on the command line. Create it once on the server AS THE ACCOUNT THAT
    RUNS THE SQL AGENT STEP (or its proxy), including host, user, auth/key and
    host key fingerprint. WinSCP stores sessions per Windows user (registry) or
    in an INI file; use -WinScpIni if you use an INI.

.NOTES
    Called by SQL Agent job "Aptos - Style Dims Export (QA)" (CmdExec step).
    Exits 0 on success, 1 on failure.
#>
param(
    [string]$SqlServer       = 'AZUSW1APSQL03QA',
    [string]$Database        = 'DBA',
    [string]$WhId            = '282999',
    [string]$RemoteDir       = '/Transfer/IN/MERCH/Style',
    [string]$WinScpPath      = 'C:\Program Files (x86)\WinSCP\winscp.com',
    [string]$WinScpSession   = 'Aptos-SFTP',            # <<< saved WinSCP session name
    [string]$WinScpIni       = '',                       # optional: path to WinSCP.ini
    [string]$HostKey         = 'ssh-rsa 2048 lp0au9aqsK5yF2hlSef33/6PWNOKEzxxSUuNlN46OJk',  # server host key fingerprint (SHA-256)
    [string]$BaseDir         = 'D:\Jobs\AptosStyleDims',
    [string]$FilePrefix      = 'Aptos_styledims',
    [string]$DateFormat      = 'yyyyMMdd_HHmmss',        # 'yyyyMMdd' for one file per day
    [bool]$SkipEmptyFile     = $true,
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
    Write-Log "Start. Server=$SqlServer DB=$Database WhId=$WhId Remote=$RemoteDir Session=$WinScpSession"

    # ---- 1. Run extract ---------------------------------------------------
    $connStr = "Server=$SqlServer;Database=$Database;Integrated Security=SSPI;Application Name=AptosStyleDimsExport"
    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    $cmd  = $conn.CreateCommand()
    $cmd.CommandType    = [System.Data.CommandType]::StoredProcedure
    $cmd.CommandText    = 'dbo.usp_Aptos_StyleDims_Export'
    $cmd.CommandTimeout = $QueryTimeoutSec
    [void]$cmd.Parameters.AddWithValue('@WhId', $WhId)
    $table = New-Object System.Data.DataTable
    try {
        $conn.Open()
        $reader = $cmd.ExecuteReader()
        try { $table.Load($reader) } finally { $reader.Dispose() }
    } finally {
        $cmd.Dispose()
        $conn.Dispose()
    }
    Write-Log ("Rows returned: {0}" -f $table.Rows.Count)

    if ($table.Rows.Count -eq 0 -and $SkipEmptyFile) {
        Write-Log 'No rows - no file created.' 'WARN'
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

    $winscpArgs = @()
    if ($WinScpIni) { $winscpArgs += "/ini=`"$WinScpIni`"" }
    $winscpArgs += '/log="' + $winscpLog + '"'
    $winscpArgs += '/command'
    $winscpArgs += 'option batch abort'
    $winscpArgs += 'option confirm off'
    $openCmd = "open `"$WinScpSession`""
    if ($HostKey) { $openCmd += " -hostkey=`"$HostKey`"" }
    $winscpArgs += $openCmd
    $winscpArgs += "put -transfer=binary -nopreservetime -resume=off `"$workFile`" `"$remoteTmp`""
    $winscpArgs += "mv `"$remoteTmp`" `"$remoteFinal`""
    $winscpArgs += 'exit'

    $attempt = 0
    while ($true) {
        $attempt++
        $out = & $WinScpPath @winscpArgs 2>&1
        $rc  = $LASTEXITCODE
        if ($rc -eq 0) { break }
        Write-Log ("WinSCP exit code {0}: {1}" -f $rc, (($out | Out-String).Trim())) 'WARN'
        if ($attempt -ge $UploadRetries) { throw "WinSCP upload failed after $attempt attempts (last exit code $rc)" }
        Write-Log "Upload attempt $attempt failed. Retrying in 30s." 'WARN'
        Start-Sleep -Seconds 30
    }
    Write-Log "File delivered: $remoteFinal"

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

<#
.SYNOPSIS
    Runs dbo.usp_Aptos_StyleDims_Export on AZUSW1APSQL03QA and writes the
    Aptos style dims import CSV to the "Aptos Prod Dims" folder (H:).

.OUTPUT FORMAT (mirrors Aptos_styledims_20261028_v6.csv)
    Style,Action,EntityAction,Code,Weight,Height,Width,Depth
    Style,update,,DQ8423-406,1.35,3.9,8,10.4
    - CRLF line endings, UTF-8 without BOM
    - Numbers use '.' and have trailing zeros dropped (8.00 -> 8, 3.90 -> 3.9)
    - Fields are only quoted if they contain a comma or quote

.IMPORTANT - H: DRIVE
    SQL Agent runs as a service and does NOT see mapped drive letters like H:.
    Set -TargetDir to the UNC path that H: maps to (run "net use" on the
    server to find it), e.g. \\fileserver\share\Aptos Prod Dims.
    If H: is a local disk on the server, 'H:\Aptos Prod Dims' works as-is.

.NOTES
    Called by SQL Agent job "Aptos - Style Dims Export (QA)" (CmdExec step).
    Exits 0 on success, 1 on failure.
#>
param(
    [string]$SqlServer       = 'AZUSW1APSQL03QA',
    [string]$Database        = 'DBA',   # <<< same DB as the stored procedure
    [string]$WhId            = '282999',
    [string]$TargetDir       = '/Transfer/IN/MERCH/Style',   # <<< replace with UNC path if H: is mapped
    [string]$BaseDir         = 'D:\Jobs\AptosStyleDims',
    [string]$FilePrefix      = 'Aptos_styledims',
    [string]$DateFormat      = 'yyyyMMdd_HHmmss',      # 'yyyyMMdd' for one file per day
    [switch]$SkipEmptyFile   = $true,
    [int]$QueryTimeoutSec    = 1800,
    [int]$CopyRetries        = 3,
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
    Write-Output $line   # also shows in SQL Agent step history
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
    Write-Log "Start. Server=$SqlServer DB=$Database WhId=$WhId Target=$TargetDir"

    # ---- 1. Run extract ---------------------------------------------------
    $connStr = "Server=$SqlServer;Database=$Database;Integrated Security=SSPI;Application Name=AptosStyleDimsExport"
    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    $cmd  = $conn.CreateCommand()
    $cmd.CommandType    = [System.Data.CommandType]::StoredProcedure
    $cmd.CommandText    = 'dbo.usp_Aptos_StyleDims_Export'
    $cmd.CommandTimeout = $QueryTimeoutSec
    [void]$cmd.Parameters.AddWithValue('@WhId', $WhId)

    $table = New-Object System.Data.DataTable
    $conn.Open()
    try { $table.Load($cmd.ExecuteReader()) } finally { $conn.Close() }
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

    # ---- 3. Deliver to Aptos Prod Dims folder (tmp + rename) --------------
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        throw "Target folder not reachable: $TargetDir (if H: is a mapped drive, use its UNC path)"
    }
    $tmpTarget   = Join-Path $TargetDir ($fileName + '.tmp')
    $finalTarget = Join-Path $TargetDir $fileName

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Copy-Item -LiteralPath $workFile -Destination $tmpTarget -Force
            if (Test-Path -LiteralPath $finalTarget) { Remove-Item -LiteralPath $finalTarget -Force }
            Rename-Item -LiteralPath $tmpTarget -NewName $fileName -Force
            break
        } catch {
            if (Test-Path -LiteralPath $tmpTarget) { Remove-Item -LiteralPath $tmpTarget -Force -ErrorAction SilentlyContinue }
            if ($attempt -ge $CopyRetries) { throw }
            Write-Log "Copy attempt $attempt failed: $($_.Exception.Message). Retrying in 30s." 'WARN'
            Start-Sleep -Seconds 30
        }
    }
    Write-Log "File delivered: $finalTarget"

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

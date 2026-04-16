<#
.SYNOPSIS
    Copy test.csv from file share to SharePoint Online (non-interactive).

.NOTES
    Prerequisites:
    - PnP.PowerShell module: Install-Module PnP.PowerShell
    - Permissions on the SharePoint site
    - Network access to \\fileserver\shares\DBA
    - Account must NOT have MFA enabled
    - Tenant must allow legacy/basic authentication
#>

param(
    [Parameter(Mandatory)]
    [string]$Username,       # e.g. DOMAIN\username

    [Parameter(Mandatory)]
    [string]$Password,

    [Parameter(Mandatory)]
    [string]$FileName        # e.g. test.csv
)

# ── Configuration ─────────────────────────────────────────────────────────────
$SourceFile     = "\\fileserver\shares\DBA\$FileName"
$SharePointSite = "https://footlocker.sharepoint.com/sites/MerchandisingDepartment"
$TargetFolder   = "Shared Documents/Planning/Data Connections"

# ── Validate source file exists ───────────────────────────────────────────────
if (-not (Test-Path $SourceFile)) {
    Write-Error "Source file not found: $SourceFile"
    exit 1
}

Write-Host "Source file found: $SourceFile"

# ── Build credential object ───────────────────────────────────────────────────
$secPassword = ConvertTo-SecureString $Password -AsPlainText -Force
$credential  = New-Object System.Management.Automation.PSCredential($Username, $secPassword)

# ── Connect to SharePoint Online ──────────────────────────────────────────────
try {
    Connect-PnPOnline -Url $SharePointSite -Credentials $credential
    Write-Host "Connected to SharePoint: $SharePointSite"
}
catch {
    Write-Error "Failed to connect to SharePoint: $_"
    exit 1
}

# ── Upload the file ───────────────────────────────────────────────────────────
try {
    Add-PnPFile -Path $SourceFile -Folder $TargetFolder -ErrorAction Stop
    Write-Host "Successfully uploaded 'test.csv' to $SharePointSite/$TargetFolder"
}
catch {
    Write-Error "Failed to upload file: $_"
    exit 1
}
finally {
    Disconnect-PnPOnline -ErrorAction SilentlyContinue
}

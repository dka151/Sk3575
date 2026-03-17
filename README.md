# SFTP CLR Upload Solution for SSRS

This solution enables SSRS reports to upload files to SFTP servers using SQL CLR.

## Files Created

1. **SFTPUploader.cs** - C# code for SFTP functionality
2. **SFTPUploader.csproj** - Project file for building
3. **Build.bat** - Script to compile the assembly
4. **Deploy_CLR.sql** - SQL script to deploy to SQL Server
5. **README.md** - This file

## Prerequisites

- .NET Framework 4.8 SDK installed
- SQL Server with CLR enabled
- SQL Server sysadmin permissions
- Visual Studio or .NET CLI tools

## Installation Steps

### Step 1: Build the CLR Assembly

Run the build script:
```cmd
cd C:\GITLAB_Clone_Repos\SFTP_CLR
Build.bat
```

This will:
- Restore NuGet packages (SSH.NET library)
- Compile the C# code
- Create DLL files in `bin\Debug\net48\` folder

### Step 2: Verify Build Output

Check that these files exist:
- `C:\GITLAB_Clone_Repos\SFTP_CLR\bin\Debug\net48\SFTPUploader.dll`
- `C:\GITLAB_Clone_Repos\SFTP_CLR\bin\Debug\net48\Renci.SshNet.dll`

### Step 3: Deploy to SQL Server

1. Open `Deploy_CLR.sql` in SQL Server Management Studio (SSMS)
2. **IMPORTANT**: Change `[YourDatabaseName]` to your actual database name (appears 2 times)
3. Verify the file paths in the script match your build output location
4. Execute the script

The script will:
- Enable CLR integration
- Set database to TRUSTWORTHY
- Register SSH.NET assembly
- Register SFTPUploader assembly
- Create `dbo.UploadToSFTP` stored procedure

### Step 4: Test the Stored Procedure

```sql
-- Create a test file first
EXEC xp_cmdshell 'echo Test content > C:\Reports\test.txt';

-- Test the upload
EXEC dbo.UploadToSFTP 
    @host = 'wssftp.files.com',
    @port = 22,
    @username = 'hilco_sftp',
    @password = 'R7$kT9!vL2@pQ4zM',
    @localFilePath = 'C:\Reports\test.txt',
    @remoteFilePath = '/Hilco Global/test.txt';
```

### Step 5: Configure SSRS Report

The RDL file `SO_058_WSS_MerchHierarchyHilco_20260316.rdl` is already configured with:
- SFTP parameters (host, port, username, password, file paths)
- Dataset that calls `dbo.UploadToSFTP`
- Status textbox to show upload results

To use:
1. Deploy the updated RDL to SSRS
2. Run the report
3. Set `EnableSFTPUpload` parameter to `True`
4. Verify the file uploads to SFTP

## SFTP Configuration

Current settings in RDL:
- **Host**: wssftp.files.com
- **Port**: 22
- **Username**: hilco_sftp
- **Password**: R7$kT9!vL2@pQ4zM
- **Remote Path**: /Hilco Global/MerchHierarchyHilco.csv

## Troubleshooting

### Build Errors

**Error**: "dotnet command not found"
- Install .NET SDK from https://dotnet.microsoft.com/download

**Error**: "Could not restore packages"
- Check internet connection
- Run: `dotnet nuget locals all --clear`

### SQL Deployment Errors

**Error**: "CLR is not enabled"
- Run: `EXEC sp_configure 'clr enabled', 1; RECONFIGURE;`

**Error**: "Assembly with same name already exists"
- Drop existing assemblies first (script handles this)

**Error**: "PERMISSION_SET = UNSAFE failed"
- Database must be set to TRUSTWORTHY
- User must have UNSAFE ASSEMBLY permission

**Error**: "Could not load file or assembly"
- Verify DLL paths in Deploy_CLR.sql are correct
- Ensure SQL Server service account has read access to DLL files

### Runtime Errors

**Error**: "Local file does not exist"
- Ensure the report exports to the LocalFilePath location first
- SQL Server service account needs read access to the file

**Error**: "Connection failed"
- Verify SFTP credentials
- Check firewall allows outbound port 22
- Test SFTP connection with WinSCP or FileZilla first

**Error**: "Permission denied"
- Verify remote path exists
- Check SFTP user has write permissions to destination folder

## Security Considerations

1. **Password in RDL**: The password is stored in plain text in the RDL file. Consider:
   - Using encrypted parameters
   - Storing credentials in a secure configuration table
   - Using Windows Authentication where possible

2. **TRUSTWORTHY Database**: Setting TRUSTWORTHY ON has security implications. Consider:
   - Using certificate signing instead
   - Limiting to specific databases
   - Regular security audits

3. **File Access**: SQL Server service account needs:
   - Read access to local files
   - Network access for SFTP connections

## Alternative: PowerShell Solution

If CLR is not allowed in your environment, use PowerShell instead:

```powershell
# Save as C:\Scripts\SFTPUpload.ps1
param([string]$LocalFile, [string]$RemoteFile)

Add-Type -Path "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"

$sessionOptions = New-Object WinSCP.SessionOptions -Property @{
    Protocol = [WinSCP.Protocol]::Sftp
    HostName = "wssftp.files.com"
    PortNumber = 22
    UserName = "hilco_sftp"
    Password = "R7`$kT9!vL2@pQ4zM"
}

$session = New-Object WinSCP.Session
$session.Open($sessionOptions)
$session.PutFiles($LocalFile, $RemoteFile).Check()
$session.Dispose()
```

Call from SQL:
```sql
EXEC xp_cmdshell 'powershell -File "C:\Scripts\SFTPUpload.ps1" -LocalFile "C:\Reports\file.csv" -RemoteFile "/Hilco Global/file.csv"'
```

## Support

For issues or questions, check:
- SQL Server error logs
- SSRS execution logs
- Windows Event Viewer
- SFTP server logs

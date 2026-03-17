@echo off
echo =============================================
echo Building SFTP CLR Assembly
echo =============================================

cd /d C:\GITLAB_Clone_Repos\SFTP_CLR

echo.
echo Step 1: Restoring NuGet packages...
dotnet restore

echo.
echo Step 2: Building the project...
dotnet build --configuration Debug

echo.
echo =============================================
echo Build completed!
echo =============================================
echo.
echo Output files location:
echo C:\GITLAB_Clone_Repos\SFTP_CLR\bin\Debug\net48\
echo.
echo Next steps:
echo 1. Verify the DLL files exist in the output folder
echo 2. Update Deploy_CLR.sql with your database name
echo 3. Run Deploy_CLR.sql in SQL Server Management Studio
echo.
pause

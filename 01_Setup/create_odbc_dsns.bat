@echo off
setlocal

echo ============================================================
echo  Cricket Analytics Platform - ODBC data sources for Alteryx
echo ============================================================
echo.
rem Creates (or recreates) the 64-bit System DSNs CricketSource_DSN and CricketDW_DSN on
rem ODBC Driver 17 for SQL Server (or Driver 18 if 17 is absent), Windows authentication, trusting the local
rem server certificate, against SQL_INSTANCE from config\local.config.
rem System DSNs need administrator rights: right-click this file and choose "Run as administrator".

net session >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Administrator rights needed. Right-click create_odbc_dsns.bat and choose "Run as administrator".
    pause
    exit /b 1
)

set "CONFIG_FILE=%~dp0..\config\local.config"
if not exist "%CONFIG_FILE%" (
    echo [FAIL] config\local.config not found. Copy config\local.config.example to config\local.config first.
    pause
    exit /b 1
)
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    if not "%%A"=="" set "%%A=%%B"
)
if "%SQL_INSTANCE%"=="" (
    echo [FAIL] SQL_INSTANCE is not set in config\local.config.
    pause
    exit /b 1
)
if "%SOURCE_DB_NAME%"=="" set "SOURCE_DB_NAME=CricketSource"
if "%WAREHOUSE_DB_NAME%"=="" set "WAREHOUSE_DB_NAME=CricketDW"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$drv = @('ODBC Driver 17 for SQL Server', 'ODBC Driver 18 for SQL Server') | Where-Object { Get-OdbcDriver -Name $_ -Platform '64-bit' -ErrorAction SilentlyContinue } | Select-Object -First 1;" ^
  "if (-not $drv) { throw 'No ODBC Driver 17 or 18 for SQL Server (64-bit) is installed' };" ^
  "Write-Host ('Using ' + $drv);" ^
  "$pairs = @{ 'CricketSource_DSN' = $env:SOURCE_DB_NAME; 'CricketDW_DSN' = $env:WAREHOUSE_DB_NAME };" ^
  "foreach ($name in $pairs.Keys) {" ^
  "  Get-OdbcDsn -Name $name -DsnType System -Platform '64-bit' -ErrorAction SilentlyContinue | Remove-OdbcDsn;" ^
  "  Add-OdbcDsn -Name $name -DriverName $drv -DsnType System -Platform '64-bit' -SetPropertyValue @(\"Server=$env:SQL_INSTANCE\", \"Database=$($pairs[$name])\", 'Trusted_Connection=Yes', 'TrustServerCertificate=Yes');" ^
  "  $a = (Get-OdbcDsn -Name $name -DsnType System -Platform '64-bit').Attribute;" ^
  "  if ($a['Database'] -ne $pairs[$name]) { throw \"$name was created without its default database\" };" ^
  "  Write-Host ('[OK]   {0} -> server {1}, database {2}' -f $name, $a['Server'], $a['Database'])" ^
  "}"
if errorlevel 1 (
    echo [FAIL] Could not create the DSNs. Run check_prerequisites.bat: it checks the ODBC driver and the connection.
    pause
    exit /b 1
)

echo.
echo Done. Next: create the two Alteryx connections on these DSNs ^(07_Docs\deployment.md, step B6^).
pause
endlocal

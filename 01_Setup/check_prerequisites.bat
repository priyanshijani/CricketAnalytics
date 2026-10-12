@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo  Cricket Analytics Platform - Prerequisite Check
echo ============================================================
echo.

set "CONFIG_FILE=%~dp0..\config\local.config"
set "ALL_OK=1"

if not exist "%CONFIG_FILE%" (
    copy /Y "%~dp0..\config\local.config.example" "%CONFIG_FILE%" >nul
    echo [NEW]  Created config\local.config from the template.
)

for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    if not "%%A"=="" set "%%A=%%B"
)

if "%SQL_INSTANCE%"=="" (
    echo [FAIL] SQL_INSTANCE is not set. Open config\local.config, set SQL_INSTANCE ^(e.g. localhost\SQLEXPRESS^),
    echo        save, and run this check again.
    set "ALL_OK=0"
) else (
    echo [OK]   SQL_INSTANCE = %SQL_INSTANCE%
)

where sqlcmd >nul 2>&1
if errorlevel 1 (
    echo [FAIL] sqlcmd not found on PATH. SQL Server 2022/2025 setup normally installs it; otherwise run
    echo        winget install sqlcmd   and open a new terminal afterwards.
    set "ALL_OK=0"
) else (
    echo [OK]   sqlcmd found on PATH.
)

set "ODBC_DRIVER="
reg query "HKLM\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 18 for SQL Server" >nul 2>&1 && set "ODBC_DRIVER=ODBC Driver 18 for SQL Server"
reg query "HKLM\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 17 for SQL Server" >nul 2>&1 && set "ODBC_DRIVER=ODBC Driver 17 for SQL Server"
if "%ODBC_DRIVER%"=="" (
    echo [FAIL] No ODBC Driver 17 or 18 for SQL Server. Alteryx connects through it:
    echo        winget install --id Microsoft.msodbcsql.18
    set "ALL_OK=0"
) else (
    echo [OK]   %ODBC_DRIVER% is installed.
)

if /i "%SQL_AUTH_MODE%"=="SQL" (
    set "AUTH_ARGS=-U %SQL_USER% -P %SQL_PASSWORD% -C"
) else (
    set "AUTH_ARGS=-E -C"
)
if not "%SQL_INSTANCE%"=="" (
    sqlcmd -S "%SQL_INSTANCE%" %AUTH_ARGS% -b -l 15 -h -1 -Q "SET NOCOUNT ON; SELECT 1" >nul 2>&1
    if errorlevel 1 (
        echo [FAIL] Cannot connect to %SQL_INSTANCE%. Check the instance name and that the SQL Server service is
        echo        running ^(Get-Service MSSQL*^). See 07_Docs\deployment.md, Troubleshooting.
        set "ALL_OK=0"
    ) else (
        echo [OK]   Connected to %SQL_INSTANCE%.
    )
)

:summary
echo.
echo ============================================================
if "%ALL_OK%"=="1" (
    echo  All prerequisites satisfied. Next: setup_database.bat, then create_odbc_dsns.bat
    echo  ^(Run as administrator^). Full order: 07_Docs\deployment.md, part B.
) else (
    echo  One or more prerequisites are missing. Resolve every [FAIL] line above before continuing.
)
echo ============================================================

pause
endlocal

@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo  Cricket Analytics Platform - SQL test suite
echo ============================================================
echo.

set "ROOT=%~dp0.."
set "CONFIG_FILE=%ROOT%\config\local.config"
set "OUT=%~dp0results\latest_sql_test_run.txt"

if not exist "%CONFIG_FILE%" (
    echo [FAIL] config\local.config not found. Run 01_Setup\check_prerequisites.bat first.
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

if /i "%SQL_AUTH_MODE%"=="SQL" (
    set "AUTH_ARGS=-U %SQL_USER% -P %SQL_PASSWORD% -C"
) else (
    set "AUTH_ARGS=-E -C"
)

rem Every script prints one row per check ending in PASS or FAIL. Run after a successful pipeline run.
echo SQL test run %DATE% %TIME% > "%OUT%"
for %%S in (check_reconciliation check_business_rules check_referential_integrity check_rpt_views check_security) do (
    echo Running %%S ...
    echo. >> "%OUT%"
    echo ===== %%S ===== >> "%OUT%"
    sqlcmd -S "%SQL_INSTANCE%" %AUTH_ARGS% -b -W -s "|" -i "%~dp0sql\%%S.sql" >> "%OUT%" 2>&1
    if errorlevel 1 echo [ERROR] %%S did not complete - see the output file.
)

set /a PASSED=0, FAILED=0
for /f %%N in ('findstr /r /c:"|PASS *$" /c:"|PASS|" "%OUT%" ^| find /c /v ""') do set PASSED=%%N
for /f %%N in ('findstr /r /c:"|FAIL *$" /c:"|FAIL|" "%OUT%" ^| find /c /v ""') do set FAILED=%%N

echo.
echo ============================================================
echo  Checks passed: %PASSED%   failed: %FAILED%
echo  Full output: 06_Tests\results\latest_sql_test_run.txt
echo ============================================================
if not "%FAILED%"=="0" (
    echo.
    echo Failed checks:
    findstr /r /c:"|FAIL *$" /c:"|FAIL|" "%OUT%"
)
echo.
pause
endlocal

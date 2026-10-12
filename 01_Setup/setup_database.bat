@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo  Cricket Analytics Platform - Database Setup
echo ============================================================
echo.

set "ROOT=%~dp0.."
set "CONFIG_FILE=%ROOT%\config\local.config"

if not exist "%CONFIG_FILE%" (
    echo [FAIL] config\local.config not found. Run check_prerequisites.bat first.
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

echo Running DDL against %SQL_INSTANCE% ...
echo.

for %%F in (00_create_databases 01_source_schema 02_warehouse_schema 03_audit_control_schema 04_populate_dim_date 05_validated_staging_schema 06_dq_metadata_schema 07_dq_feedback_schema 08_warehouse_load_schema 10_orchestration) do (
    echo --- %%F.sql ---
    sqlcmd -S "%SQL_INSTANCE%" %AUTH_ARGS% -b -i "%ROOT%\01_Setup\sql\%%F.sql"
    if errorlevel 1 (
        echo [FAIL] %%F.sql failed. Stopping.
        pause
        exit /b 1
    )
)

set "SEED_FILE=%ROOT%\02_SampleData\source\sql_server\seed_data.sql"
if exist "%SEED_FILE%" (
    echo --- seed_data.sql ---
    sqlcmd -S "%SQL_INSTANCE%" %AUTH_ARGS% -b -d "%SOURCE_DB_NAME%" -i "%SEED_FILE%"
    if errorlevel 1 (
        echo [FAIL] seed_data.sql failed. Stopping.
        pause
        exit /b 1
    )
) else (
    echo [WARN] seed_data.sql not found yet - run the sample-data generator first, then re-run
    echo        this script to seed CricketSource.
)

echo --- reporting views (03_Alteryx\reporting_views) ---
sqlcmd -S "%SQL_INSTANCE%" %AUTH_ARGS% -b -i "%ROOT%\03_Alteryx\reporting_views\rpt_reporting_views.sql"
if errorlevel 1 (
    echo [FAIL] rpt_reporting_views.sql failed. Stopping.
    pause
    exit /b 1
)

if "%SOURCE_READER_PASSWORD%"=="" goto :no_security
if "%ETL_WRITER_PASSWORD%"=="" goto :no_security
if "%RPT_READER_PASSWORD%"=="" goto :no_security
echo --- 09_security.sql ---
sqlcmd -S "%SQL_INSTANCE%" %AUTH_ARGS% -b -i "%ROOT%\01_Setup\sql\09_security.sql" -v SOURCE_READER_PASSWORD="%SOURCE_READER_PASSWORD%" ETL_WRITER_PASSWORD="%ETL_WRITER_PASSWORD%" RPT_READER_PASSWORD="%RPT_READER_PASSWORD%"
if errorlevel 1 (
    echo [FAIL] 09_security.sql failed. Stopping.
    pause
    exit /b 1
)
goto :security_done
:no_security
echo [WARN] Login passwords are not set in config\local.config - skipped 09_security.sql.
echo        Set SOURCE_READER_PASSWORD, ETL_WRITER_PASSWORD and RPT_READER_PASSWORD, then re-run.
:security_done

echo.
echo ============================================================
echo  Database setup complete.
echo ============================================================

pause
endlocal

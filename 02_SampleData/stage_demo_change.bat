@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0.."
set "DEMO_ROOT=%ROOT%\02_SampleData\source\demo_changes"
set "DEST=%ROOT%\02_SampleData\_runtime\inbound"

if "%~1"=="" (
    echo Usage: stage_demo_change.bat ^<category^> [filename]
    echo   category: new_matches ^| corrected_files ^| duplicate_files ^| malformed_files
    echo   filename: optional - a specific file in that category. Omit to stage every file in it.
    pause
    exit /b 1
)

set "CATEGORY=%~1"
set "SRC=%DEMO_ROOT%\%CATEGORY%"

if not exist "%SRC%" (
    echo [FAIL] Unknown category: %CATEGORY%
    echo        Expected one of: new_matches, corrected_files, duplicate_files, malformed_files
    pause
    exit /b 1
)

if not exist "%DEST%" mkdir "%DEST%"

if "%~2"=="" (
    echo Staging all files from %CATEGORY% ...
    for %%F in ("%SRC%\*.*") do (
        if /i not "%%~nxF"=="README.md" copy /Y "%%F" "%DEST%\" >nul
    )
) else (
    echo Staging %~2 from %CATEGORY% ...
    copy /Y "%SRC%\%~2" "%DEST%\" >nul
)

echo Done. Open 03_Alteryx\workflows\00_orchestrator.yxmd in Designer and run it to process it.

pause
endlocal

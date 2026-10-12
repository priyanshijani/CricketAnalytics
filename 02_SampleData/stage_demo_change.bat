@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0.."
set "DEMO_ROOT=%ROOT%\02_SampleData\source\demo_changes"
set "DEST=%ROOT%\02_SampleData\_runtime\inbound"

rem Usage: stage_demo_change.bat [category] [filename]
rem   category: new_matches | corrected_files | duplicate_files | malformed_files (asked for when omitted)
rem   filename: optional - a specific file in that category. Omit to stage every file in it.
set "CATEGORY=%~1"
if "%CATEGORY%"=="" (
    echo Which demo change do you want to stage? Run one per pipeline pass, in this order:
    echo   1. new_matches      - new match M0121
    echo   2. corrected_files  - corrected match M0031
    echo   3. duplicate_files  - identical re-send of M0051
    echo   4. malformed_files  - three broken files
    set /p "CHOICE=Enter 1-4: "
    if "!CHOICE!"=="1" set "CATEGORY=new_matches"
    if "!CHOICE!"=="2" set "CATEGORY=corrected_files"
    if "!CHOICE!"=="3" set "CATEGORY=duplicate_files"
    if "!CHOICE!"=="4" set "CATEGORY=malformed_files"
)
if "%CATEGORY%"=="" (
    echo [FAIL] No demo change chosen.
    pause
    exit /b 1
)
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

echo Done. Staged %CATEGORY%. Close Tableau, open 03_Alteryx\workflows\00_orchestrator.yxmd in Designer and run it to process it.

pause
endlocal

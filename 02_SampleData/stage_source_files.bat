@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0.."
set "SRC=%ROOT%\02_SampleData\source"
set "DEST=%ROOT%\02_SampleData\_runtime\inbound"

echo Staging baseline source files into the runtime inbound folder...

if not exist "%DEST%" mkdir "%DEST%"

for %%D in (json\matches csv\deliveries csv\player_rankings csv\historical_stats) do (
    if exist "%SRC%\%%D\*.*" (
        for %%F in ("%SRC%\%%D\*.*") do (
            if /i not "%%~nxF"=="README.md" copy /Y "%%F" "%DEST%\" >nul
        )
    )
)

echo Done. Files staged in %DEST%
echo Open 03_Alteryx\workflows\00_orchestrator.yxmd in Designer and run it to process them.

pause
endlocal

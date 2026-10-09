@echo off
rem Runs setup.ps1 elevated, bypassing the execution policy.
rem Arguments are passed through, e.g.: setup.cmd -SkipApps -SkipSystem
setlocal

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
set "rc=%errorlevel%"

echo.
if "%rc%"=="0" (echo setup.ps1 finished.) else (echo setup.ps1 failed with exit code %rc%.)
pause
exit /b %rc%

@echo off
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [CodeFerry] PowerShell was not found.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
set "CODEFERRY_EXIT=%ERRORLEVEL%"

if not "%CODEFERRY_EXIT%"=="0" (
    echo.
    echo [CodeFerry] Deployment or startup failed with exit code %CODEFERRY_EXIT%.
    pause
)

exit /b %CODEFERRY_EXIT%

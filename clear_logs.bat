@echo off
setlocal

set "SCRIPT=%~dp0clear_logs.ps1"

if not exist "%SCRIPT%" (
    echo Error: %SCRIPT% not found 1>&2
    exit /b 1
)

powershell -NoProfile -NoLogo -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

endlocal & exit /b %RC%
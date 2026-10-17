@echo off
setlocal

set "LOG_DIR=L:\log"
set "BACKUP_DIR=C:\lab1\backup"
set "SCRIPT=%~dp0clear_logs.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test_clear_logs.ps1" "%LOG_DIR%" "%BACKUP_DIR%" "%SCRIPT%"

exit /b %errorlevel%
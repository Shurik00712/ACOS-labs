@echo off
setlocal

if not defined LOG_DIR    set "LOG_DIR=L:\log"
if not defined BACKUP_DIR set "BACKUP_DIR=C:\lab1\backup"
if not defined SCRIPT     set "SCRIPT=%~dp0clear_logs.ps1"

if not "%~1"=="" set "LOG_DIR=%~1"
if not "%~2"=="" set "BACKUP_DIR=%~2"
if not "%~3"=="" set "SCRIPT=%~3"

powershell -NoProfile -File "%~dp0test_clear_logs.ps1" "%LOG_DIR%" "%BACKUP_DIR%" "%SCRIPT%"

exit /b %errorlevel%
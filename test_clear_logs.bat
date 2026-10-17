@echo off
setlocal EnableDelayedExpansion

set "LOG_DIR=L:\log"
set "BACKUP_DIR=C:\lab1\backup"
set "SCRIPT=clear_logs.bat"
set "FAILED=0"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

call :test_empty
call :test_below
REM call :test_above
call :test_lzma
call :test_nonexistent
call :test_archive_valid

if "!FAILED!"=="1" (
    echo.
    echo === FAILED ===
    exit /b 1
)
echo.
echo === ALL PASSED ===
exit /b 0

:clearup
del /f /q "%LOG_DIR%\*" 2>nul
del /f /q "%BACKUP_DIR%\*" 2>nul
exit /b 0

:create_file
powershell -NoProfile -Command "$f=[IO.File]::Create('%~1'); $f.SetLength(%~2 * 1MB); $f.Close(); (Get-Item '%~1').LastWriteTime = (Get-Date).AddDays(-%~3)" >nul 2>&1
exit /b 0

:count_backup
set "CNT=0"
for /f %%a in ('dir /b /a-d "%BACKUP_DIR%\*" 2^>nul ^| find /c /v ""') do set "CNT=%%a"
exit /b 0

:get_disk_mb
for /f "usebackq" %%a in (`powershell -NoProfile -Command "[math]::Floor(((Get-PSDrive (Get-Item -LiteralPath '%LOG_DIR%').PSDrive.Name).Used + (Get-PSDrive (Get-Item -LiteralPath '%LOG_DIR%').PSDrive.Name).Free)/1MB)"`) do set "DISK_MB=%%a"
exit /b 0

:test_empty
echo.
echo === TEST: empty ===
call :clearup
call %SCRIPT% "%LOG_DIR%" 70 "%BACKUP_DIR%" >nul 2>&1
call :count_backup
if not "!CNT!"=="0" (
    echo FAIL: expected 0 archives, got !CNT!
    set "FAILED=1"
    exit /b 1
)
echo PASS: empty
exit /b 0

:test_below
echo.
echo === TEST: below threshold ===
call :clearup
call :get_disk_mb
set /a half=DISK_MB*50/100
call :create_file "%LOG_DIR%\new.log" !half! 1
call %SCRIPT% "%LOG_DIR%" 70 "%BACKUP_DIR%" >nul 2>&1
call :count_backup
if not "!CNT!"=="0" (
    echo FAIL: expected 0 archives, got !CNT!
    set "FAILED=1"
    exit /b 1
)
echo PASS: below threshold
exit /b 0

:test_above
echo.
echo === TEST: above threshold ===
call :clearup
call :get_disk_mb
set /a chunk=DISK_MB*18/100
call :create_file "%LOG_DIR%\f1.log" !chunk! 10
call :create_file "%LOG_DIR%\f2.log" !chunk! 5
call :create_file "%LOG_DIR%\f3.log" !chunk! 1
call :create_file "%LOG_DIR%\f4.log" !chunk! 1
call :create_file "%LOG_DIR%\f5.log" !chunk! 1
call %SCRIPT% "%LOG_DIR%" 70 "%BACKUP_DIR%" >nul 2>&1
call :count_backup
if "!CNT!"=="0" (
    echo FAIL: no archive created
    set "FAILED=1"
    exit /b 1
)
if exist "%LOG_DIR%\f1.log" (
    echo FAIL: f1 not deleted
    set "FAILED=1"
    exit /b 1
)
if not exist "%LOG_DIR%\f5.log" (
    echo FAIL: f5 deleted
    set "FAILED=1"
    exit /b 1
)
echo PASS: above threshold
exit /b 0

:test_lzma
echo.
echo === TEST: lzma ===
call :clearup
call :get_disk_mb
set /a chunk=DISK_MB*18/100
call :create_file "%LOG_DIR%\f1.log" !chunk! 10
call :create_file "%LOG_DIR%\f2.log" !chunk! 1
call :create_file "%LOG_DIR%\f3.log" !chunk! 1
call :create_file "%LOG_DIR%\f4.log" !chunk! 1
call :create_file "%LOG_DIR%\f5.log" !chunk! 1
set "LAB1_MAX_COMPRESSION=1"
call %SCRIPT% "%LOG_DIR%" 70 "%BACKUP_DIR%"
set "LAB1_MAX_COMPRESSION="
set "LZ=0"
for %%a in ("%BACKUP_DIR%\*.tar.lzma") do if exist "%%a" set "LZ=1"
if "!LZ!"=="0" (
    echo FAIL: no .tar.lzma found
    set "FAILED=1"
    exit /b 1
)
echo PASS: lzma
exit /b 0

:test_nonexistent
echo.
echo === TEST: nonexistent ===
call :clearup
set "FAKE=L:\does_not_exist"
if exist "%FAKE%" rmdir /s /q "%FAKE%"

call %SCRIPT% "%FAKE%" 70 "%BACKUP_DIR%" >nul 2>&1
if not errorlevel 1 (
    echo FAIL: nonexistent — script must fail
    set "FAILED=1"
    exit /b 1
)
call :count_backup
if not "!CNT!"=="0" (
    echo FAIL: nonexistent — no archives expected
    set "FAILED=1"
    exit /b 1
)
echo PASS: nonexistent
exit /b 0

:test_archive_valid
echo.
echo === TEST: archive valid ===
call :clearup
call :get_disk_mb
set /a chunk=DISK_MB*80/100/5
call :create_file "%LOG_DIR%\f1.log" !chunk! 10
call :create_file "%LOG_DIR%\f2.log" !chunk! 5
call :create_file "%LOG_DIR%\f3.log" !chunk! 1
call :create_file "%LOG_DIR%\f4.log" !chunk! 1
call :create_file "%LOG_DIR%\f5.log" !chunk! 1

call %SCRIPT% "%LOG_DIR%" 70 "%BACKUP_DIR%" >nul 2>&1

set "ARCH="
for %%a in ("%BACKUP_DIR%\*.tar.gz") do if exist "%%a" set "ARCH=%%a"

if "!ARCH!"=="" (
    echo FAIL: archive valid — not found
    set "FAILED=1"
    exit /b 1
)

tar -tzf "!ARCH!" >nul 2>&1
if errorlevel 1 (
    echo FAIL: archive valid
    set "FAILED=1"
    exit /b 1
)

set "INSIDE=0"
for /f %%c in ('tar -tzf "!ARCH!" 2^>nul ^| find /c /v ""') do set "INSIDE=%%c"
if "!INSIDE!"=="0" (
    echo FAIL: archive valid — empty
    set "FAILED=1"
    exit /b 1
)
echo PASS: archive valid
exit /b 0
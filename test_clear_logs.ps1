param(
    [Parameter(Mandatory, Position = 0)] [string]$LOG_DIR,
    [Parameter(Mandatory, Position = 1)] [string]$BACKUP_DIR,
    [Parameter(Mandatory, Position = 2)] [string]$SCRIPT
)

$FAILED = 0

if (-not (Test-Path -LiteralPath $LOG_DIR))    { New-Item -ItemType Directory -Path $LOG_DIR    | Out-Null }
if (-not (Test-Path -LiteralPath $BACKUP_DIR)) { New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null }

function clearup {
    Get-ChildItem -LiteralPath $LOG_DIR    -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $BACKUP_DIR -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

function create_file($path, [long]$size, $days) {
    $f = [IO.File]::Create($path)
    $f.SetLength($size)
    $f.Close()
    (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$days)
}

function count_backup {
    $script:CNT = @(Get-ChildItem -LiteralPath $BACKUP_DIR -File -ErrorAction SilentlyContinue).Count
}

function get_disk_bytes {
    $drive = Get-PSDrive -Name (Get-Item -LiteralPath $LOG_DIR).PSDrive.Name
    $script:DISK = [long]($drive.Used + $drive.Free)
}

function run_script($dir) {
    $global:LASTEXITCODE = 0
    try {
        & $SCRIPT $dir 70 $BACKUP_DIR 2>&1 | Out-Host
    } catch {
        Write-Host $_
        $script:CODE = 1
        return
    }
    $script:CODE = $LASTEXITCODE
}

function test_empty {
    Write-Host ""
    Write-Host "=== TEST: empty ==="
    clearup
    run_script $LOG_DIR
    count_backup
    if ($CNT -ne 0) {
        Write-Host "FAIL: expected 0 archives, got $CNT"
        $script:FAILED = 1
        return
    }
    Write-Host "PASS: empty"
}

function test_below {
    Write-Host ""
    Write-Host "=== TEST: below threshold ==="
    clearup
    get_disk_bytes
    $half = [long]($DISK * 50 / 100)
    create_file "$LOG_DIR\new.log" $half 1
    run_script $LOG_DIR
    count_backup
    if ($CNT -ne 0) {
        Write-Host "FAIL: expected 0 archives, got $CNT"
        $script:FAILED = 1
        return
    }
    Write-Host "PASS: below threshold"
}

function test_above {
    Write-Host ""
    Write-Host "=== TEST: above threshold ==="
    clearup
    get_disk_bytes
    $slice = [long]($DISK * 18 / 100)
    create_file "$LOG_DIR\f1.log" $slice 10
    create_file "$LOG_DIR\f2.log" $slice 5
    create_file "$LOG_DIR\f3.log" $slice 2
    create_file "$LOG_DIR\f4.log" $slice 1
    create_file "$LOG_DIR\f5.log" $slice 1
    run_script $LOG_DIR
    count_backup
    if ($CNT -eq 0) {
        Write-Host "FAIL: no archive created"
        $script:FAILED = 1
        return
    }
    if (Test-Path -LiteralPath "$LOG_DIR\f1.log") {
        Write-Host "FAIL: f1 not deleted"
        $script:FAILED = 1
        return
    }
    if (-not (Test-Path -LiteralPath "$LOG_DIR\f5.log")) {
        Write-Host "FAIL: f5 deleted"
        $script:FAILED = 1
        return
    }
    Write-Host "PASS: above threshold"
}

function test_lzma {
    Write-Host ""
    Write-Host "=== TEST: lzma ==="
    clearup
    get_disk_bytes
    $slice = [long]($DISK * 18 / 100)
    create_file "$LOG_DIR\f1.log" $slice 10
    create_file "$LOG_DIR\f2.log" $slice 5
    create_file "$LOG_DIR\f3.log" $slice 2
    create_file "$LOG_DIR\f4.log" $slice 1
    create_file "$LOG_DIR\f5.log" $slice 1
    $env:LAB1_MAX_COMPRESSION = "1"
    run_script $LOG_DIR
    Remove-Item Env:LAB1_MAX_COMPRESSION -ErrorAction SilentlyContinue
    $LZ = 0
    foreach ($a in Get-ChildItem -LiteralPath $BACKUP_DIR -Filter "*.tar.lzma" -File -ErrorAction SilentlyContinue) { $LZ = 1 }
    if ($LZ -eq 0) {
        Write-Host "FAIL: no .tar.lzma found"
        $script:FAILED = 1
        return
    }
    Write-Host "PASS: lzma"
}

function test_nonexistent {
    Write-Host ""
    Write-Host "=== TEST: nonexistent ==="
    clearup
    $FAKE = Join-Path ([IO.Path]::GetPathRoot($LOG_DIR)) "does_not_exist"
    if (Test-Path -LiteralPath $FAKE) { Remove-Item -LiteralPath $FAKE -Recurse -Force }
    run_script $FAKE
    if ($CODE -eq 0) {
        Write-Host "FAIL: nonexistent - script must fail"
        $script:FAILED = 1
        return
    }
    count_backup
    if ($CNT -ne 0) {
        Write-Host "FAIL: nonexistent - no archives expected"
        $script:FAILED = 1
        return
    }
    Write-Host "PASS: nonexistent"
}

function test_archive_valid {
    Write-Host ""
    Write-Host "=== TEST: archive valid ==="
    clearup
    get_disk_bytes
    $slice = [long]($DISK * 80 / 100 / 5)
    create_file "$LOG_DIR\f1.log" $slice 10
    create_file "$LOG_DIR\f2.log" $slice 5
    create_file "$LOG_DIR\f3.log" $slice 2
    create_file "$LOG_DIR\f4.log" $slice 1
    create_file "$LOG_DIR\f5.log" $slice 1

    run_script $LOG_DIR

    $ARCH = ""
    foreach ($a in Get-ChildItem -LiteralPath $BACKUP_DIR -Filter "*.tar.gz" -File -ErrorAction SilentlyContinue) { $ARCH = $a.FullName }

    if ($ARCH -eq "") {
        Write-Host "FAIL: archive valid - not found"
        $script:FAILED = 1
        return
    }

    tar -tzf $ARCH *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL: archive valid"
        $script:FAILED = 1
        return
    }

    $INSIDE = @(tar -tzf $ARCH 2>$null).Count
    if ($INSIDE -eq 0) {
        Write-Host "FAIL: archive valid - empty"
        $script:FAILED = 1
        return
    }
    Write-Host "PASS: archive valid"
}

test_empty
test_below
test_above
test_lzma
test_nonexistent
test_archive_valid

if ($FAILED -eq 1) {
    Write-Host ""
    Write-Host "=== FAILED ==="
    exit 1
}
Write-Host ""
Write-Host "=== ALL PASSED ==="
exit 0
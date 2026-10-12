#!/bin/bash
set -euo pipefail


LOG_DIR="${1:-$HOME/log}"
BACKUP_DIR="${2:-/backup}"

setup() {
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    find "$LOG_DIR" -mindepth 1 -delete
    find "$BACKUP_DIR" -mindepth 1 -delete
}

get_max_size() {
    df -B1 "$LOG_DIR" | awk 'NR==2 {print $2}'
}

create_file() {
    local path="$1" size_mb="$2" days="$3"
    dd if=/dev/zero of="$path" bs=1M count="$size_mb" 2>/dev/null
    touch -d "$days days ago" "$path"
}

count_backup() {
    find "$BACKUP_DIR" -type f -printf '.' 2>/dev/null | wc -c
}

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

test_empty() {
    setup
    ./clear_logs.sh "$LOG_DIR" 70 "$BACKUP_DIR" > /dev/null
    local archives
    archives=$(count_backup)
    [ "$archives" -ne 0 ] && fail "test_empty: there should be no archives"
    pass "test_empty"
}
test_above_threshold() {
    setup
    local max mb slice
    max=$(get_max_size)
    mb=$(( max / 1024 / 1024 ))
    slice=$(( mb * 90 / 100 / 5 ))
    create_file "$LOG_DIR/f1.log" "$slice" 8
    create_file "$LOG_DIR/f2.log" "$slice" 5
    create_file "$LOG_DIR/f3.log" "$slice" 4
    create_file "$LOG_DIR/f4.log" "$slice" 1
    create_file "$LOG_DIR/f5.log" "$slice" 1
    ./clear_logs.sh "$LOG_DIR" 70 "$BACKUP_DIR" > /dev/null
    local archives
    archives=$(count_backup)
    if [ "$archives" -eq 0 ]; then
        fail "archive was not created"
    fi
    if [ -f "$LOG_DIR/f1.log" ]; then
        fail "old files were not deleted"
    fi
    if [ ! -f "$LOG_DIR/f4.log" ]; then
        fail "new files were deleted"
    fi
    pass "test_above_passed"
}
test_below_threshold() {
    setup
    local max
    max=$(get_max_size)
    create_file "$LOG_DIR/new.log" $(( max / 1024 / 1024 / 2 )) 1
    ./clear_logs.sh "$LOG_DIR" 70 "$BACKUP_DIR" > /dev/null
    local archives
    archives=$(count_backup)
    [ "$archives" -ne 0 ] && fail "test_below: there should be no archives"
    pass "test_below"
}
test_lzma() {
    setup
    local max mb slice
    max=$(get_max_size)
    mb=$(( max / 1024 / 1024 ))
    slice=$(( mb * 90 / 100 / 5 ))
    create_file "$LOG_DIR/f1.log" "$slice" 8
    create_file "$LOG_DIR/f2.log" "$slice" 5
    create_file "$LOG_DIR/f3.log" "$slice" 4
    create_file "$LOG_DIR/f4.log" "$slice" 1
    create_file "$LOG_DIR/f5.log" "$slice" 1
    LAB1_MAX_COMPRESSION=1 ./clear_logs.sh "$LOG_DIR" 70 "$BACKUP_DIR" > /dev/null
    local count=0
    local IFS=
    count=$(find "$BACKUP_DIR" -name '*.tar.lzma' -printf '.' 2>/dev/null | wc -c)
    if [ "$count" -eq 0 ]; then
        fail ".tar.lzma not found"
    fi
    pass "test_lzma_passed"
}
test_nonexistent() {
    setup
    local fake="${TEST_DIR%/*}/doesnt_exist"
    if ./clear_logs.sh "$fake" 70 "$BACKUP_DIR" > /dev/null 2>&1; then
        fail "test_nonexistent"
    fi
    if [ "$(count_backup)" -ne 0 ]; then
        fail "there should be no archives"
    fi
    pass "test_nonexistent"
}
test_archive_valid() {
    setup
    local max mb slice
    max=$(get_max_size)
    mb=$(( max / 1024 / 1024 ))
    slice=$(( mb * 90 / 100 / 5 ))
    create_file "$LOG_DIR/f1.log" "$slice" 8
    create_file "$LOG_DIR/f2.log" "$slice" 5
    create_file "$LOG_DIR/f3.log" "$slice" 1
    create_file "$LOG_DIR/f4.log" "$slice" 1
    create_file "$LOG_DIR/f5.log" "$slice" 1
    ./clear_logs.sh "$LOG_DIR" 70 "$BACKUP_DIR" > /dev/null
    local archive
    archive=$(find "$BACKUP_DIR" -name '*.tar.gz' | head -1)
    [ -z "$archive" ] && fail "test_archive_valid"
    tar -tzf "$archive" > /dev/null 2>&1 || fail "test_archive_valid"
    [ "$(tar -tzf "$archive" | wc -l)" -eq 0 ] && fail "test_archive_valid"
    pass "test_archive_valid"
}
test_empty
test_below_threshold
test_above_threshold
test_lzma
test_nonexistent
test_archive_valid
echo "All tests passed"
#!/bin/bash
set -euo pipefail

test_dir="$HOME/lab1"
log_dir="$test_dir/log"
backup_dir="$test_dir/backup"
script="./clear_logs.sh"

fail() { echo "Error: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

setup() {
    mkdir -p "$log_dir" "$backup_dir"
    find "$log_dir" -mindepth 1 -delete
    find "$backup_dir" -mindepth 1 -delete
}

get_max_size() {
    local max_size
    max_size=$(df -B1 --output=size "$log_dir" | tail -n 1 | grep -o '[0-9]*')
    case "$max_size" in
        ''|*[!0-9]*) fail "could not determine the disk size for $log_dir" ;;
    esac
    echo "$max_size"
}

create_file() {
    local path="$1" size_mb="$2" days="$3"
    dd if=/dev/zero of="$path" bs=1M count="$size_mb" 2>/dev/null
    touch -d "$days days ago" "$path"
}

count_backup() {
    find "$backup_dir" -type f -printf '.' 2>/dev/null | wc -c
}

fill_log_dir() {
    local max mb slice
    max=$(get_max_size)
    mb=$(( max / 1024 / 1024 ))
    slice=$(( mb * 90 / 100 / 5 ))
    create_file "$log_dir/f1.log" "$slice" 8
    create_file "$log_dir/f2.log" "$slice" 5
    create_file "$log_dir/f3.log" "$slice" 4
    create_file "$log_dir/f4.log" "$slice" 1
    create_file "$log_dir/f5.log" "$slice" 1
}

test_empty() {
    setup
    $script "$log_dir" 70 "$backup_dir" > /dev/null
    local archives
    archives=$(count_backup)
    (( archives == 0 )) || fail "test_empty: there should be no archives"
    pass "test_empty"
}

test_below_threshold() {
    setup
    local max
    max=$(get_max_size)
    create_file "$log_dir/new.log" $(( max / 1024 / 1024 / 2 )) 1
    $script "$log_dir" 70 "$backup_dir" > /dev/null
    local archives
    archives=$(count_backup)
    (( archives == 0 )) || fail "test_below: there should be no archives"
    pass "test_below"
}

test_above_threshold() {
    setup
    fill_log_dir
    $script "$log_dir" 70 "$backup_dir" > /dev/null
    local archives
    archives=$(count_backup)
    (( archives > 0 )) || fail "test_above: archive was not created"
    [ ! -f "$log_dir/f1.log" ] || fail "test_above: old files were not deleted"
    [ -f "$log_dir/f4.log" ] || fail "test_above: new files were deleted"
    pass "test_above"
}

test_lzma() {
    setup
    fill_log_dir
    LAB1_MAX_COMPRESSION=1 $script "$log_dir" 70 "$backup_dir" > /dev/null
    local count
    count=$(find "$backup_dir" -name '*.tar.lzma' -printf '.' 2>/dev/null | wc -c)
    (( count > 0 )) || fail "test_lzma: .tar.lzma not found"
    pass "test_lzma"
}

test_nonexistent() {
    setup
    local fake="$test_dir/doesnt_exist"
    if $script "$fake" 70 "$backup_dir" > /dev/null 2>&1; then
        fail "test_nonexistent: script should fail on missing directory"
    fi
    (( $(count_backup) == 0 )) || fail "test_nonexistent: there should be no archives"
    pass "test_nonexistent"
}

test_archive_valid() {
    setup
    fill_log_dir
    $script "$log_dir" 70 "$backup_dir" > /dev/null
    local archive
    archive=$(find "$backup_dir" -name '*.tar.gz' | head -1)
    [ -n "$archive" ] || fail "test_archive_valid: archive not found"
    tar -tzf "$archive" > /dev/null 2>&1 || fail "test_archive_valid: archive is corrupted"
    (( $(tar -tzf "$archive" | wc -l) > 0 )) || fail "test_archive_valid: archive is empty"
    pass "test_archive_valid"
}

test_empty
test_below_threshold
test_above_threshold
test_lzma
test_nonexistent
test_archive_valid
echo "All tests passed"
#!/bin/bash
set -euo pipefail

LOG_DIR="${1:-/log}"
THRESHOLD="${2:-70}"
BACKUP_DIR="${3:-/backup}"

case "$THRESHOLD" in
    ''|*[!0-9]*)
        echo "THRESHOLD should be a number" >&2
        exit 1
        ;;
esac

if (( THRESHOLD < 0 || THRESHOLD > 100 )); then
    echo "Error: THRESHOLD should be in range 0..100" >&2
    exit 1
fi

if [ ! -d "$LOG_DIR" ]; then
    echo "Error: $LOG_DIR not found" >&2
    exit 1
fi

case "$BACKUP_DIR/" in
    "$LOG_DIR/"*)
        echo "Error: BACKUP_DIR ($BACKUP_DIR) located in LOG_DIR ($LOG_DIR)" >&2
        exit 1
        ;;
esac

MAX_SIZE=$(df -B1 --output=size "$LOG_DIR" | tail -n 1 | grep -o '[0-9]*')

if [ "$MAX_SIZE" -le 0 ]; then 
    echo "Error: could not determine the disk size for $LOG_DIR (size less zero)" >&2
    exit 1
fi

case "$MAX_SIZE" in
    ''|*[!0-9]*)
        echo "Error: could not determine the disk size for $LOG_DIR" >&2
        exit 1
        ;;
esac

echo "disk size $LOG_DIR: $MAX_SIZE bytes"

mkdir -p "$BACKUP_DIR"

current_size=$(du -sb "$LOG_DIR" | cut -f1)

case "$current_size" in
    ''|*[!0-9]*)
        echo "Error: could not determine the size $LOG_DIR" >&2
        exit 1
        ;;
esac

percent=$(( current_size * 100 / MAX_SIZE ))
echo "Size of $LOG_DIR: $current_size bytes ($percent%)"

if [ "$percent" -le "$THRESHOLD" ]; then
    echo "The fill level does not exceed $THRESHOLD%."
    exit 0
fi

target=$(( MAX_SIZE * THRESHOLD / 100 ))
need=$(( current_size - target ))
echo "Need to free: $need bytes"

files=()
echo find "$LOG_DIR"
while IFS= read -r -d '' line; do
    echo $line
    files+=("$line")
done < <(find "$LOG_DIR" -type f -printf '%T@ %p\0' | sort -z -n | cut -z -d ' ' -f2-)

files_arch=()
i=0
freed=0
while [ "$need" -gt 0 ] && [ "$i" -lt "${#files[@]}" ]; do
    path="${files[i]}"

    size=$(stat -c %s "$path") || {
        echo "Error: stat for: $path" >&2
        exit 1
    }

    files_arch+=("$path")
    need=$(( need - size ))
    freed=$(( freed + size ))

    i=$(( i + 1 ))
done

if [ ${#files_arch[@]} -eq 0 ]; then
    echo "No files found for archivation."
    exit 0
fi

if [ "$need" -gt 0 ]; then
    echo "Warning: Failed to collect files for $need bytes; everything that was found will be archived and deleted." >&2
fi

timestamp=$(date +%Y%m%d_%H%M%S)
if [ "${LAB1_MAX_COMPRESSION:-0}" = "1" ]; then
    arch="$BACKUP_DIR/archive_$timestamp.tar.lzma"
    tar --lzma -cf "$arch" -C "$LOG_DIR" -- "${files_arch[@]#"$LOG_DIR"/}"
else
    arch="$BACKUP_DIR/archive_$timestamp.tar.gz"
    tar -czf "$arch" -C "$LOG_DIR" -- "${files_arch[@]#"$LOG_DIR"/}"
fi

if [ ! -s "$arch" ]; then
    echo "Error: archive is not created or empty: $arch" >&2
    exit 1
fi

echo "Archive created: $arch"
rm -f "${files_arch[@]}"
echo "Number of files deleted: ${#files_arch[@]}, freed: $freed bytes"
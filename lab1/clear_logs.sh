#!/bin/bash
set -euo pipefail

log_dir="${1:-/log}"
threshold="${2:-70}"
backup_dir="${3:-/backup}"

case "$threshold" in
    ''|*[!0-9]*)
        echo "THRESHOLD should be a number" >&2
        exit 1
        ;;
esac

if (( threshold < 0 || threshold > 100 )); then
    echo "Error: THRESHOLD should be in range 0..100" >&2
    exit 1
fi

if [ ! -d "$log_dir" ]; then
    echo "Error: $log_dir not found" >&2
    exit 1
fi

case "$backup_dir/" in
    "$log_dir/"*)
        echo "Error: $backup_dir located in $log_dir" >&2
        exit 1
        ;;
esac

max_size=$(df -B1 --output=size "$log_dir" | tail -n 1 | grep -o '[0-9]*')

if [ "$max_size" -le 0 ]; then
    echo "Error: could not determine the disk size for $log_dir" >&2
    exit 1
fi

case "$max_size" in
    ''|*[!0-9]*)
        echo "Error: could not determine the disk size for $log_dir" >&2
        exit 1
        ;;
esac

echo "disk size $log_dir: $max_size bytes"

mkdir -p "$backup_dir"

current_size=$(du -sb "$log_dir" | cut -f1)

case "$current_size" in
    ''|*[!0-9]*)
        echo "Error: could not determine the size $log_dir" >&2
        exit 1
        ;;
esac

percent=$(( current_size * 100 / max_size ))
echo "Size of $log_dir: $current_size bytes ($percent%)"

if [ "$percent" -le "$threshold" ]; then
    echo "The fill level does not exceed $threshold%."
    exit 0
fi

target=$(( max_size * threshold / 100 ))
need=$(( current_size - target ))
echo "Need to free: $need bytes"

files=()
while IFS= read -r -d '' line; do
    echo $line
    files+=("$line")
done < <(find "$log_dir" -type f -printf '%T@ %p\0' | sort -z -n | cut -z -d ' ' -f2-)

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

ts=$(date +%Y%m%d_%H%M%S)
if [ "${LAB1_MAX_COMPRESSION:-0}" = "1" ]; then
    arch="$backup_dir/archive_$ts.tar.lzma"
    tar --lzma -cf "$arch" -C "$log_dir" -- "${files_arch[@]#"$log_dir"/}"
else
    arch="$backup_dir/archive_$ts.tar.gz"
    tar -czf "$arch" -C "$log_dir" -- "${files_arch[@]#"$log_dir"/}"
fi

if [ ! -s "$arch" ]; then
    echo "Error: archive is not created or empty: $arch" >&2
    exit 1
fi

echo "Archive created: $arch"
rm -f "${files_arch[@]}"
echo "Number of files deleted: ${#files_arch[@]}, freed: $freed bytes"
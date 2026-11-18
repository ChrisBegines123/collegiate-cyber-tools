#!/bin/bash
# File Integrity Monitoring - Monitor Script
# Compares current file hashes against baseline and logs changes

DB_DIR="/var/lib/fim"
DB_FILE="$DB_DIR/baseline.db"
CURRENT="/tmp/fim_current_$$"

TARGETS=(
    /boot
    /usr/bin
    /usr/sbin
    /etc/passwd
    /etc/shadow
)

if [ ! -f "$DB_FILE" ]; then
    logger "FIM ALERT: No baseline database found at $DB_FILE - run install.sh first"
    exit 1
fi

> "$CURRENT"

for target in "${TARGETS[@]}"; do
    if [ -d "$target" ]; then
        find "$target" -type f -exec sha256sum {} \; >> "$CURRENT"
    elif [ -f "$target" ]; then
        sha256sum "$target" >> "$CURRENT"
    fi
done

sort -o "$CURRENT" "$CURRENT"

# Check for modified or deleted files
while read -r hash filepath; do
    current_line=$(grep -F "$filepath" "$CURRENT")
    if [ -z "$current_line" ]; then
        logger "FIM ALERT: Deleted file detected: $filepath"
    elif ! echo "$current_line" | grep -Fxq "$hash  $filepath"; then
        logger "FIM ALERT: Modified file detected: $filepath"
    fi
done < "$DB_FILE"

# Check for new files
while read -r hash filepath; do
    if ! grep -Fq "$filepath" "$DB_FILE"; then
        logger "FIM ALERT: New file detected: $filepath"
    fi
done < "$CURRENT"

rm -f "$CURRENT"

#!/bin/bash
# File Integrity Monitoring - Baseline Installer
# Creates baseline hashes and registers crontab for monitoring

DB_DIR="/var/lib/fim"
DB_FILE="$DB_DIR/baseline.db"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/monitor.sh"

TARGETS=(
    /boot
    /usr/bin
    /usr/sbin
    /etc/passwd
    /etc/shadow
)

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Must run as root."
    exit 1
fi

mkdir -p "$DB_DIR"

echo "Creating baseline database at $DB_FILE"

> "$DB_FILE"

for target in "${TARGETS[@]}"; do
    if [ -d "$target" ]; then
        find "$target" -type f -exec sha256sum {} \; >> "$DB_FILE"
    elif [ -f "$target" ]; then
        sha256sum "$target" >> "$DB_FILE"
    else
        echo "Warning: $target does not exist, skipping."
    fi
done

sort -o "$DB_FILE" "$DB_FILE"
chmod 600 "$DB_FILE"

echo "Baseline created with $(wc -l < "$DB_FILE") entries."

# Register crontab entry
chmod +x "$MONITOR_SCRIPT"
CRON_ENTRY="*/10 * * * * $MONITOR_SCRIPT"

if crontab -l 2>/dev/null | grep -Fq "$MONITOR_SCRIPT"; then
    echo "Crontab entry already exists, updating."
    crontab -l 2>/dev/null | grep -Fv "$MONITOR_SCRIPT" | { cat; echo "$CRON_ENTRY"; } | crontab -
else
    ( crontab -l 2>/dev/null; echo "$CRON_ENTRY" ) | crontab -
fi

echo "Crontab registered: $CRON_ENTRY"
echo "FIM installation complete."

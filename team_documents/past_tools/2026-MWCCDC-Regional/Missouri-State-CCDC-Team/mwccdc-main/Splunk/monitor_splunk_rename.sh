#!/bin/bash

# Script to detect Splunk folder rename
# Date: March 04, 2025

LOG_FILE="/var/log/splunk_rename_monitor.log"
AUDIT_KEY="splunk_rename"
CHECK_INTERVAL=5  # Seconds between checks

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Log setup
echo "Starting Splunk rename monitor at $(date)" >> "$LOG_FILE"

# Function to check for rename events
check_rename() {
    LAST_EVENT=$(ausearch -k "$AUDIT_KEY" --format raw | tail -n 1)
    if [[ -n "$LAST_EVENT" && "$LAST_EVENT" =~ name=\"/opt/splunk\".*name=\"/opt/spunk\" ]]; then
        TIMESTAMP=$(echo "$LAST_EVENT" | grep -o 'time->[^ ]*' | cut -d'>' -f2)
        USER=$(echo "$LAST_EVENT" | grep -o 'auid=[0-9]*' | cut -d'=' -f2)
        echo "[ALERT] Splunk folder renamed to spunk at $TIMESTAMP by user ID $USER" | tee -a "$LOG_FILE"
        # Optional: Send email alert
        # echo "Splunk folder renamed at $TIMESTAMP by UID $USER" | mail -s "Splunk Rename Alert" admin@example.com
    fi
}

# Main loop
echo "Monitoring /opt for splunk -> spunk rename..."
while true; do
    check_rename
    sleep "$CHECK_INTERVAL"
done
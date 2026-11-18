#!/bin/bash
#
# This script continuously monitors active TCP connections using the 'ss' command
# and logs the output to a file. It's useful for detecting unusual network activity.
#

# --- Configuration ---
LOG_FILE="/var/log/tcp_connections.log"
INTERVAL=60 # Time in seconds between checks

echo "--- TCP Connection Monitor ---"
echo "[*] Monitoring TCP connections every ${INTERVAL} seconds."
echo "[*] Output will be logged to ${LOG_FILE}"

# Main loop
while true; do
    echo "--- Snapshot at $(date) ---" >> "${LOG_FILE}"
    
    # Use 'ss' to get TCP connections.
    # -t: TCP
    # -a: All (listening and non-listening)
    # -n: Numeric (don't resolve hostnames)
    # -p: Show process using socket
    ss -tanp >> "${LOG_FILE}"
    
    echo "" >> "${LOG_FILE}"
    
    sleep "${INTERVAL}"
done

#!/bin/bash
#
# This script sets up a simple, low-interaction SSH honeypot using netcat.
# It listens on a specified port and logs all connection attempts and
# any data sent by the attacker.
#
# This is NOT a high-security honeypot. It is for early warning and
# intelligence gathering in a CCDC-like environment.
#

# --- Configuration ---
HONEYPOT_PORT="2222"
LOG_FILE="/var/log/ssh_honeypot.log"
BANNER="SSH-2.0-OpenSSH_7.6p1 Ubuntu-4ubuntu0.3" # A plausible SSH banner

# Check for root privileges to run on a low port, though not strictly necessary for >1024
if [ "$(id -u)" -ne 0 ]; then
    echo "This script is best run as root for logging and port access."
fi

# Check if netcat is installed
if ! command -v nc &> /dev/null; then
    echo "netcat (nc) is not installed. Please install it first."
    echo "For Debian/Ubuntu: sudo apt-get install netcat"
    echo "For CentOS/RHEL: sudo yum install nmap-ncat"
    exit 1
fi

echo "--- SSH Honeypot ---"
echo "[*] Starting simple SSH honeypot on port ${HONEYPOT_PORT}"
echo "[*] Connection attempts will be logged to ${LOG_FILE}"

# Create the log file and set permissions
touch "${LOG_FILE}"
chmod 600 "${LOG_FILE}"

# Main loop to keep the honeypot running
while true; do
    {
        echo "--- Connection received at $(date) from \$NCAT_REMOTE_ADDR ---"
        echo -e "${BANNER}"
        # Log everything the client sends
        cat
        echo "--- Connection closed at $(date) ---"
        echo ""
    } | nc -l -p "${HONEYPOT_PORT}" -v >> "${LOG_FILE}" 2>&1
    
    echo "Connection closed. Restarting listener..."
    sleep 1
done

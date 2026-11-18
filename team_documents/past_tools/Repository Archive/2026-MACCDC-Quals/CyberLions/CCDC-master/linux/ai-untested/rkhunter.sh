#!/bin/bash
#
# This script automates running rkhunter (Rootkit Hunter) to scan for
# rootkits, backdoors, and other malicious software.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Check if rkhunter is installed
if ! command -v rkhunter &> /dev/null; then
    echo "rkhunter is not installed. Please install it first."
    echo "For Debian/Ubuntu: sudo apt-get install rkhunter"
    echo "For CentOS/RHEL: sudo yum install rkhunter"
    exit 1
fi

LOG_FILE="/var/log/rkhunter_scan_$(date +%Y%m%d_%H%M%S).log"
echo "--- Rkhunter Scan ---"
echo "Scan results will be logged to ${LOG_FILE}"

# Update rkhunter's data files
echo "[*] Updating rkhunter data files..."
rkhunter --update

# Update file properties database
echo "[*] Updating rkhunter file properties database..."
rkhunter --propupd

# Run the scan
# --check: Performs the scan
# --skip-keypress: Skips the "press enter to continue" prompts
# --report-warnings-only: Only shows warnings in the output
echo "[*] Starting rkhunter scan. This may take a while..."
rkhunter --check --skip-keypress --report-warnings-only | tee "${LOG_FILE}"

echo "[+] Rkhunter scan complete."
echo "Please review the output above and check the log file for details:"
echo "${LOG_FILE}"

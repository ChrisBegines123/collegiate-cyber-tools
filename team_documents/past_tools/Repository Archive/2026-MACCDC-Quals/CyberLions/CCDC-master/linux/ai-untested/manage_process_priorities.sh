#!/bin/bash
#
# This script manages the priority of running processes.
# It can increase the priority of critical defensive tools to ensure
# they have sufficient CPU resources during high system load.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root to change process priorities." >&2
    exit 1
fi

# --- Configuration ---
# List of process names to prioritize. Use exact process names.
# Example: PROCESSES_TO_PRIORITIZE=("clamscan" "auditd" "ossec-agentd")
PROCESSES_TO_PRIORITIZE=(
    "clamscan"
    "rkhunter"
    "auditd"
    "syslogd"
    "rsyslogd"
)

# Niceness value to set. Ranges from -20 (highest priority) to 19 (lowest).
# We'll use a moderately high priority.
NEW_NICE_VALUE="-10"

echo "--- Managing Process Priorities ---"

for process_name in "${PROCESSES_TO_PRIORITIZE[@]}"; do
    # Find the PIDs of the running processes
    pids=$(pgrep -f "$process_name")

    if [ -n "$pids" ]; then
        echo "[*] Found process: ${process_name} with PID(s): ${pids}"
        
        # Use renice to change the priority
        renice -n "${NEW_NICE_VALUE}" -p "${pids}"
        
        if [ $? -eq 0 ]; then
            echo "[+] Successfully set priority for ${process_name} to ${NEW_NICE_VALUE}"
        else
            echo "[-] Failed to set priority for ${process_name}"
        fi
    else
        echo "[ ] Process not found: ${process_name}"
    fi
done

echo "--- Process priority management complete ---"
echo "You can verify the new priorities with: ps -eo pid,ni,comm"

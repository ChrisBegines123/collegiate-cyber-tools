#!/bin/bash
#
# This script gathers a comprehensive inventory of the system.
# It collects information about the OS, hardware, network, services,
# users, and more, saving it to a file for analysis.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root for full information gathering." >&2
fi

# --- Setup ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="inventory_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"
echo "System inventory will be saved in the '${OUTPUT_DIR}' directory."

# Function to run a command and save its output
run_and_log() {
    local cmd="$1"
    local outfile="$2"
    echo "--- Running: ${cmd} ---" >> "${OUTPUT_DIR}/${outfile}"
    eval "${cmd}" >> "${OUTPUT_DIR}/${outfile}" 2>&1
    echo -e "\n\n" >> "${OUTPUT_DIR}/${outfile}"
}

# --- System Information ---
echo "[*] Gathering basic system information..."
run_and_log "uname -a" "system_info.txt"
run_and_log "hostnamectl" "system_info.txt"
run_and_log "cat /etc/*-release" "system_info.txt"
run_and_log "uptime" "system_info.txt"

# --- Hardware Information ---
echo "[*] Gathering hardware information..."
run_and_log "lscpu" "hardware_info.txt"
run_and_log "lsmem" "hardware_info.txt"
run_and_log "lsblk" "hardware_info.txt"
run_and_log "lspci" "hardware_info.txt"
run_and_log "lsusb" "hardware_info.txt"
run_and_log "df -h" "hardware_info.txt"

# --- Network Information ---
echo "[*] Gathering network information..."
run_and_log "ip a" "network_info.txt"
run_and_log "ip r" "network_info.txt"
run_and_log "ss -tuln" "network_info.txt"
run_and_log "cat /etc/resolv.conf" "network_info.txt"

# --- Users and Groups ---
echo "[*] Gathering user and group information..."
run_and_log "cat /etc/passwd" "users_groups.txt"
run_and_log "cat /etc/shadow" "users_groups.txt"
run_and_log "cat /etc/group" "users_groups.txt"
run_and_log "cat /etc/sudoers" "users_groups.txt"
run_and_log "w" "users_groups.txt"
run_and_log "last" "users_groups.txt"

# --- Services and Processes ---
echo "[*] Gathering service and process information..."
run_and_log "ps aux" "services_processes.txt"
run_and_log "systemctl list-units --type=service --all" "services_processes.txt"
run_and_log "systemctl list-timers --all" "services_processes.txt"
run_and_log "crontab -l" "services_processes.txt" # For the current user
run_and_log "ls -l /etc/cron.*" "services_processes.txt" # System-wide cron jobs

# --- Installed Packages ---
echo "[*] Gathering installed package information..."
if command -v dpkg &> /dev/null; then
    run_and_log "dpkg -l" "packages.txt"
elif command -v rpm &> /dev/null; then
    run_and_log "rpm -qa" "packages.txt"
fi

# --- Firewall Configuration ---
echo "[*] Gathering firewall configuration..."
if command -v ufw &> /dev/null; then
    run_and_log "ufw status verbose" "firewall.txt"
fi
if command -v iptables &> /dev/null; then
    run_and_log "iptables -L" "firewall.txt"
fi

echo "[+] Inventory gathering complete. Results are in '${OUTPUT_DIR}'."

#!/bin/bash
#
# This script finds and reports on potentially insecure file permissions.
# It identifies world-writable files and directories, as well as files
# with SUID/SGID bits set. It can optionally try to fix them.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Log file for changes
LOG_FILE="permissions_changes.log"
echo "--- Permissions Check Log ---" > "$LOG_FILE"
date >> "$LOG_FILE"
echo "---------------------------" >> "$LOG_FILE"

# --- Find World-Writable Files and Directories ---
echo "[*] Searching for world-writable files and directories..."
# We exclude /tmp and /dev/shm as they are expected to be world-writable
world_writable=$(find / -not \( -path "/tmp/*" -o -path "/dev/shm/*" \) -perm -o=w -type f -o -perm -o=w -type d 2>/dev/null)

if [ -n "$world_writable" ]; then
    echo "[-] Found world-writable files/directories:"
    echo "$world_writable"
    echo "$world_writable" >> "$LOG_FILE"

    read -p "Do you want to remove world-writable permissions on these items? (y/n): " choice
    if [ "$choice" == "y" ]; then
        echo "[*] Removing world-writable permissions..."
        echo "$world_writable" | while read -r item; do
            chmod o-w "$item"
            echo "Removed world-writable from $item" >> "$LOG_FILE"
        done
        echo "[+] Permissions fixed."
    fi
else
    echo "[+] No world-writable files or directories found (excluding /tmp and /dev/shm)."
fi


# --- Find SUID/SGID Files ---
echo -e "\n[*] Searching for SUID and SGID files..."
# SUID files
suid_files=$(find / -perm /4000 2>/dev/null)
if [ -n "$suid_files" ]; then
    echo "[-] Found SUID files:"
    echo "$suid_files"
    echo -e "\n--- SUID Files ---" >> "$LOG_FILE"
    echo "$suid_files" >> "$LOG_FILE"
    echo "    Review these files. SUID bit on non-standard binaries can be a security risk."
else
    echo "[+] No SUID files found."
fi

# SGID files
sgid_files=$(find / -perm /2000 2>/dev/null)
if [ -n "$sgid_files" ]; then
    echo "[-] Found SGID files:"
    echo "$sgid_files"
    echo -e "\n--- SGID Files ---" >> "$LOG_File"
    echo "$sgid_files" >> "$LOG_FILE"
    echo "    Review these files. SGID bit might be expected on some directories."
else
    echo "[+] No SGID files found."
fi

echo -e "\n[+] Permissions check complete. See ${LOG_FILE} for details."

#!/bin/bash
#
# This script checks for the use of LD_PRELOAD, a common technique
# used by rootkits to hijack function calls. It checks environment
# files and the system-wide ld.so.preload file.
#

echo "--- Checking for LD_PRELOAD Hijacking ---"

# --- Check /etc/ld.so.preload ---
LD_SO_PRELOAD_FILE="/etc/ld.so.preload"
echo "[*] Checking ${LD_SO_PRELOAD_FILE}..."

if [ -f "${LD_SO_PRELOAD_FILE}" ]; then
    echo "[-] Found ${LD_SO_PRELOAD_FILE}. Content:"
    cat "${LD_SO_PRELOAD_FILE}"
    echo "    This file preloads shared libraries for all processes. Investigate these libraries."
else
    echo "[+] ${LD_SO_PRELOAD_FILE} does not exist."
fi

# --- Check Environment Files for LD_PRELOAD ---
echo -e "\n[*] Searching environment files for LD_PRELOAD..."

# List of common environment files to check
ENV_FILES=(
    "/etc/environment"
    "/etc/profile"
    "/etc/profile.d/*.sh"
    "/etc/bash.bashrc"
    "~/.bashrc"
    "~/.bash_profile"
    "~/.profile"
)

found_in_env=false
for file_pattern in "${ENV_FILES[@]}"; do
    # Handle home directory tilde expansion
    eval expanded_pattern=$file_pattern
    
    # Check if the file/pattern exists
    if ls ${expanded_pattern} 1>/dev/null 2>&1; then
        grep -H "LD_PRELOAD" ${expanded_pattern}
        if [ $? -eq 0 ]; then
            found_in_env=true
        fi
    fi
done

if [ "$found_in_env" = true ]; then
    echo "[-] LD_PRELOAD is set in one or more environment files."
    echo "    This could be legitimate, but should be investigated for malicious use."
else
    echo "[+] LD_PRELOAD not found in common environment files."
fi


# --- Check Running Processes for LD_PRELOAD ---
echo -e "\n[*] Checking currently running processes for LD_PRELOAD..."
# This is a bit more involved. We'll check the environment of all processes.
# This can be slow and output a lot of data. We'll grep for the variable.
running_preload=$(ps -e -o pid= | while read pid; do strings -f "/proc/$pid/environ" 2>/dev/null | grep -q "LD_PRELOAD=" && echo "PID: $pid, Command: $(ps -p $pid -o comm=)"; done)

if [ -n "$running_preload" ]; then
    echo "[-] Found running processes with LD_PRELOAD set:"
    echo "$running_preload"
else
    echo "[+] No running processes found with LD_PRELOAD set in their environment."
fi

echo -e "\n--- LD_PRELOAD Check Complete ---"

#!/bin/bash
#
# This script checks for common security misconfigurations in the
# Pluggable Authentication Modules (PAM) framework.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root to access PAM configuration files." >&2
    exit 1
fi

echo "--- Analyzing PAM Configuration ---"

PAM_CONFIG_DIR="/etc/pam.d"

# --- Check Permissions of PAM Configuration Files ---
echo "[*] Checking permissions of PAM configuration files in ${PAM_CONFIG_DIR}..."
insecure_files=$(find "${PAM_CONFIG_DIR}" -type f -not -perm 644)
if [ -n "$insecure_files" ]; then
    echo "[-] The following PAM configuration files have insecure permissions (not 644):"
    echo "$insecure_files"
    read -p "Do you want to fix these permissions to 644? (y/n): " choice
    if [ "$choice" == "y" ]; then
        echo "$insecure_files" | while read -r file; do
            chmod 644 "$file"
        done
        echo "[+] Permissions fixed."
    fi
else
    echo "[+] All PAM configuration files have correct permissions (644)."
fi

# --- Check for Risky PAM Modules ---
echo -e "\n[*] Checking for potentially risky PAM modules..."

# Check for pam_rootok.so which allows root to authenticate without a password
risky_rootok=$(grep -r "pam_rootok.so" "${PAM_CONFIG_DIR}")
if [ -n "$risky_rootok" ]; then
    echo "[-] pam_rootok.so is used in the following files:"
    echo "$risky_rootok"
    echo "    This module can allow root access without a password. Review its usage carefully."
else
    echo "[+] pam_rootok.so not found in PAM configuration."
fi

# Check for nullok, which allows empty passwords
risky_nullok=$(grep -r "nullok" "${PAM_CONFIG_DIR}")
if [ -n "$risky_nullok" ]; then
    echo "[-] 'nullok' is used in the following files, which might allow empty passwords:"
    echo "$risky_nullok"
else
    echo "[+] 'nullok' not found in PAM configuration."
fi

# Check for pam_exec.so, which can execute external commands
risky_exec=$(grep -r "pam_exec.so" "${PAM_CONFIG_DIR}")
if [ -n "$risky_exec" ]; then
    echo "[-] pam_exec.so is used to execute external commands during authentication:"
    echo "$risky_exec"
    echo "    Ensure these commands are secure and necessary."
else
    echo "[+] pam_exec.so not found in PAM configuration."
fi


# --- Check Password Quality Settings ---
echo -e "\n[*] Checking for password quality and cracking resistance..."
# This is often handled by pam_pwquality.so or pam_cracklib.so
pwquality_config=$(grep -r "pam_pwquality.so" "${PAM_CONFIG_DIR}")
if [ -n "$pwquality_config" ]; then
    echo "[+] Password quality settings are likely configured via pam_pwquality.so:"
    echo "$pwquality_config"
else
    echo "[-] Could not find pam_pwquality.so. Password strength rules might not be enforced."
fi

echo -e "\n--- PAM Configuration Analysis Complete ---"

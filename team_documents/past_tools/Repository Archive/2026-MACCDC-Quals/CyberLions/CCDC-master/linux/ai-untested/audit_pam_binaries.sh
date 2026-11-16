#!/bin/bash
#
# This script identifies PAM (Pluggable Authentication Modules) binaries,
# calculates their hashes, and optionally submits them to VirusTotal for
# analysis. This helps detect tampering with critical authentication components.
#

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root to access all PAM files." >&2
    exit 1
fi

# --- Configuration ---
# You need a VirusTotal API key for the submission part.
# Get one from virustotal.com and place it here.
VT_API_KEY=""

PAM_LIB_DIR="/lib/security"
if [ -d "/lib64/security" ]; then
    PAM_LIB_DIR="/lib64/security"
fi

if [ ! -d "$PAM_LIB_DIR" ]; then
    echo "Could not find PAM library directory."
    exit 1
fi

echo "--- Auditing PAM Binaries in ${PAM_LIB_DIR} ---"
LOG_FILE="pam_audit.log"
echo "File,SHA256" > "${LOG_FILE}"

# --- Find and Hash PAM Binaries ---
pam_binaries=$(find "${PAM_LIB_DIR}" -name "*.so" -type f)

echo "[*] Found the following PAM binaries:"
echo "$pam_binaries"
echo ""

for binary in $pam_binaries; do
    sha256=$(sha256sum "$binary" | awk '{print $1}')
    echo "Hashing ${binary}..."
    echo "${binary},${sha256}" >> "${LOG_FILE}"
done

echo "[+] Hashes have been saved to ${LOG_FILE}"

# --- VirusTotal Submission (Optional) ---
if [ -z "$VT_API_KEY" ]; then
    echo -e "\n[*] To submit hashes to VirusTotal, please add your API key to this script."
else
    echo -e "\n[*] Submitting hashes to VirusTotal..."
    while IFS=, read -r file hash; do
        if [ "$file" == "File" ]; then continue; fi # Skip header

        echo "Submitting hash for ${file}..."
        # This is a simple example using curl.
        # A more robust script might parse the JSON response.
        curl -s --request GET \
          --url "https://www.virustotal.com/api/v3/files/${hash}" \
          --header "x-apikey: ${VT_API_KEY}"
        
        # Add a small delay to not exceed API rate limits
        sleep 15 
    done < "${LOG_FILE}"
    echo "[+] VirusTotal submission complete."
fi

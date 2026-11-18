#!/bin/bash
#
# This script performs security checks on /etc/passwd and /etc/shadow.
# It checks for proper permissions, empty passwords, duplicate UIDs,
# and ensures password policies are enforced.
#

echo "--- Analyzing /etc/passwd and /etc/shadow ---"

# Check permissions of /etc/passwd and /etc/shadow
echo "[*] Checking file permissions..."
if [ "$(stat -c "%a" /etc/passwd)" != "644" ]; then
    echo "[-] /etc/passwd permissions are not 644. Fixing..."
    chmod 644 /etc/passwd
else
    echo "[+] /etc/passwd permissions are correct (644)."
fi

if [ "$(stat -c "%a" /etc/shadow)" != "640" ] && [ "$(stat -c "%a" /etc/shadow)" != "400" ]; then
    echo "[-] /etc/shadow permissions are not 640 or 400. Fixing to 640..."
    chmod 640 /etc/shadow
else
    echo "[+] /etc/shadow permissions are correct."
fi

# Check for accounts with empty passwords
echo "[*] Checking for accounts with empty passwords..."
empty_pass_users=$(awk -F: '($2 == "") {print $1}' /etc/shadow)
if [ -n "$empty_pass_users" ]; then
    echo "[-] The following users have empty passwords:"
    echo "$empty_pass_users"
    echo "    Consider locking these accounts or setting a password."
else
    echo "[+] No users with empty passwords found."
fi

# Check for locked accounts
echo "[*] Listing locked accounts (password hash is ! or *)..."
locked_accounts=$(awk -F: '($2 == "!" || $2 == "*") {print $1}' /etc/shadow)
if [ -n "$locked_accounts" ]; then
    echo "[+] The following accounts are locked:"
    echo "$locked_accounts"
else
    echo "[+] No locked accounts found."
fi


# Check for duplicate UIDs
echo "[*] Checking for duplicate UIDs..."
duplicate_uids=$(cut -f3 -d: /etc/passwd | sort -n | uniq -d)
if [ -n "$duplicate_uids" ]; then
    echo "[-] Duplicate UIDs found:"
    for uid in $duplicate_uids; do
        echo "    UID: $uid"
        grep ":x:$uid:" /etc/passwd | cut -d: -f1
    done
else
    echo "[+] No duplicate UIDs found."
fi


# Check for accounts with UID 0 (root)
echo "[*] Checking for accounts with UID 0..."
root_accounts=$(awk -F: '($3 == 0) {print $1}' /etc/passwd)
if [ "$(echo "$root_accounts" | wc -l)" -gt 1 ]; then
    echo "[-] Multiple accounts with UID 0 found:"
    echo "$root_accounts"
else
    echo "[+] Only 'root' has UID 0."
fi


echo "--- Analysis complete ---"

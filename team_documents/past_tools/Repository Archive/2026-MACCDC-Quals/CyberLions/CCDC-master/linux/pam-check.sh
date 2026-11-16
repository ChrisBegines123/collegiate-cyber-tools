#!/bin/bash

echo "===== PAM Security Check ====="
ISSUES=0

check_line() {
    FILE=$1
    PATTERN=$2
    MESSAGE=$3
    if grep -q "$PATTERN" "$FILE" 2>/dev/null; then
        echo "[!!] $MESSAGE ($FILE)"
        ((ISSUES++))
    fi
}

check_missing() {
    FILE=$1
    PATTERN=$2
    MESSAGE=$3
    if ! grep -q "$PATTERN" "$FILE" 2>/dev/null; then
        echo "[!!] MISSING: $MESSAGE in $FILE"
        ((ISSUES++))
    fi
}

FILES=("/etc/pam.d/system-auth" "/etc/pam.d/common-password" "/etc/pam.d/login" "/etc/pam.d/sudo")

echo "[+] Checking for NULL passwords allowed..."
check_line "/etc/pam.d/common-password" "nullok" "nullok detected → Allows blank passwords"
check_line "/etc/pam.d/system-auth" "nullok" "nullok detected → Allows blank passwords"

echo "[+] Checking for pam_permit"
check_line "/etc/pam.d/common-auth" "sufficient" "pam_permit.so sufficient found → Unconditional access allowed"

echo "[+] Checking password hashing strength..."
check_missing "/etc/pam.d/common-password" "pam_unix.so.*sha512" "SHA512 hashing"
check_missing "/etc/pam.d/system-auth" "pam_unix.so.*sha512" "SHA512 hashing"

echo "[+] Checking password quality enforcement..."
check_missing "/etc/pam.d/common-password" "pam_pwquality.so\|pam_cracklib.so" "Password quality module"
check_missing "/etc/pam.d/system-auth" "pam_pwquality.so\|pam_cracklib.so" "Password quality module"

echo "[+] Checking brute-force mitigation..."
if [[ -f /etc/redhat-release ]]; then
    check_missing "/etc/pam.d/system-auth" "pam_faillock.so" "Failed attempt lockout (RHEL/CentOS)"
else
    check_missing "/etc/pam.d/common-auth" "pam_tally2.so\|pam_faillock.so" "Failed attempt lockout (Debian/Ubuntu)"
fi

echo "[+] Checking sudo permissions..."
check_line "/etc/pam.d/sudo" "pam_permit.so" "sudo bypass issue"

echo 
if [[ $ISSUES -eq 0 ]]; then
    echo "[✔] PAM configuration seems secure based on checks."
else
    echo "[⚠] $ISSUES potential vulnerabilities or weaknesses found."
fi

echo "===== Completed ====="

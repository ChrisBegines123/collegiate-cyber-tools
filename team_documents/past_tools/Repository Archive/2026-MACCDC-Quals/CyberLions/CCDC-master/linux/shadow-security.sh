#!/bin/bash

echo "===== /etc/shadow Password Audit ====="
ISSUES=0

SHADOW="/etc/shadow"

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] You must run this script as root."
  exit 1
fi

echo "[+] Checking for accounts with NO PASSWORD (dangerous)..."
while IFS=: read -r user pass _; do
  if [[ "$pass" == "" ]]; then
    echo "[!!] User '$user' has NO PASSWORD SET"
    ((ISSUES++))
  fi
done < "$SHADOW"

echo "[+] Checking for accounts allowing BLANK PASSWORD (pass = '!' or '*')..."
while IFS=: read -r user pass _; do
  if [[ "$pass" == "!" || "$pass" == "*" ]]; then
    echo "[!] '$user' is locked (no password login allowed) -> OK but confirm intentional"
  fi
done < "$SHADOW"

echo "[+] Checking for legacy / weak password hash types..."
while IFS=: read -r user pass _; do
  if [[ "$pass" == \$1* ]]; then
    echo "[!!] '$user' uses MD5 hash -> deprecated & weak"
    ((ISSUES++))
  fi

  if [[ "$pass" == \$2* ]]; then
    echo "[!] '$user' uses Blowfish (ok but rare) -> Validate system support"
  fi

  if [[ "$pass" == \$5* ]]; then
    echo "[!] '$user' using SHA-256 -> Acceptable but SHA-512 recommended"
  fi

  if [[ "$pass" == \$6* ]]; then
    echo "[✔] '$user' using SHA-512 (good)"
  fi

done < "$SHADOW"

echo "[+] Checking accounts set to NEVER EXPIRE..."
awk -F: '($5 == "" || $5 == 99999) {print "[!!] User " $1 " never expires"}' "$SHADOW" && ((ISSUES++))

echo "[+] Checking if shadow file has been modified RECENTLY..."
lastmod=$(stat -c %y /etc/shadow | cut -d'.' -f1)
echo "[!] /etc/shadow last modified: $lastmod"
echo "    Validate this aligns with authorized password changes"

echo ""
if [[ $ISSUES -eq 0 ]]; then
  echo "[✔] No critical /etc/shadow vulnerabilities detected."
else
  echo "[⚠] $ISSUES shadow security issues found — review recommended."
fi

echo "===== Completed ====="

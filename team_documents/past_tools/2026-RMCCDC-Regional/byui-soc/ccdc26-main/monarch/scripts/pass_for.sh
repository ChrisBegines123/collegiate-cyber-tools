#!/bin/bash
# Changes password for a specified user
# Usage: pass_for.sh USERNAME NEWPASSWORD
# Called by Monarch's rotate command

USER="$1"
PASS="$2"

if [ -z "$USER" ] || [ -z "$PASS" ]; then
    echo "Usage: $0 USERNAME PASSWORD"
    exit 1
fi

echo "$USER:$PASS" | chpasswd 2>/dev/null
if [ $? -eq 0 ]; then
    echo "ok"
else
    echo "fail"
    exit 1
fi

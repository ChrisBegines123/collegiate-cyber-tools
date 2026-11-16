#!/bin/bash
# CCDC26 Monarch - Find all IP addresses in configuration files
# Usage: find-ips.sh [search_path] [specific_ip]
# Examples:
#   find-ips.sh                    # Search /etc for all IPs
#   find-ips.sh /var/www           # Search web root
#   find-ips.sh /etc 10.0.1.50    # Find specific IP in /etc

SEARCH_PATH="${1:-/etc}"
SPECIFIC_IP="$2"

echo "=== IP Address Finder ==="
echo "Searching: $SEARCH_PATH"
echo ""

if [ -n "$SPECIFIC_IP" ]; then
    echo "Looking for: $SPECIFIC_IP"
    grep -rnH --include='*.conf' --include='*.cfg' --include='*.ini' --include='*.yml' --include='*.yaml' --include='*.xml' --include='*.properties' --include='*.env' --include='*.sh' --include='*.py' --include='*.php' "$SPECIFIC_IP" "$SEARCH_PATH" 2>/dev/null
else
    echo "All IP addresses found:"
    grep -rnhoE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$SEARCH_PATH" 2>/dev/null | sort | uniq -c | sort -rn | head -50
    echo ""
    echo "Files containing IPs:"
    grep -rlE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$SEARCH_PATH" --include='*.conf' --include='*.cfg' --include='*.ini' --include='*.yml' --include='*.xml' --include='*.env' --include='*.sh' --include='*.php' 2>/dev/null | sort
fi

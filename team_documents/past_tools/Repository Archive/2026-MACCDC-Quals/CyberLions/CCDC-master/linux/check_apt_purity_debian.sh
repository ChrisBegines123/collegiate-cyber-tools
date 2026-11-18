#!/bin/bash

# Colors for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "--- CHECKING APT SOURCES ---"

# 1. Scan all source files
# valid_domains regex: matches ubuntu.com, debian.org, or kali.org
VALID_DOMAINS="ubuntu\.com|debian\.org|kali\.org"

grep -rE "^deb" /etc/apt/sources.list /etc/apt/sources.list.d/ | while read -r line ; do
    # Check if the line contains a valid domain
    if [[ "$line" =~ $VALID_DOMAINS ]]; then
        echo -e "${GREEN}[OK]   $line${NC}"
    else
        echo -e "${RED}[SUS]  $line${NC}"
        echo -e "       (Make sure this isn't a Red Team IP or random domain)"
    fi
done

echo -e "\n--- CHECKING APT PROXIES ---"
# 2. Check for malicious proxies (Red Team interception)
PROXY_CONF=$(grep -r "Acquire::http::Proxy" /etc/apt/)

if [ -z "$PROXY_CONF" ]; then
    echo -e "${GREEN}[OK]   No APT proxies found.${NC}"
else
    echo -e "${RED}[!!!]  PROXY DETECTED:${NC}"
    echo "$PROXY_CONF"
    echo -e "${RED}       DELETE THE FILE LISTED ABOVE IMMEDIATELY.${NC}"
fi

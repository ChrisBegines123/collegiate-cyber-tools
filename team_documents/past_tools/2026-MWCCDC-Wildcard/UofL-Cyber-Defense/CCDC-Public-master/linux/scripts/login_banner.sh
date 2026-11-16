#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#initool --command bash
# Author: Collin Dewey
# Description:
# Creates a login banner for Linux devices
# Usage: 
# ./<Script_Name> <Banner Text> <Splunk Location>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

if [ $# -ne 1 ]; then
    echo "Usage: $0 <Banner Text> <Splunk Location>"
    exit 1
fi

echo "$1" > /etc/issue
echo "$1" > /etc/issue.net
echo "$1" > /etc/motd

# Splunk
if [ -z "$2" ]; then
    SPLUNK_HOME=/opt/splunk
else
    SPLUNK_HOME="$2"
fi

if [ -d "$SPLUNK_HOME" ]; then 
    if ! command -v initool &> /dev/null; then
        echo "Splunk detected, but initool is not available"
        exit 1
    fi
    if [ ! -f "$SPLUNK_HOME"/etc/system/local/web.conf ]; then mkdir -p "$SPLUNK_HOME"/etc/system/local; touch "$SPLUNK_HOME"/etc/system/local/web.conf; fi
    initool set "$SPLUNK_HOME"/etc/system/local/web.conf settings login_content "$1" > "$SPLUNK_HOME"/etc/system/local/web.conf 
fi

#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Runs either debsums or rpm verification
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check
DEST="/opt/ccdc/modified_$(date +%s)"

mkdir -p "$DEST"
if command -v apt-get >/dev/null 2>&1; then
    if ! command -v  >/dev/null 2>&1; then
        DEBIAN_FRONTEND="noninteractive" web apt-get update -y
        DEBIAN_FRONTEND="noninteractive" web apt-get install debsums -y
    fi
    debsums -ac | xargs -d '\n' -I {} cp --parents -p {} "$DEST"
elif command -v rpm >/dev/null 2>&1; then
    rpm -Va | awk '{print $NF}' | xargs -d '\n' -I {} cp --parents -p {} "$DEST"
fi
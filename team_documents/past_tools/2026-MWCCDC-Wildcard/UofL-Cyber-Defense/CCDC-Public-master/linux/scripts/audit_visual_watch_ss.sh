#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
#  Watchs for any change in connection
# Usage:
# ./<SCRIPT NAME>

snapshotFile="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
currentFile="/tmp/$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

# Take a snapshot of the initial output
netstat -tulpn > $snapshotFile

# Watch
watch -n 1 "netstat -tulpn > $currentFile; diff $snapshotFile $currentFile"
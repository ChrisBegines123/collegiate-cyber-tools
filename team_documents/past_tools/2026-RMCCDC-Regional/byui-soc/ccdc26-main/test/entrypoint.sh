#!/bin/bash
# PID 1 wrapper -- keeps container alive even if SSHD restarts
/usr/sbin/sshd -e
trap "kill $(cat /run/sshd.pid 2>/dev/null) 2>/dev/null" EXIT
while true; do
    if ! pgrep -x sshd >/dev/null 2>&1; then
        /usr/sbin/sshd -e
    fi
    sleep 5
done

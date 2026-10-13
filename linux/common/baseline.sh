#!/bin/bash

previous=$(ps -e -o pid=)

while true; do
    current=$(ps -e -o pid=)

    for pid in $current; do
        if ! grep -qw "$pid" <<< "$previous"; then
            echo "New process detected: PID $pid"
            ps -p "$pid" -o pid,ppid,user,comm,args
        fi
    done

    previous="$current"
    sleep 1
done

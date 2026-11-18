#!/usr/bin/env bash

function nuke_cron() {
    # Comment out every line but the first three
    sed -i '4,${/^[[:space:]]*$/! s/^/#/}' /etc/crontab

    # Backup, then nuke user crons
    tar -cJf /root/b/cron_bak.tar.xz /var/spool/cron/*
    rm -f /var/spool/cron/*
}

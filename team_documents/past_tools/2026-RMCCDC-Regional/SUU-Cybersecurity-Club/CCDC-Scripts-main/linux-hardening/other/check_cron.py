#!/usr/bin/env python3
from pathlib import Path

sys_crontab_dir = Path("/etc/cron.d")
hourly_cron = Path("/etc/cron.hourly")
daily_cron = Path("/etc/cron.daily")
weekly_cron = Path("/etc/cron.weekly")
monthly_cron = Path("/etc/cron.monthly")

cron_dirs = [sys_crontab_dir, hourly_cron, daily_cron, weekly_cron, monthly_cron]

sys_crontab = Path("/etc/crontab")

def get_dir_files(directory):
    files = [f.name for f in directory.iterdir() if f.is_file()]
    return files

for dir in cron_dirs:
    print(f'\nFiles in {dir}:')
    for file in get_dir_files(dir):
        print(f'\t{file}')
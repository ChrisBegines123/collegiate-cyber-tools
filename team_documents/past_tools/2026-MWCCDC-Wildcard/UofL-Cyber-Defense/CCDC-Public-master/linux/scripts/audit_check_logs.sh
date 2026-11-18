#!/usr/bin/env bash
# Author: Noah Tongate @Ap3x
# Description:
# Audit the linux system logs
# Usage:
# ./<SCRIPT NAME>

tail -n 20 /var/log/auth.log
tail -n 20 /var/log/secure
tail -n 20 /var/log/syslog
tail -n 20 /var/log/wmtp
tail -n 20 ~/.bash_history

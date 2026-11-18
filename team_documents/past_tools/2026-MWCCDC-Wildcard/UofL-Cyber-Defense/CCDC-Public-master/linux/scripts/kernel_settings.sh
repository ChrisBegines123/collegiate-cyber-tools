#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Tweaks
# Usage:
# ./<Script_Name>

. $(dirname "$0")/helper.sh; if [ -z ${PUBLIC_KEY+x} ]; then exit 1; fi
root_check

echo '''kernel.sysrq = 1
kernel.panic = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 5
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
kernel.randomize_va_space=2
fs.inotify.max_user_watches=524288
''' >> /etc/sysctl.d/99-sysctl.conf

/sbin/sysctl -p /etc/sysctl.d/99-sysctl.conf
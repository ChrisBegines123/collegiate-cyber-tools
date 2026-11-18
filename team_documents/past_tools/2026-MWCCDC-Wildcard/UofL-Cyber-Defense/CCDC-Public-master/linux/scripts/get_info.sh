#!/usr/bin/env bash
# Author: Collin Dewey
# Description:
# Lists basic system information and important services
# Usage:
# ./<Script_Name>

file=system_info.txt

cat /etc/hostname | tee $file
cat /etc/os-release | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g' | cut -d\" -f2 | tee -a $file
uname -r | tee -a $file
netstat -tulpn | tee -a $file

systemctl list-unit-files --state=enabled --no-pager | awk '/.service|.socket|.timer/ && !/logrotate/ && !/systemd-tmpfiles-clean/ && !/clamav-scan/ && !/getty@/ && !/lvm2-*/ && !/nix-/ && !/systemd-/ && !/user@/ {system("systemctl show "$1" -p Description | sed \"s%Description=%"$1"|%g\"")}' | sort | column -t -s '|' | tee $file 2>&1

echo '''#!/usr/bin/env bash
disable=(''' > disable.sh
systemctl list-unit-files --state=enabled --no-pager | awk '/.service|.socket|.timer/ && !/logrotate/ && !/systemd-tmpfiles-clean/ && !/clamav-scan/ && !/auditd/ && !/chrony/ && !/clamav-/ && !/getty@/ && !/lvm2-*/ && !/NetworkManager/ && !/nix-/ && !/ntpd/ && !/rsyslog/ && !/systemd-/ && !/user@/ && !/iptables/ && !/user-runtime-dir/ && !/dbus/ && !/console-setup/ && !/ifup@/ && !/networking/ && !/keyboard-setup/ && !/resolvconf/ && /service/ {system("echo \\\""$1"\\\" >> disable.sh")}'
echo ''')
for i in "${disable[@]}"; do
    systemctl disable $i
    systemctl stop $i
done''' >> disable.sh
chmod 777 disable.sh
chmod 666 system_info.txt
echo "View disable.sh and edit accordingly"
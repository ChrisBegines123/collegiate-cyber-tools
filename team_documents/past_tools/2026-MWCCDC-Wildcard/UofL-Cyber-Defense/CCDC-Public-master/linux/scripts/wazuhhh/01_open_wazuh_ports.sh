#!/usr/bin/env bash
set -e

echo "Opening firewall ports on Wazuh manager host..."

if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=1514/tcp
  firewall-cmd --permanent --add-port=1515/tcp
  firewall-cmd --permanent --add-port=514/udp
  firewall-cmd --reload
  echo "firewalld rules applied."
elif command -v ufw >/dev/null 2>&1; then
  ufw allow 1514/tcp
  ufw allow 1515/tcp
  ufw allow 514/udp
  ufw reload
  echo "ufw rules applied."
else
  echo "No firewall detected. Skipping."
fi

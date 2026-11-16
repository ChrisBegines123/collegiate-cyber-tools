#!/usr/bin/env bash
set -e

echo "Enabling syslog listener inside Wazuh manager..."

MANAGER_ID=$(docker ps --format '{{.ID}} {{.Names}}' | awk '$2 ~ /wazuh\.manager/ {print $1}')

if [[ -z "$MANAGER_ID" ]]; then
  echo "Wazuh manager container not found."
  exit 1
fi

docker exec -i "$MANAGER_ID" bash << EOF
CONF="/var/ossec/etc/ossec.conf"
EOF

if ! grep -q "<connection>syslog</connection>" "$CONF"; then
  sed -i "/<\/ossec_config>/i \
  <remote>\n\
    <connection>syslog</connection>\n\
    <port>514</port>\n\
    <protocol>udp</protocol>\n\
    <allowed-ips>0.0.0.0/0</allowed-ips>\n\
  </remote>\n" "$CONF"
  echo "[container] Syslog listener added."
else
  echo "[container] Syslog listener already present."
fi
EOF

echo "Syslog listener configured."

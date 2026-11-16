#!/usr/bin/env bash
set -e

echo "Exposing Wazuh agent + syslog ports via Docker..."

cat > docker-compose.override.yml << YAML
services:
  wazuh.manager:
    ports:
      - "1514:1514/tcp"
      - "1515:1515/tcp"
      - "514:514/udp"
YAML

echo "docker-compose.override.yml created."
echo "Restart the stack after running this."

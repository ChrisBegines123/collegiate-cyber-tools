# just to make sure

#!/usr/bin/env bash
set -euo pipefail

WAZUH_DOCKER_BRANCH="v4.14.2"
WAZUH_DIR="wazuh-docker"
SINGLE_NODE_DIR="${WAZUH_DIR}/single-node"

# ports exposed on the wazuh manager host
AGENT_PORT_1="1514/tcp"
AGENT_PORT_2="1515/tcp"
SYSLOG_PORT="514/udp"

echo "Starting Wazuh manager setup + Cisco syslog/rules..."

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Dependencies
if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  if command -v yum >/dev/null 2>&1; then
    yum install -y git
  elif command -v apt >/dev/null 2>&1; then
    apt update && apt install -y git
  else
    echo "No supported package manager found (yum/apt)." >&2
    exit 1
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Install Docker first."
  echo "(Your existing install_wazuh_server.sh installs Docker via yum, run that first if needed.)"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose' plugin not found. Install docker-compose-plugin." >&2
  exit 1
fi

echo "Setting vm.max_map_count"
sysctl -w vm.max_map_count=262144 >/dev/null

# Firewall open (host)

echo "Opening firewall ports on the Wazuh manager host..."
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${AGENT_PORT_1}" || true
  firewall-cmd --permanent --add-port="${AGENT_PORT_2}" || true
  firewall-cmd --permanent --add-port="${SYSLOG_PORT}"  || true
  firewall-cmd --reload || true
  echo "    - firewalld updated."
elif command -v ufw >/dev/null 2>&1; then
  ufw allow 1514/tcp || true
  ufw allow 1515/tcp || true
  ufw allow 514/udp  || true
  ufw reload || true
  echo "    - ufw updated."
else
  echo "    - No firewalld/ufw detected, skipping host firewall changes."
fi

# Clone Wazuh docker repo
if [[ ! -d "${WAZUH_DIR}" ]]; then
  echo "Cloning wazuh-docker (${WAZUH_DOCKER_BRANCH})..."
  git clone https://github.com/wazuh/wazuh-docker.git -b "${WAZUH_DOCKER_BRANCH}"
else
  echo "wazuh-docker already exists, updating branch ${WAZUH_DOCKER_BRANCH}..."
  (cd "${WAZUH_DIR}" && git fetch --all && git checkout "${WAZUH_DOCKER_BRANCH}" && git pull) || true
fi

if [[ ! -d "${SINGLE_NODE_DIR}" ]]; then
  echo "[!] single-node directory not found at ${SINGLE_NODE_DIR}" >&2
  exit 1
fi

cd "${SINGLE_NODE_DIR}"

# Create docker-compose override | expose agent ports + syslog
echo "Writing docker-compose.override.yml to expose ports."
cat > docker-compose.override.yml << YAML
services:
  wazuh.manager:
    ports:
      - "1514:1514/tcp"
      - "1515:1515/tcp"
      - "514:514/udp"
YAML

# Bring stack up
echo "Generating indexer certs..."
docker compose -f generate-indexer-certs.yml run --rm generator

echo "Starting Wazuh stack..."
docker compose up -d

# Enable syslog listener on UDP/514
# Enable Cisco decoders + rules

echo "Configuring Wazuh manager container for syslog + Cisco decoders/rules."
MANAGER_CID="$(docker ps --format '{{.ID}} {{.Names}}' | awk '$2 ~ /wazuh\.manager/ {print $1; exit}')"
if [[ -z "${MANAGER_CID}" ]]; then
  echo "Could not find wazuh.manager container." >&2
  exit 1
fi

echo "    - wazuh.manager container: ${MANAGER_CID}"

docker exec -i "${MANAGER_CID}" bash -lc
set -e
CONF="/var/ossec/etc/ossec.conf"

if ! grep -q "<connection>syslog</connection>" "$CONF"; then
  echo "[container] Adding syslog listener (<remote>) to ossec.conf."
  sed -i "/<\/ossec_config>/i \
  <remote>\n\
    <connection>syslog</connection>\n\
    <port>514</port>\n\
    <protocol>udp</protocol>\n\
    <allowed-ips>0.0.0.0/0</allowed-ips>\n\
  </remote>\n" "$CONF"
else
  echo "[container] Syslog listener already present; skipping."
fi
'

docker exec -i "${MANAGER_CID}" bash -lc '
set -e
DEC_DIR="/var/ossec/etc/decoders"
RULE_DIR="/var/ossec/etc/rules"
DEC_LOCAL="${DEC_DIR}/local_decoder.xml"
RULE_LOCAL="${RULE_DIR}/local_rules.xml"

mkdir -p "$DEC_DIR" "$RULE_DIR"

# If local decoder file doesn't exist, create a basic skeleton
if [[ ! -f "$DEC_LOCAL" ]]; then
  cat > "$DEC_LOCAL" << EOF
<decoders>
</decoders>
EOF
fi

# If local rules file doesnt exist, create a basic skeleton
if [[ ! -f "$RULE_LOCAL" ]]; then
  cat > "$RULE_LOCAL" << EOF
<group name="local,">
</group>
EOF
fi

# Make sure cisco decoder include is present
if ! grep -q "cisco_decoders.xml" "$DEC_LOCAL"; then
  echo "[container] Enabling Cisco decoders in local_decoder.xml."
  sed -i "s#</decoders>#  <include>cisco_decoders.xml</include>\n</decoders>#g" "$DEC_LOCAL"
else
  echo "[container] Cisco decoder include already present. Skipping."
fi

# Make sure cisco rules include is present
if ! grep -q "cisco_rules.xml" "$RULE_LOCAL"; then
  echo "[container] Enabling Cisco rules include in local_rules.xml..."
  sed -i "s#<group name=\"local,\">#<group name=\"local,\">\n  <include>cisco_rules.xml</include>#g" "$RULE_LOCAL" || true
fi
'

echo "estarting Wazuh manager container to apply changes..."
docker restart "${MANAGER_CID}" >/dev/null

echo ""
echo "Done."
echo "    - Wazuh agent ports: 1514/tcp, 1515/tcp exposed"
echo "    - Syslog port: 514/udp exposed"
echo "    - Syslog listener enabled in manager"
echo "    - Cisco decoders/rules enabled via local include"
echo ""
echo "Next checks (run on manager host):"
echo "  docker logs -n 50 ${MANAGER_CID}"
echo "  sudo tcpdump -i any udp port 514"

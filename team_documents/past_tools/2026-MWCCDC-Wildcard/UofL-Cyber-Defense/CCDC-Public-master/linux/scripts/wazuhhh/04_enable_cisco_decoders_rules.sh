#!/usr/bin/env bash
set -e

echo "Enabling Cisco decoders and rules."

MANAGER_ID=$(docker ps --format '{{.ID}} {{.Names}}' | awk '$2 ~ /wazuh\.manager/ {print $1}')

if [[ -z "$MANAGER_ID" ]]; then
  echo "Wazuh manager container not found."
  exit 1
fi

docker exec -i "$MANAGER_ID" bash << EOF
DECODER_FILE="/var/ossec/etc/decoders/local_decoder.xml"
RULE_FILE="/var/ossec/etc/rules/local_rules.xml"
mkdir -p /var/ossec/etc/decoders /var/ossec/etc/rules
EOF

if [[ ! -f "$DECODER_FILE" ]]; then
  cat > "$DECODER_FILE" << XML
<decoders>
</decoders>
XML
fi

if ! grep -q "cisco_decoders.xml" "$DECODER_FILE"; then
  sed -i 's#</decoders>#  <include>cisco_decoders.xml</include>\n</decoders>#' "$DECODER_FILE"
  echo "Cisco decoders enabled."
fi

if [[ ! -f "$RULE_FILE" ]]; then
  cat > "$RULE_FILE" << XML
<group name="local,">
</group>
XML
fi


if ! grep -q "cisco_rules.xml" "$RULE_FILE"; then
  sed -i 's#<group name="local,">#<group name="local,">\n  <include>cisco_rules.xml</include>#' "$RULE_FILE"
  echo "Cisco rules enabled."
fi

echo "Cisco decoders and rules configured."

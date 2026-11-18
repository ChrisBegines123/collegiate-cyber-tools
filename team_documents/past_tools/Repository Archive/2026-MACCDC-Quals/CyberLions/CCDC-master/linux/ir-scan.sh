#!/bin/bash
set -euo pipefail

BASE="/opt/ir"
BASELINE="$BASE/baseline.json"
CURRENT="$BASE/current.json"
CHANGES="$BASE/changes.json"
QUAR="$BASE/quarantine"

mkdir -p "$BASE" "$QUAR"

MODE=""
REMEDIATE=false

[[ "${1:-}" == "--baseline" ]] && MODE="baseline"
[[ "${1:-}" == "--scan" ]] && MODE="scan"
[[ "${2:-}" == "--remediate" ]] && REMEDIATE=true

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 --baseline | --scan [--remediate]"
  exit 1
fi

echo "[*] Collecting inventory..."

# -------------------------
# INVENTORY COLLECTION
# -------------------------
sudo apt install -y jq
inventory=$(jq -n \
  --arg host "$(hostname)" \
  --arg time "$(date -Is)" \
  --argjson services "$(systemctl list-unit-files --type=service --no-pager | awk '{print $1}' | jq -R . | jq -s .)" \
  --argjson running_services "$(systemctl list-units --type=service --state=running --no-pager | awk '{print $1}' | jq -R . | jq -s .)" \
  --argjson cron_system "$(ls -R /etc/cron* 2>/dev/null | jq -R . | jq -s .)" \
  --argjson cron_users "$(for u in $(cut -f1 -d: /etc/passwd); do crontab -u $u -l 2>/dev/null | sed "s/^/$u: /"; done | jq -R . | jq -s .)" \
  --argjson suid "$(find / -perm -4000 -type f 2>/dev/null | jq -R . | jq -s .)" \
  --argjson users "$(cut -d: -f1 /etc/passwd | jq -R . | jq -s .)" \
  --argjson ssh_keys "$(find /home -name authorized_keys 2>/dev/null | xargs -I{} sh -c 'echo {}; cat {}' | jq -R . | jq -s .)" \
  --argjson net "$(ss -tulpn | jq -R . | jq -s .)" \
  '{
    meta: { hostname: $host, timestamp: $time },
    services: $services,
    running_services: $running_services,
    cron_system: $cron_system,
    cron_users: $cron_users,
    suid_files: $suid,
    users: $users,
    ssh_keys: $ssh_keys,
    network: $net
  }')

echo "$inventory" > "$CURRENT"

# -------------------------
# BASELINE MODE
# -------------------------
if [[ "$MODE" == "baseline" ]]; then
  cp "$CURRENT" "$BASELINE"
  echo "[+] Baseline created at $BASELINE"
  exit 0
fi

# -------------------------
# DIFF
# -------------------------
echo "[*] Comparing to baseline..."

jq -n \
  --argfile base "$BASELINE" \
  --argfile cur "$CURRENT" \
  '{
    services_added: ($cur.services - $base.services),
    running_services_added: ($cur.running_services - $base.running_services),
    suid_added: ($cur.suid_files - $base.suid_files),
    users_added: ($cur.users - $base.users),
    ssh_keys_added: ($cur.ssh_keys - $base.ssh_keys)
  }' > "$CHANGES"

echo "[+] Changes written to $CHANGES"

# -------------------------
# REMEDIATION
# -------------------------
if [[ "$REMEDIATE" == true ]]; then
  echo "[!] REMEDIATION ENABLED"

  # Disable new services
  jq -r '.services_added[]?' "$CHANGES" | while read svc; do
    echo "[!] Disabling service $svc"
    systemctl disable "$svc" --now 2>/dev/null || true
  done

  # Remove SUID bit
  jq -r '.suid_added[]?' "$CHANGES" | while read file; do
    echo "[!] Removing SUID bit from $file"
    chmod u-s "$file" || true
  done

  # Lock new users
  jq -r '.users_added[]?' "$CHANGES" | while read usr; do
    echo "[!] Locking user $usr"
    passwd -l "$usr" || true
  done

  # Quarantine SSH keys
  jq -r '.ssh_keys_added[]?' "$CHANGES" | while read key; do
    echo "[!] Quarantining SSH key"
    echo "$key" >> "$QUAR/ssh_keys.quarantine"
  done

  echo "[+] Remediation complete"
fi

echo "[✔] Done"

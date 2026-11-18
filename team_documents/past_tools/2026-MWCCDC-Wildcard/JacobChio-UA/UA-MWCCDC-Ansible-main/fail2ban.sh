#!/bin/bash
set -euo pipefail

LOG="/root/ecom_hardening_$(date +%F_%H-%M).log"
exec > >(tee -a "$LOG") 2>&1

TEAM_NET="172.25.28.0/24"
echo "[+] Starting Ecom hardening for Ubuntu 24.04 - $(date)"
echo "[+] Log: $LOG"

# 1. Backup
BACKUP_DIR="/root/backup_$(date +%F_%H-%M-%S)"
mkdir -p "$BACKUP_DIR"/{etc,web}
rsync -a --exclude={lost+found,*.lock,*.pid} /etc/ "$BACKUP_DIR/etc/"
[ -d /var/www ] && rsync -a /var/www/ "$BACKUP_DIR/web/"

# 2. SSH (safe, no password auth unless needed)
SSHD="/etc/ssh/sshd_config"
cp "$SSHD" "$SSHD.bak.$(date +%s)"
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD"
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD"
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$SSHD"
sed -i 's/^#*LoginGraceTime.*/LoginGraceTime 30/' "$SSHD"
sshd -t && systemctl restart sshd || { echo "[!] SSH config invalid"; exit 1; }

# 3. UFW (additive, no reset)
if ! ufw status | grep -q "Status: active"; then
    ufw --force enable
fi
ufw allow from "$TEAM_NET" to any port 22 proto tcp comment "Team SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw reload
ufw status verbose

# 4. Fail2ban
apt install -y fail2ban
cat <<EOF > /etc/fail2ban/jail.d/ecom.local
[DEFAULT]
ignoreip = 127.0.0.1/8 $TEAM_NET
bantime  = 15m
findtime = 10m
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[apache-auth]
enabled = true
EOF
systemctl restart fail2ban
systemctl enable fail2ban

# 5. Updates (safe)
apt update -y
apt upgrade --no-install-recommends -y

# 6. Service reload (not restart)
for svc in apache2 nginx php*-fpm mariadb mysql; do
    systemctl is-active --quiet "$svc" && systemctl reload "$svc" || true
done

# 7. Webshell hunt (quiet, targeted)
echo "[+] Webshell hunt (quick)"
find /var/www -type f -name "*.php" -o -name "*.phtml" -o -name "*.php[0-9]" \
    -exec grep -ilE "eval|base64_decode|exec|system|passthru|shell_exec|assert" {} \; -ls 2>/dev/null

# 8. Final checks
echo "[+] Listening ports:"
ss -tulpn
echo "[+] Recent auth.log:"
tail -n 30 /var/log/auth.log

echo -e "\n\e[38;5;82m[+] Hardening complete. Review $LOG\e[0m"

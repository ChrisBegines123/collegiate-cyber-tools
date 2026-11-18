#!/bin/bash
set -euo pipefail

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root!"
  exit 1
fi

# -------------------------------
# 1. Change Passwords
# -------------------------------
NEW_PASSWORD="example-password"

# Change the root password
echo "Changing root password..."
echo "root:$NEW_PASSWORD" | chpasswd && echo "✅ Root password changed." || { echo "❌ Failed to change root password."; exit 1; }

# Change sysadmin password if the user exists
if id "sysadmin" &>/dev/null; then
  echo "Changing sysadmin password..."
  echo "sysadmin:$NEW_PASSWORD" | chpasswd && echo "✅ Sysadmin password changed." || echo "❌ Failed to change sysadmin password."
else
  echo "⚠️ User 'sysadmin' does not exist. Skipping."
fi

echo "🎉 Password change complete!"

# -------------------------------
# 2. Environment Checks & Service Management
# -------------------------------
echo "🔄 Checking environment on MWCCDC Debian machine..."

# Stop SSH service if running
if systemctl is-active --quiet ssh; then
  systemctl stop ssh
  if systemctl is-active --quiet ssh; then
    echo "❌ Failed to stop SSH!"
  else
    echo "✅ SSH service stopped."
  fi
else
  echo "⚠️ SSH service not running. Skipping."
fi

# Backup BIND directory if it exists
if [[ -d "/etc/bind" ]]; then
  BACKUP_DIR="/root/backit"
  TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
  BACKUP_DEST="$BACKUP_DIR/bind_backup_$TIMESTAMP"
  mkdir -p "$BACKUP_DIR"
  cp -r /etc/bind "$BACKUP_DEST"
  if [[ -d "$BACKUP_DEST" ]]; then
    echo "✅ BIND backup successful: $BACKUP_DEST"
  else
    echo "❌ BIND backup failed!"
  fi
else
  echo "⚠️ /etc/bind not found. Skipping backup."
fi

# -------------------------------
# 3. Add Login Notification
# -------------------------------
if command -v wall &>/dev/null; then
  LOGIN_WALL_SCRIPT="/etc/profile.d/login_wall.sh"
  cat <<'EOF' > "$LOGIN_WALL_SCRIPT"
#!/bin/bash
if [ -n "${SSH_CLIENT:-}" ]; then
  IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
  wall "$(id -un) logged in from $IP"
fi
EOF
  chmod +x "$LOGIN_WALL_SCRIPT"
  echo "✅ Login notification configured in $LOGIN_WALL_SCRIPT"
else
  echo "⚠️ 'wall' command not found. Skipping login notification."
fi

# -------------------------------
# 4. Fix Package Repository Issues
# -------------------------------
echo "🔄 Fixing package repository issues..."

# Add missing GPG keys (note: apt-key is deprecated in newer systems)
if ! apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 71DAEAA8A4D4CAB6 4F4EA0AAE5267A6C; then
  wget -qO - "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x71DAEAA8A4D4CAB6" | apt-key add -
  wget -qO - "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x4F4EA0AAE5267A6C" | apt-key add -
fi

# Disable problematic repositories if they exist
sed -i 's/^\(deb\)/#\1/' /etc/apt/sources.list.d/sury-php.list 2>/dev/null || true
sed -i 's/^\(deb\)/#\1/' /etc/apt/sources.list.d/ondrej-php.list 2>/dev/null || true

# Update package lists
apt update

# -------------------------------
# 5. Reinstall & Configure UFW
# -------------------------------
echo "🚨 Forcefully reinstalling UFW..."
apt-get remove --purge -y ufw
apt-get update
apt-get install -y ufw

if command -v ufw &>/dev/null; then
  echo "✅ UFW installed."
else
  echo "❌ UFW installation failed. Exiting..."
  exit 1
fi

echo "🔒 Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 53/udp      # DNS
ufw allow 53/tcp      # DNS over TCP
ufw allow 123/udp     # NTP
ufw allow 55460/tcp      # SSH
ufw allow proto udp from any to any port 53
ufw allow proto tcp from any to any port 53
ufw allow proto udp from any to any port 123
ufw allow proto tcp from any to any port 55460
ufw --force enable
echo "✅ UFW firewall configuration complete!"

# -------------------------------
# 6. Reinstall & Configure Fail2Ban
# -------------------------------
echo "🔥 Reinstalling Fail2Ban..."
apt remove --purge -y fail2ban
rm -rf /etc/fail2ban /var/lib/fail2ban
apt update && apt install -y fail2ban

if command -v fail2ban-client &>/dev/null; then
  echo "✅ Fail2Ban installed."
else
  echo "❌ Fail2Ban installation failed!"
  exit 1
fi

systemctl enable --now fail2ban

# Create jail.local if it doesn't exist and configure SSH protection
if [[ ! -f /etc/fail2ban/jail.local ]]; then
  cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi

cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
logtarget = /var/log/fail2ban.log

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
EOF

systemctl restart fail2ban
fail2ban-client status sshd
echo "✅ Fail2Ban configuration complete!"

# -------------------------------
# 7. Reinstall & Run Lynis
# -------------------------------
echo "🔥 Reinstalling Lynis..."
apt remove --purge -y lynis
rm -rf /var/log/lynis /etc/lynis
apt update && apt install -y lynis

echo "🔍 Running initial Lynis security audit..."
lynis audit system --quick | tee /var/log/lynis_audit.log
echo "✅ Lynis installation complete!"
echo "📊 Audit report saved at: /var/log/lynis_audit.log"

echo "🎉 Script execution complete!"

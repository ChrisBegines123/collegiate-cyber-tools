#!/bin/bash

# Variables
ROOT_PASSWORD=""              # Replace with the new root password
SYSADMIN_PASSWORD=""      # Replace with the new sysadmin password
PRESTASHOPUSER_PASSWORD="" # Replace with the new PrestaShop user password
COOKIE_VALUE="INLUuxkWHDX9k7jE6Q7rs3gvWzPQWw8z77sufKkTIzjz2QR4e3RodgYO"                    # Replace with cookie value
NEW_ADMIN_PASSWORD=""        # Replace with the new admin portal password
ADMIN_EMAIL="greg@presta.local"          # Replace with the admin email
#ALLOWED_SSH_IP="172.20.242.12"                # Replace with the IP allowed for SSH
       # Apache configuration file
PRESTASHOP_CONF="/var/www/html/prestashop/config/settings.inc.php" # Replace with the actual path



# Update MySQL root and PrestaShop user's password
echo "Updating MySQL root and PrestaShop user passwords..."
sudo mysql -u root -p <<EOF
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$ROOT_PASSWORD');
SET PASSWORD FOR 'root'@'dareduck' = PASSWORD('$PRESTASHOPUSER_PASSWORD');
SET PASSWORD FOR 'root'@'127.0.0.1' = PASSWORD('$PRESTASHOPUSER_PASSWORD');
SET PASSWORD FOR '::1' = PASSWORD('$PRESTASHOPUSER_PASSWORD');
FLUSH PRIVILEGES;
EOF

# Update PrestaShop configuration file
echo "Updating PrestaShop configuration file..."
sudo sed -i "s/define('_DB_PASSWD_', .*/define('_DB_PASSWD_', '$PRESTASHOPUSER_PASSWORD');/g" $PRESTASHOP_CONF

#

# Restart services
echo "Restarting MariaDB and Apache..."
sudo systemctl restart mariadb httpd

# Update PrestaShop admin portal password
echo "Updating PrestaShop admin portal password..."

sudo mysql -u root -p$ROOT_PASSWORD <<EOF
USE prestashop;
UPDATE ps_employee SET passwd=MD5('$COOKIE_VALUE$NEW_ADMIN_PASSWORD') WHERE email='$ADMIN_EMAIL';
EOF

# Configure firewalld
echo "Configuring firewalld..."
sudo firewall-cmd --set-default-zone=drop
sudo firewall-cmd --permanent --add-port=80/tcp
#sudo firewall-cmd --permanent --add-port=443/tcp
#sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ALLOWED_SSH_IP' port port=22 protocol=tcp accept"
sudo firewall-cmd --reload

echo "Configuration completed successfully."

# Disable root SSH login
sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Check for existing crontabs
echo "Checking for existing crontabs for all users..."
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -u "$user" -l 2>/dev/null | grep -v "^#" | grep -q . && echo "Crontab entries found for user: $user"
done
echo "Crontab check completed."

echo "Checking root user's crontab..."
crontab -l 2>/dev/null | grep -v "^#" | grep -q . && echo "Root user has crontab entries." || echo "No crontab entries for root user."

echo "Crontab check completed."

# Restrict crontab usage
echo "root" | sudo tee -a /etc/cron.allow
sudo touch /etc/cron.deny && sudo chmod 600 /etc/cron.deny

# Enforce Strong Password Policy
echo "Enforcing strong password policy..."
echo "minlen = 12" | sudo tee -a /etc/security/pwquality.conf
echo "dcredit = -1" | sudo tee -a /etc/security/pwquality.conf
echo "ucredit = -1" | sudo tee -a /etc/security/pwquality.conf
echo "lcredit = -1" | sudo tee -a /etc/security/pwquality.conf
echo "ocredit = -1" | sudo tee -a /etc/security/pwquality.conf

echo "Password policy enforcement completed."

# List all system users
echo "Listing all system users..."
cut -d: -f1 /etc/passwd

# List running services
systemctl list-units --type=service --state=running

#!/bin/bash

# Variables

BACKUP_FILE="prestashop.zip"           # Backup file name
SQL_DUMP_FILE="prestashop_bk.sql"      # SQL dump file name
APACHE_DOC_ROOT="/var/www/html"
IP_ADDRESS="172.20.241.0"           # Replace with Fedora IP 
DB_NAME="prestashop"
DB_USER="root"
DB_PASSWORD=""

# Step 1: Navigate to user's home directory
cd ~




# Step 4: Start and enable services
sudo systemctl start httpd mariadb
sudo systemctl enable httpd mariadb

# Step 5: Unzip PrestaShop files
unzip "$BACKUP_FILE" -d prestashop

# Step 6: Set ownership and permissions
sudo chown -R apache: ./prestashop/
sudo chmod -R 755 ./prestashop/

# Step 7: Move files to Apache document root
sudo mv -f ./prestashop/* "$APACHE_DOC_ROOT/"

# Step 8: Configure MariaDB
sudo mysql -u root -p <<EOF
CREATE DATABASE $DB_NAME;
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD' WITH GRANT OPTION;
FLUSH PRIVILEGES;
USE $DB_NAME;
SOURCE ~/$SQL_DUMP_FILE;
UPDATE ps_configuration SET value='$IP_ADDRESS' WHERE name='PS_SHOP_DOMAIN';
UPDATE ps_configuration SET value='$IP_ADDRESS' WHERE name='PS_SHOP_DOMAIN_SSL';
UPDATE ps_shop_url SET domain='$IP_ADDRESS', domain_ssl='$IP_ADDRESS';
EOF

# Step 9: Adjust security settings
sudo setenforce 0
sudo systemctl stop firewalld
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -F
sudo iptables -X

# Step 10: Restart services
sudo systemctl restart httpd mariadb

echo "PrestaShop restoration completed successfully."

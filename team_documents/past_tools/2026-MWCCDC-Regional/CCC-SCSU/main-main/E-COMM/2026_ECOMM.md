# Ecommerce Role Playbook
OS: Ubuntu 24 Server
Firewall: UFW
Service: Ecommerce (OpenCart expected)

------------------------------------------------------------
GIT / REPOSITORY NOTES
------------------------------------------------------------

curl will not be an option; we must use git. The reason is that the file for the forwarders exceeds the standard 25 MB limit for uploading to our repo. This was worked around using Git LFS, so files uploaded with LFS can only be retrieved with LFS itself.

Install git first.

Linux:
sudo apt update
sudo apt install git -y

Windows:
winget install --id Git.Git -e --source winget

Open a new terminal afterwards.

Git / LFS setup:

git lfs install
git clone --filter=blob:none --no-checkout https://github.com/CCC-SCSU/main.git
cd main
git sparse-checkout init --no-cone


------------------------------------------------------------
FIRST STEPS (INITIAL TRIAGE)
------------------------------------------------------------

Check the webpage locally:
curl localhost

Change passwords:
sudo passwd [username]
sudo passwd root
sudo passwd sysadmin

Check users with shells:
cat /etc/passwd | grep bash

Lock unnecessary accounts:
sudo passwd -l [username]

Change accounts to no login:
sudo usermod -s /usr/sbin/nologin [username]

Backup web root:
sudo cp -R /var/www/html /opt/html.BAK.1

------------------------------------------------------------
MYSQL PASSWORD CHANGE (LOCAL HOST)
------------------------------------------------------------

Login to MySQL locally:
sudo mysql

Run:
ALTER USER 'root'@'localhost' IDENTIFIED BY '[new password]';
FLUSH PRIVILEGES;

Verify login:
mysql -u root -p


------------------------------------------------------------
SERVICE / PROCESS TRIAGE
------------------------------------------------------------

Find enabled services:
systemctl list-unit-files --type=service | grep enabled

Disable unnecessary services:
sudo systemctl disable service_name

Remove packages if needed:
sudo apt remove packagename

Check active connections:
sudo netstat -plant
sudo netstat -planu

Check cron jobs:
crontab -l
crontab -u [user] -l

View processes:
top
ps aux

Kill malicious processes:
kill -9 [pid]

Required ports open:
80
443


------------------------------------------------------------
APACHE CONFIGURATION (UBUNTU)
------------------------------------------------------------

Apache user on Ubuntu:
www-data

Important paths:
/etc/apache2/apache2.conf
/etc/apache2/sites-enabled/

Enable important modules:
sudo a2enmod rewrite
sudo a2enmod headers

Restart apache:
sudo systemctl restart apache2

Correct ownership of web files:
sudo chown -R www-data:www-data /var/www/html

Apache hardening directives (add to apache2.conf or site config):

ServerSignature Off
TraceEnable Off
ServerTokens Prod
Header set X-XSS-Protection "1; mode=block"
Header set X-Frame-Options "SAMEORIGIN"


Disable directory indexing globally:
Options -Indexes


------------------------------------------------------------
OPENCART SPECIFIC HARDENING
------------------------------------------------------------

Rename admin folder (obfuscation):

1. Generate random string
2. Rename /var/www/html/admin to random string
3. Update admin/config.php
4. Update root config.php

Example change:

define('HTTP_SERVER', 'http://yourdomain.com/admin/');

becomes:

define('HTTP_SERVER', 'http://yourdomain.com/awlkegfnbt34o2rjewfsd/');

Note: admin/config.php usually contains 3-5 references to admin/.


------------------------------------------------------------
ADMIN PANEL ACCESS CONTROL
------------------------------------------------------------

Create .htaccess inside admin directory:

Order Deny,Allow
Deny from all
Allow from [update IP once team topology is known]


------------------------------------------------------------
OPENCART CONFIG CHECK (COMMON BREAKAGE)
------------------------------------------------------------

If the site loads but shows a wall of text or missing images, check:

config.php
admin/config.php

Verify:

define('HTTP_SERVER', 'http://PUBLIC_IP/');
define('HTTPS_SERVER', 'https://PUBLIC_IP/');

Also check:

Apache rewrite
file permissions
DNS/IP mapping


------------------------------------------------------------
APACHE REWRITE FIX
------------------------------------------------------------

If .htaccess exists but rewrite module is disabled:

sudo a2enmod rewrite
sudo systemctl restart apache2


------------------------------------------------------------
UPLOAD EXPLOIT PROTECTION
------------------------------------------------------------

OpenCart often allows malicious uploads through extensions.

Add .htaccess to these directories:

/image/
/system/storage/
/upload/

Rules:

<FilesMatch "\.php$">
deny from all
</FilesMatch>


------------------------------------------------------------
PATH TRAVERSAL MITIGATION
------------------------------------------------------------

Add to Apache config:

<Directory /var/www/html>
AllowOverride None
Options -Indexes
</Directory>


------------------------------------------------------------
PHP HARDENING
------------------------------------------------------------

Edit php.ini and confirm:

session.cookie_httponly = 1
session.cookie_secure = 1

If time allows, update PHP to the newest version supported by the installed OpenCart version.


------------------------------------------------------------
DISABLE TEMPLATE EDITOR (RCE RISK)
------------------------------------------------------------

Inside OpenCart admin panel:

System -> Settings -> Server

Set:
Allow Template Editing = OFF


------------------------------------------------------------
DISABLE UNUSED EXTENSIONS
------------------------------------------------------------

Admin -> Extensions -> Modules

Disable anything not required.


------------------------------------------------------------
OPENCART BACKUP
------------------------------------------------------------

Database backup:

mysqldump -u root -p opencart > /opt/opencart.sql

File backup:

tar -czf /opt/opencart_files.tar.gz /var/www/html


------------------------------------------------------------
LOGGING
------------------------------------------------------------

OpenCart logs attacks in:

system/storage/logs/

Ensure system/storage is NOT web accessible and is outside the web root if possible.


------------------------------------------------------------
DISABLE API IF UNUSED
------------------------------------------------------------

Investigate and disable if unused:

/index.php?route=api/


------------------------------------------------------------
FAIL2BAN FOR APACHE
------------------------------------------------------------

Example jail configuration:

[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log

Verify this does not block the scoring engine.


------------------------------------------------------------
FILE PERMISSIONS
------------------------------------------------------------

OpenCart needs write access only to:

image/
system/storage/
system/cache/
system/logs/

Everything else:

chmod -R 755


------------------------------------------------------------
OPENCART TRIAGE
------------------------------------------------------------

Check site:
curl localhost

Check Apache:
systemctl status apache2

Check logs:
tail -f /var/log/apache2/error.log

Check PHP:
php -v

Check database:
mysql -u root -p
SHOW DATABASES;

Check OpenCart config:
config.php
admin/config.php

Check permissions:
ls -la /var/www/html


------------------------------------------------------------
OPENCART CACHE FIX
------------------------------------------------------------

If Apache/PHP works but site is broken:

rm -rf system/storage/cache/*


------------------------------------------------------------
EMERGENCY / BACKUP ACTIONS
------------------------------------------------------------

If Cockpit exists (remove it):

sudo systemctl stop cockpit.socket
sudo systemctl disable cockpit.socket
sudo systemctl stop cockpit.service
sudo systemctl disable cockpit.service

Possible additional action:

sudo systemctl stop rpcbind.service
sudo systemctl disable rpcbind.service

Last resort (ONLY if AIO script fails):

sudo systemctl stop sshd.service
sudo systemctl disable sshd.service


------------------------------------------------------------
QUICK TRIAGE COMMANDS
------------------------------------------------------------

Open ports:
sudo ss -tulnp

Running services:
sudo systemctl list-units --type=service --state=running

High CPU processes:
ps aux --sort=-%cpu | head

Cron jobs:
sudo crontab -l
sudo ls /etc/cron*

Systemd autostart:
sudo systemctl list-unit-files --state=enabled

SSH keys:
sudo ls -la /root/.ssh /home/*/.ssh

New users:
awk -F: '$3>=1000{print $1}' /etc/passwd

Network connections:
sudo netstat -tampa | grep ESTABLISHED

Suspicious executable files:
find /tmp /dev/shm /var/tmp -type f -perm /111

Recent system changes:
find /etc /bin /usr/bin /sbin -mmin -60


------------------------------------------------------------
DATABASE HARDENING
------------------------------------------------------------

Run:
sudo mysql_secure_installation

Edit:
/etc/mysql/mysql.conf.d/mysqld.cnf

Ensure:

bind-address = 127.0.0.1

Also remove test DB and disallow remote root login.


------------------------------------------------------------
NETWORK DEFENSE
------------------------------------------------------------

Enable firewall:

sudo ufw enable
sudo ufw default deny incoming

Allow required ports:

sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow ssh


------------------------------------------------------------
SSH HARDENING
------------------------------------------------------------

Edit:
/etc/ssh/sshd_config

Set:

PermitRootLogin no


------------------------------------------------------------
USEFUL TOOLS (IF TIME ALLOWS)
------------------------------------------------------------

fail2ban
Nessus
Lynis (runs heavy, use after core hardening)


------------------------------------------------------------
REFERENCE
------------------------------------------------------------

Apache paths:
/etc/apache2/apache2.conf
/etc/apache2/sites-enabled/

Apache commands:

sudo a2enmod rewrite
sudo a2enmod headers
sudo systemctl restart apache2

Apache user:
www-data
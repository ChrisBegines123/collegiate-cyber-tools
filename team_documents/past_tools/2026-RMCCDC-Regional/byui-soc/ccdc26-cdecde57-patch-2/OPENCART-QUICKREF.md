# OpenCart Quick Reference - Ubuntu Ecom Server

**IP:** 172.20.242.30  
**Application:** OpenCart E-Commerce  
**Scored Services:** HTTP (80), HTTPS (443)

---

## 🚨 PRIORITY ACTIONS

### 1. Login to Admin Panel (Minute 5)

**URL:** http://172.20.242.30/admin

**Confirmed Username:** `admin` (verified from database)

**Default Passwords to Try:**
- ☐ `admin` (most common)
- ☐ `password`
- ☐ `demo`
- ☐ `Password123`
- ☐ `changeme`

### 2. Change Admin Password (Minute 6)

1. Login to admin panel
2. Navigate to: **System → Users → Users**
3. Click **Edit** next to admin user
4. Change password to: `[YOUR_TEAM_PASSWORD]`
5. Click **Save**

### 3. Run Hardening Script (Minute 7)

```bash
ssh sysadmin@172.20.242.30
cd /opt/ccdc26/linux-scripts/service-hardening
sudo ./harden-opencart.sh
```

**Script will:**
- Remove `/install` directory
- Rename `/admin` to random name
- Set secure permissions
- Install fail2ban
- Show new admin URL

### 4. Access New Admin Panel

**After hardening, admin URL changes to:**
```
http://172.20.242.30/admin_secure_XXXXX
```
(Script will show the exact URL)

---

## 📂 FILE LOCATIONS

| Item | Path |
|------|------|
| Web Root | `/var/www/html/` |
| Config File | `/var/www/html/config.php` |
| Admin Config | `/var/www/html/admin/config.php` |
| Images/Uploads | `/var/www/html/image/` |
| Storage | `/var/www/html/system/storage/` |
| Apache Config | `/etc/apache2/sites-available/000-default.conf` |
| Access Log | `/var/log/apache2/access.log` |
| Error Log | `/var/log/apache2/error.log` |

---

## 🔑 DATABASE ACCESS

### Confirmed Database Details

**From MySQL inspection:**
- Database name: `opencart`
- Admin table: `oc_user`
- Admin username: `admin`
- Admin email: `admin@example.com`
- Password hashing: **bcrypt** (`$2y$10$...`)

### Find Database Credentials

```bash
sudo grep "DB_" /var/www/html/config.php
```

**Typical output:**
```php
define('DB_HOSTNAME', 'localhost');
define('DB_USERNAME', 'opencart_user');  # May vary
define('DB_PASSWORD', 'password123');    # Current password
define('DB_DATABASE', 'opencart');        # Confirmed
```

### Change Database Password

```bash
# Login to MySQL
sudo mysql -u root -p

# Change password
ALTER USER 'opencart_user'@'localhost' IDENTIFIED BY 'NewStrongP@ss!';
FLUSH PRIVILEGES;
EXIT;

# Update config file
sudo nano /var/www/html/config.php
# Change: define('DB_PASSWORD', 'NewStrongP@ss!');
```

---

## 🔒 MANUAL HARDENING STEPS

### Remove Install Directory

```bash
sudo rm -rf /var/www/html/install/
```

### Rename Admin Directory

```bash
sudo mv /var/www/html/admin /var/www/html/admin_secure_12345

# Update config
sudo nano /var/www/html/config.php
# Change: define('HTTP_ADMIN', 'http://yourdomain.com/admin_secure_12345/');
```

### Set Secure Permissions

```bash
# Make everything read-only except uploads
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;

# Config files
sudo chmod 644 /var/www/html/config.php
sudo chmod 644 /var/www/html/admin*/config.php

# Upload directories (writable)
sudo chmod -R 777 /var/www/html/image/
sudo chmod -R 777 /var/www/html/system/storage/

# Set ownership
sudo chown -R www-data:www-data /var/www/html/
```

---

## 🔍 MONITORING COMMANDS

### Watch Admin Login Attempts

```bash
# Real-time monitoring
sudo tail -f /var/log/apache2/access.log | grep -i "admin"

# Count failed logins
sudo grep "POST.*admin.*login" /var/log/apache2/access.log | wc -l

# Find attacking IPs
sudo grep "POST.*admin.*login" /var/log/apache2/access.log | \
  awk '{print $1}' | sort | uniq -c | sort -rn | head -10
```

### Check for SQL Injection Attempts

```bash
sudo grep -iE "union.*select|concat\(|0x[0-9a-f]" /var/log/apache2/access.log
```

### Check for Suspicious Files

```bash
# Find PHP files with dangerous functions
sudo find /var/www/html -type f -name "*.php" \
  -exec grep -l "eval\|base64_decode\|system\|exec" {} \;

# Recently modified files (last 10 minutes)
sudo find /var/www/html -type f -mmin -10 -ls
```

### Monitor Apache Status

```bash
# Check Apache is running
sudo systemctl status apache2

# Active connections
sudo netstat -tuln | grep :80

# Apache processes
sudo ps aux | grep apache2
```

---

## 🚫 BLOCK ATTACKING IPs

### Using UFW

```bash
# Block single IP
sudo ufw deny from <attacking_ip>

# Block IP range
sudo ufw deny from <attacking_ip>/24
```

### Using iptables

```bash
# Block IP
sudo iptables -A INPUT -s <attacking_ip> -j DROP

# Save rules
sudo iptables-save > /etc/iptables/rules.v4
```

### Using fail2ban

```bash
# Check jail status
sudo fail2ban-client status opencart-admin

# Ban IP manually
sudo fail2ban-client set opencart-admin banip <ip>

# Unban IP
sudo fail2ban-client set opencart-admin unbanip <ip>
```

---

## 🩺 HEALTH CHECKS

### Test Scored Service

```bash
# From another machine
curl http://172.20.242.30
curl -k https://172.20.242.30

# Should return HTML (not error)
```

### Check Apache Errors

```bash
sudo tail -50 /var/log/apache2/error.log
```

### Restart Apache (if needed)

```bash
# Check config first
sudo apache2ctl configtest

# Restart
sudo systemctl restart apache2

# Check status
sudo systemctl status apache2
```

---

## 🛡️ IN-ADMIN SECURITY SETTINGS

### After Logging In

1. **System → Settings → Store**
   - Enable SSL if certificate available

2. **System → Users → User Groups**
   - Review admin group permissions
   - Remove unnecessary permissions

3. **Extensions → Extensions**
   - **Type:** Modules
   - Disable any unfamiliar extensions

4. **Extensions → Modifications**
   - Review for suspicious modifications
   - Disable suspicious ones

5. **System → Maintenance**
   - Review error logs within admin panel

---

## 🆘 EMERGENCY PROCEDURES

### Admin Panel Locked Out

**Reset password via MySQL (bcrypt hashing):**

**IMPORTANT: OpenCart uses bcrypt, NOT MD5**

```bash
# Quick one-liner password reset using PHP
sudo mysql -u root -p opencart -e "UPDATE oc_user SET password = '$(php -r "echo password_hash('YourNewPassword', PASSWORD_BCRYPT);")' WHERE username = 'admin';"

# OR step-by-step:
sudo mysql -u root -p

USE opencart;

# View current admin user
SELECT user_id, username, email FROM oc_user;
# Should show: admin, admin@example.com

# Generate bcrypt hash using PHP
# Exit MySQL first with: EXIT;
php -r "echo password_hash('YourNewTeamPassword', PASSWORD_BCRYPT) . PHP_EOL;"

# Copy the generated hash, then back to MySQL:
sudo mysql -u root -p opencart

UPDATE oc_user SET password = '$2y$10$YOUR_GENERATED_HASH_HERE' 
WHERE username = 'admin';

EXIT;
```

**Alternative using Python:**

```bash
# Generate hash with Python
python3 -c "import bcrypt; print(bcrypt.hashpw(b'YourNewPassword', bcrypt.gensalt(rounds=10)).decode())"

# Then update in MySQL with the generated hash
```

### Apache Won't Start

```bash
# Check config syntax
sudo apache2ctl configtest

# Check what's using port 80
sudo netstat -tuln | grep :80
sudo lsof -i :80

# Check error log
sudo tail -100 /var/log/apache2/error.log

# Try starting manually
sudo /usr/sbin/apache2ctl start
```

### Website Returns 500 Error

```bash
# Check Apache error log
sudo tail -50 /var/log/apache2/error.log

# Check file permissions
ls -la /var/www/html/

# Check database connectivity
sudo mysql -u opencart_user -p opencart -e "SELECT 1;"
```

### Stylesheet Not Loading / Connection Errors

**Symptoms:**
- Stylesheets not loading
- NS_ERROR_CONNECTION errors
- Admin panel won't load
- Blank or unstyled pages

**Quick Fix:**

```bash
# Run automated fix script
cd /opt/ccdc26/linux-scripts/service-hardening
sudo ./fix-opencart-errors.sh
```

**Manual Troubleshooting:**

```bash
# 1. Check Apache is running
sudo systemctl status apache2
sudo systemctl restart apache2

# 2. Check Apache config
sudo apache2ctl configtest

# 3. Enable required modules
sudo a2enmod rewrite headers
sudo systemctl restart apache2

# 4. Fix file permissions
sudo chown -R www-data:www-data /var/www/html
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;
sudo chmod -R 777 /var/www/html/image/
sudo chmod -R 777 /var/www/html/system/storage/

# 5. Check Apache is listening
sudo netstat -tuln | grep :80
sudo lsof -i :80

# 6. Test from localhost
curl -I http://localhost/
curl http://localhost/ | head -20

# 7. Check error logs
sudo tail -50 /var/log/apache2/error.log
sudo tail -50 /var/log/apache2/access.log
```

**Check config.php URLs:**

```bash
sudo grep "HTTP_SERVER" /var/www/html/config.php

# Should match server IP:
# define('HTTP_SERVER', 'http://172.20.242.30/');

# If wrong, edit:
sudo nano /var/www/html/config.php
```

**Enable .htaccess support:**

```bash
sudo nano /etc/apache2/sites-available/000-default.conf

# Add inside <VirtualHost>:
<Directory /var/www/html>
    AllowOverride All
    Require all granted
</Directory>

# Restart Apache
sudo systemctl restart apache2
```

---

## 📋 CHECKLIST

### Initial Setup (Minute 5-10)
- ☐ Login to admin panel with default credentials
- ☐ Change admin password to team password
- ☐ Run `/opt/ccdc26/linux-scripts/service-hardening/harden-opencart.sh`
- ☐ Document new admin URL
- ☐ Remove install directory (`/var/www/html/install/`)
- ☐ Change database password
- ☐ Update config.php with new DB password
- ☐ Review and disable suspicious extensions

### Every 10 Minutes
- ☐ Check Apache logs for brute force attempts
- ☐ Verify Apache is running: `systemctl status apache2`
- ☐ Test scored service: `curl http://172.20.242.30`
- ☐ Check fail2ban status: `fail2ban-client status opencart-admin`

### If Under Attack
- ☐ Identify attacking IPs from Apache logs
- ☐ Block IPs with UFW or iptables
- ☐ Increase fail2ban sensitivity (decrease maxretry)
- ☐ Temporarily rename admin directory again
- ☐ Add ModSecurity WAF rules if time permits

---

## 🔗 RELATED DOCUMENTATION

- Competition quick reference: `QUICKREF.md`
- Hardening script: `linux-scripts/service-hardening/harden-opencart.sh`
- Main documentation: `README.md`

---

**Keep this file open during competition for quick reference!**

**Last Updated:** January 21, 2026

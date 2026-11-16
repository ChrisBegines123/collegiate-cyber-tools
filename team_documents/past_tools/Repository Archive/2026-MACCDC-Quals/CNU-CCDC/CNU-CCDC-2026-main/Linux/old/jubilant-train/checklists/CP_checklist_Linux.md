## Linux
1. Update system
  - `apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y`
2. Install and run clamtk
  - `apt-get install clamtk`
  - `freshclam`
3. Set up automatic updates
  - System Settings > Software and Updates > Updates
    - Automatically check for updates
    - Important security updates
4. Search for all prohibited files
  - `find / -name "*.{extension}" -type f`
5. Configure a firewall
  - `apt-get install ufw`
  - `ufw enable`
  - `ufw status`
6. Edit the lightdm.conf file
  - `allow-guest=false`
  - `autologin-user=none`
  - `greeter-hide-users=true`
  - `greeter-show-manual-login=true`
  - Ubuntu:
    - Check both /etc/lightdm/lightdm.conf and /usr/share/lightdm/lightdm.conf/50-ubuntu.conf
  - Debian:
    - In /etc/gdm3/greeter.dconf:
      - `disable-user-list=true`
      - `disable-restart-buttons=true`
      - `AutomaticLoginEnable=false`
7. Create any missing users
8. Change all the user passwords to something memorable
9. Edit /etc/login.defs
  - FAILLOG_ENAB YES
  - LOG_UNKFAIL_ENAB YES
  - SYSLOG_SU_ENAB YES
  - SYSLOG_SG_ENAB YES
  - PASS_MAX_DAYS 90
  - PASS_MIN_DAYS 10
  - PASS_WARN_AGE 7
10. Edit /etc/pam.d/common-password
  - Add `ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1` to the line that ends with `difok=3`
11. Delete any unauthorized users
12. Check the /etc/passwd file for:
  - Repeating UID/GIDs
  - Programs with /bin/sh or /bin/bash
  - Users other than root with a UID or GID of 0
13. Check the /etc/group file for:
  - Any extra users in the sudo and adm groups
  - Any missing users from the sudo and adm groups
14. Secure SSH if required
  - /etc/ssh/sshd_config
    - `LoginGraceTime 60`
    - `PermitRootLogin no`
    - `Protocol 2`
    - `PermitEmptyPasswords no`
    - `PasswordAuthentication yes`
    - `X11Fowarding no`
    - `UsePAM yes`
    - `UsePrivilegeSeparation yes`
15.	Secure the /etc/shadow file
  - `chmod 640 /etc/shadow`
  - `chown root:root /etc/shadow`
16. Look for any bad programs
  - `dpkg -l | grep {package}`
    - John the Ripper
    - Hydra
    - Nginx
    - Samba
    - Bind9
    - VSFTPD/FTP
    - TFTPD
    - X11vnc/tightvncserver
    - SNMP
    - Nfs
    - Sendmail/postfix
    - Xinetd
17. If FTP is required, secure /etc/vsftpd.conf
  - anonymous_enable=ON
  - local_enable=YES
  - write_enable=YES
  - chroot_local_user=YES
18. Configure /etc/sysctl.conf
  - `net.ipv4.conf.all.accept_redirects = 0`
  - `net.ipv4.ip_forward = 0`
  - `net.ipv4.conf.all.send_redirects = 0`
  - `net.ipv4.conf.default.send_redirects = 0`
  - `net.ipv4.conf.all.rp_filter=1`
  - `net.ipv4.conf.all.accept_source_route=0`
  - `net.ipv4.tcp_max_syn_backlog = 2048`
  - `net.ipv4.tcp_synack_retries = 2`
  - `net.ipv4.tcp_syn_retries = 5`
  - `net.ipv4.tcp_syncookies = 1`
  - `net.ipv6.conf.all.disable_ipv6 = 1`
  - `net.ipv6.conf.default.disable_ipv6 = 1`
  - `net.ipv6.conf.lo.disable_ipv6 = 1`
19. Check cronjobs/startup scripts
  - /etc/cron.*
  - /etc/crontab
  - /var/spool/cron/crontabs
  - /etc/init
  - /etc/init.d
  - `crontab -u {user} -l`
20. Check sudoers
  - /etc/sudoers
  - /etc/sudoers.d
  - Make sure noting has NOPASSWD permission
21. Check the runlevels if unable to boot into GUI.
  - `runlevel`
    - 0: System halt; No activity
    - 1: Single user
    - 2: Multi-user, no filesystem
    - 3: Multi-user, commandline only
    - 4: user defineable
    - 5: multi-users,GUI
    - 6: Reboot
  - Use `telinit {level}` to set the run level

## Apache
1. Hide Apache version number
  - /etc/apache2/apache2.conf
    - `ServerSignature Off`
    - `ServerTokens Prod`
2. Make sure apache is running under its own user and group.
  - `useradd apache`
  - /etc/apache2/apache2.conf
    - `User apache`
    - `Group apache`
3. Ensure files outside the web root directory are not accessed.
  - /etc/apache2/apache2.conf
    - ```xml
        <Directory />
            Order Deny,Allow
            Dent from all
            Options -Indexes
            AllowOverride None
        </Directory>
        <Directory /html>
            Order Allow,Deny
            Allow from all
        </Directory>
        ```
4. Turn off directory brwosing, follow symbolic links, and CGI execution.
  - Add `Options None` to a `<Directory /html>` tag
5. Install modsecurity
  - `apt-get install mod_security`
  - `service httpd restart`
6. Lower the timeout value in /etc/apache2/apache2.conf
  - `Timeout 45`

## MySQL
1. Restrict remote MySQL access
  - /etc/mysql/my.cnf
    - `Bind-address=127.0.0.1`
2. Disable use of LOCAL INFILE
  - Edit /etc/mysql/my.cnf
    - `[mysqld]` <!-- Not sure what this does tbh -->
    - `local-infile=0`
3. Create application specific user
  - `mysql -u root -p`
  - `CREATE USER 'myuser'@'localhost' IDENTIFIED BY '{password}'`
  - `GRANT SELECT,INSERT,UPDATE,DELETE ON mydb.* TO 'myusr'@'localhost' IDENTIFIED BY '{password}'`
  - `FLUSH PRIVILEGES`
4. Improve security with mysql_secure-installation
  - `mysql_secure-installation`

## PHP
1. Restrict PHP information usage
  - /etc/php5/apache2/php.ini.
    - `expose_php = off`
2. Disable remote code execution
  - /etc/php5/apache2/php.ini
    - `allow_url_fopen = off`
    - `allow_url_include = off`
3. Disable dangerous PHP functions
  - /etc/php5/apache2/php.ini
    - `disable_functions=exec,shell_exec,passthru,system,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,proc_open,pcntl_exec`
4. Enable Limits in PHP
  - /etc/php5/apache2/php.ini
    - `upload_max_filesize = 2M`
    - `max_execution_time = 30`
    - `max_input_time = 60`

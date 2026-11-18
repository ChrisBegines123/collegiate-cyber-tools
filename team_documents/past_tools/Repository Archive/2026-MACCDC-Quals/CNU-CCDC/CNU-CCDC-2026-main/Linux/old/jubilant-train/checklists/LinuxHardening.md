# Ubuntu CyberPatriot Checklist WIP

Basic instructions:  
**ALWAYS** do the forensic questions first!!!  
Helpful forensics site: [CyberChef](https://cyberchef.org/)  
Make machine snapshots consistently  
Do not stop scoring unless the machine is not working properly  
Remember: Ctrl+C/Ctrl+V does not work in terminal.  Use Ctrl+Shift+C/Ctrl+Shift+V  
Change all user accounts to `P@$$W0rd1!`  

## UPGRADE/UPDATE SYSTEM FIRST
```bash
sudo apt-get update && sudo apt-get upgrade -y # One line version
sudo apt-get update # Finds updates in package repositories.  Does not install anything
sudo apt-get upgrade -y # Installs updates in package repositories.  Don't run this until you run apt-get update
sudo apt-get dist-upgrade # Installs updates but also has the ability to install new packages for the updates (it may seem like upgrade does this but it installs dependencies, this can install more)
sudo apt-get autoremove -y # Removes extra dependencies that aren't in use by other packages on your system.
```

## UPDATE AND CONFIGURE FIREFOX SETTINGS  
```bash
firefox --version (To show which version you are running)
sudo apt install firefox
```
Open Firefox and go to "Privacy and Security"  
Standard protection, Turn off "Ask to save logins and passwords"  
Make sure Dangerous and deceptive content is blocked, addons blocked, popups blocked, and delete cookies  
Firefox does not autofill credit card info  

## CHECK USERS AND DISABLE ANY UNAPPROVED USER ACCOUNTS. REMOVE THEM FROM GROUPS ALSO
```bash
sudo nano /etc/passwd
```
comment out/remove any unauthorized accounts by using a "#" Then save by pressing ctrl+x  
```bash
sudo nano /etc/group
```
make sure to remove users from unauthorized groups (especially 'sudo' and 'adm') while you are in /etc/group  

## DISABLE GUEST ACCOUNT  
Instructions to come

## MAKE SURE NO NON-ROOT ACCOUNTS HAVE A UID OR GID OF 0
```bash
echo "Users with UID 0"
awk -F: '($3 == "0") {print}' /etc/passwd # Prints all accounts with a UID of 0
echo "Users with GID 0"
awk -F: '($4 == "0") {print}' /etc/passwd # Prints all accounts with a UID of 0
```

## TURN ON FIREWALL
Basic installation and usage
```bash
sudo apt-get install ufw # Installs UFW
sudo ufw enable # Enables UFW
sudo ufw status # Lists the active firewall rules.
sudo ufw status numbered # Lists the active firewall rules and their numerical IDs
sudo ufw allow ARGS # Adds a new rule to explicitly allow activity in/out from certain IPs/ports (see ufw man pages)
sudo ufw deny ARGS # Adds a new rule to explicitly deny activity in/out from certain IPs/ports (see ufw man pages)
sudo ufw --force reset # Removes all existing UFW rules
sudo ufw default ARGS # Adjusts the firewall's default rules for certain connections
sudo ufw delete RULE|NUM # Deletes an active rule either by full name or numerical ID
```
Some good configs for ufw
```bash
sudo ufw default deny incoming # Tells the firewall to deny incoming connections by default
sudo ufw default allow outgoing # Tells the firewall to allow outgoing connections by default

# Allowing connections on localhost
ufw allow in on lo
ufw allow out on lo

# Denying connections on the local network
ufw deny in from 127.0.0.0/8

# Denying localhost IPv6 connections (Also good practice to just straight up disable IPv6, but that's not a ufw thing)
ufw deny in from ::1
```

## CHECK FOR MALWARE
```bash
sudo apt install clamav -y # Installs clamav
clamscan # Runs the antivirus
```

**USE SUDO INSTEAD OF ROOT!!**
```bash
sudo passwd -l root (disables root account)
```

## --WIP-- CHANGE PASSWORD POLICY (Make a snapshot here.  This section has not been tested.)
```bash
sudo apt-get install libpam-pwquality
sudo nano /etc/pam.d/common-password
```
After pam_unix.so, make sure these settings are listed: "use_authtok sha512 shadow remember=5"  
After pam_pwquality.so, make sure these settings are listed: "retry=3 minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 reject_username enforce_for_root"  

```bash
sudo nano /etc/login.defs
```
Make the following changes:  
- `PASS_MAX_DAYS 45`  
- `PASS_MIN_DAYS 1`  
- `PASS_WARN_AGE 7`  
- `LOGIN_RETRIES 3`  
- `LOGIN_TIMEOUT 30`  
- `ENCRYPT_METHOD SHA512`  

```bash
sudo nano /etc/pam.d/common-auth
```
I have these sed commands that *might* work (i forget) to manage common-auth.  
```bash
sudo sed -i '1i auth required pam_faillock.so preauth silent deny=3 unlock_time=600' /etc/pam.d/common-auth
sudo sed -i '/pam_unix.so/i auth [default=die] pam_faillock.so authfail' /etc/pam.d/common-auth
sudo sed -i '/pam_unix.so/a auth sufficient pam_faillock.so authsucc' /etc/pam.d/common-auth
```

## REMOVE UNAUTHORIZED FILES, PROGRAMS, AND HACKING TOOLS (media files, games, hacking tools, malware)
Use the find command
```bash
sudo find / -type f -name *.<extension> >> found.txt
```
This will find all files with the specified `<extension>` and put their absolute path into a file `found.txt`.  
Make sure to use `>> found.txt` rather than `> found.txt` as `>>` appends to the file while `>` deletes any existing content.  Useful for chaining find commands.  

EX:
```bash
sudo find / -type f -name *.mp3 >> found.txt
```

You can delete files as you find them, but I advise not doing this because you could delete system files.  

## INSTALL LYNIS TO SCAN FOR VUNERABILITIES
```bash
sudo apt install lynis
sudo lynis audit system
```

## INSTALL CHKROOTKIT (checks for rootkits that could be the system)
```bash
sudo apt-get install chkrootkit -y
sudo chkrootkit
```

## REMOVE ANY SUS PORTS
```bash
sudo netstat -plant # Lists active TCP ports.  Monitor for suspicious activity like services that are not listed in a readme.
# TO REMOVE:
sudo kill -9 $pid # Replace $pid with the process ID you see in netstat.
sudo ufw deny $port # Replace $port with the port the malicious server was running on.
sudo ufw delete $rule # A good alternative to `ufw deny`, it removes whatever rule is allowing the port to connect to the internet.
```

## DISABLE SSH ROOT LOGIN
```bash
sudo nano /etc/ssh/sshd_config
```
set "PermitRootlogin no"  
```bash
service ssh restart # Restarts ssh/sshd
```

## DISABLE FTP IF NECCESSARY
```bash
sudo systemctl stop pure-ftpd # Stops the service
sudo systemctl disable pure-ftpd # Disables the service
```
**NOTE: A different ftp server may be installed.**

## CHECK LOG FILES
Below are some common log files to monitor.  
Try using `journalctl -u <service>` to get service-specific logs.  

- /var/log/syslog: System logs for debian-based systems  
- /var/log/message: System logs for non-debian systems  
- /var/log/auth.log: Authentication logs  
- /var/log/kern.log: Kernel logs  
- /var/log/cron.log: cron logs  
- /var/log/maillog: mail server logs  
- /var/log/boot.log: System boot log  
- /var/log/mysqld.log: MySQL database server log file  
- /var/log/secure: Authentication log  
- /var/log/apt/*: Apt package manager logs  

#### These files are in a binary format.  Read them with `sudo last -f <path>`

- /var/log/btmp: Record of failed login attempts. 
- /var/log/utmp: Record of active users.  May not show up on recent versions of ubuntu.
- /var/log/wtmp: Record of past active users.

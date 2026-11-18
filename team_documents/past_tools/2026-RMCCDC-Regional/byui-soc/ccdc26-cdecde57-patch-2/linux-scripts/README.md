# CCDC26 Linux Defense Toolkit

Designed to work across multiple distributions (Debian/Ubuntu, RHEL/CentOS/Fedora, Alpine, Arch).

## Quick Start

```bash
# Make all scripts executable
chmod +x *.sh */*.sh

# Run initial hardening (as root)
sudo ./hardening/full-harden.sh

# Harden all detected services
sudo ./services/harden-all.sh

# Set up fail2ban and security tools
sudo ./tools/fail2ban-setup.sh
sudo ./tools/security-tools.sh

# Set up Splunk forwarder
sudo ./tools/splunk-forwarder.sh quick

# Start monitoring
sudo ./monitoring/deploy-monitoring.sh

# Hunt for persistence
sudo ./persistence-hunting/full-hunt.sh
```

## Directory Structure

```
linux-scripts/
├── hardening/              # System hardening scripts
│   ├── full-harden.sh      # Run all hardening (use first!)
│   ├── users.sh            # User account hardening
│   ├── ssh.sh              # SSH hardening
│   ├── firewall.sh         # Firewall setup
│   ├── services.sh         # Service management
│   ├── permissions.sh      # File permission fixes
│   └── kernel.sh           # Kernel parameter hardening
├── services/               # Service-specific hardening
│   ├── harden-all.sh       # Auto-detect and harden all
│   ├── harden-webserver.sh # Apache/Nginx/PHP
│   ├── harden-database.sh  # MySQL/MariaDB/PostgreSQL
│   ├── harden-mail.sh      # Postfix/Dovecot
│   ├── harden-ftp.sh       # vsftpd/ProFTPD/Pure-FTPd
│   └── harden-dns.sh       # BIND/named
├── tools/                  # Security tools setup
│   ├── fail2ban-setup.sh   # Fail2ban installation & config
│   ├── security-tools.sh   # Auditd, rkhunter, lynis, etc.
│   ├── splunk-forwarder.sh # Splunk forwarder for log collection
│   └── splunk-server.sh    # Splunk server index setup
├── persistence-hunting/    # Find attacker persistence
│   ├── full-hunt.sh        # Run all persistence checks
│   ├── cron-audit.sh       # Cron job analysis
│   ├── service-audit.sh    # Systemd/init service check
│   ├── user-audit.sh       # User/group anomaly detection
│   ├── binary-audit.sh     # SUID/SGID/capability check
│   └── startup-audit.sh    # Boot persistence check
├── monitoring/             # Continuous monitoring
│   ├── deploy-monitoring.sh    # Deploy all monitors
│   ├── file-monitor.sh         # File integrity monitoring
│   ├── process-monitor.sh      # Process monitoring
│   ├── network-monitor.sh      # Connection monitoring
│   └── log-watcher.sh          # Real-time log analysis
├── incident-response/      # IR tools
│   ├── triage.sh           # Quick system triage
│   ├── collect-evidence.sh # Evidence collection
│   ├── kill-session.sh     # Kill attacker sessions
│   ├── isolate.sh          # Network isolation
│   ├── incident_responder.sh # Automatic Incident Responder
│   └── restore-service.sh  # Service recovery
└── utils/                  # Utility functions
    └── common.sh           # Shared functions
```

## Priority Order During Competition

### First 15 Minutes (Critical)
1. `./hardening/users.sh` - Change all passwords, disable unauthorized users
2. `./hardening/ssh.sh` - Secure SSH immediately
3. `./hardening/firewall.sh` - Lock down network access

### Next 30 Minutes (Important)
4. `./services/harden-all.sh` - Harden all detected services
5. `./tools/fail2ban-setup.sh` - Set up intrusion prevention
6. `./tools/splunk-forwarder.sh quick` - Set up log forwarding to Splunk
7. `./persistence-hunting/full-hunt.sh` - Find backdoors
8. `./monitoring/deploy-monitoring.sh` - Start monitoring

### Ongoing
- Monitor alerts from `./monitoring/`
- Setup `./incident-response/incident_responder.sh` to monitor network traffic
- Re-run persistence hunting periodically
- Use IR tools as needed

## Service Hardening

The toolkit can automatically detect and harden:
- **Web Servers**: Apache, Nginx, PHP
- **Databases**: MySQL, MariaDB, PostgreSQL
- **Mail**: Postfix, Dovecot
- **FTP**: vsftpd, ProFTPD, Pure-FTPd
- **DNS**: BIND/named

Run `./services/harden-all.sh` to auto-detect and secure all services.

## Security Tools Included

- **fail2ban**: Intrusion prevention (brute force protection)
- **auditd**: System auditing and logging
- **rkhunter**: Rootkit detection
- **chkrootkit**: Rootkit detection
- **lynis**: Security auditing
- **ClamAV**: Antivirus scanning
- **Splunk Forwarder**: Log forwarding to competition Splunk server

## SIEM Integration

### Splunk Forwarder

The competition has an existing Splunk server at **172.20.242.20** (Oracle Linux 9.2). All logs are forwarded there.

### Forwarder Setup (on client machines)

```bash
# Quick setup - forwards all logs to competition Splunk
sudo ./tools/splunk-forwarder.sh quick
```

### Server Setup (on 172.20.242.20)

```bash
# Create indexes and enable receiver port
sudo ./tools/splunk-server.sh quick
```

### Indexes

Logs are organized into these indexes:
- `linux-security` - auth.log, secure, audit.log, fail2ban
- `linux-os` - syslog, messages, kern.log, cron
- `linux-web` - apache, nginx logs
- `linux-database` - mysql, mariadb, postgresql
- `linux-mail` - mail.log, maillog
- `linux-dns` - named, bind logs
- `linux-ftp` - vsftpd, proftpd logs

## Distro Detection

All scripts automatically detect the distribution and use appropriate commands:
- **Debian/Ubuntu**: apt, ufw, systemd
- **RHEL/CentOS/Fedora**: dnf/yum, firewalld, systemd
- **Alpine**: apk, iptables, openrc
- **Arch**: pacman, iptables, systemd

## Important Notes

- Always run as root or with sudo
- Backup configs before changes: scripts create `.bak` files
- Review output carefully - don't blindly trust automated changes
- Keep terminal open with monitoring running
- Document everything for scoring

## Author
Brady Hodge

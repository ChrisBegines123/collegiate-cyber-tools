<img width="440" height="68" alt="image" src="https://github.com/user-attachments/assets/07e35ba9-b98d-4ddf-b178-5dbed06bc89a" /># CCDC26 Quick Reference

**Team 2 (BYU)** | **Date:** Jan 24, 2026 | **Drop Flag:** 9am MST

---

## CREDENTIALS

### Linux (172.20.242.0/24 - behind Palo Alto)

| Machine | IP | User | Password | Scored Services |
|---------|-----|------|----------|-----------------|
| Ubuntu Ecom | 172.20.242.30 | sysadmin | changeme | HTTP |
| Fedora Webmail | 172.20.242.40 | sysadmin | changeme | SMTP, POP3 |
| Splunk | 172.20.242.20 | root | changemenow | - |
| Ubuntu Wks | **DHCP** | sysadmin | changeme | - |

### Windows (172.20.240.0/24 - behind Cisco FTD)

| Machine | IP | User | Password | Scored Services |
|---------|-----|------|----------|-----------------|
| AD/DNS 2019 | 172.20.240.102 | administrator | !Password123 | DNS |
| Web 2019 | 172.20.240.101 | administrator | !Password123 | HTTP |
| FTP 2022 | 172.20.240.104 | administrator | !Password123 | - |
| Win11 Wks | 172.20.240.100 | administrator | !Password123 | - |

### Network Devices

| Device | IP | Access From | User | Password |
|--------|-----|-------------|------|----------|
| Palo Alto | 172.20.242.150 | Ubuntu Wks (browser) | admin | Changeme123 |
| Cisco FTD | 172.20.240.200 | Win11 Wks (browser) | admin | !Changeme123 |
| VyOS Router | 172.16.101.1 | Any (SSH) | vyos | changeme |

### Competition Portals

| Portal | URL | Accounts |
|--------|-----|----------|
| NISE | https://ccdcadmin1.morainevalley.edu | team02a - team02i |
| Stadium | https://ccdc.cit.morainevalley.edu | v2u1 - v2u8 |

---

## NETWORK TOPOLOGY

```
                        INTERNET/SCORING
                              │
                    ┌─────────┴─────────┐
                    │    VyOS Router    │
                    │  172.16.101.1     │
                    └────┬─────────┬────┘
                         │         │
         ┌───────────────┘         └───────────────┐
         ▼                                         ▼
┌─────────────────┐                     ┌─────────────────┐
│   Palo Alto     │                     │   Cisco FTD     │
│ 172.20.242.150  │                     │ 172.20.240.200  │
└────────┬────────┘                     └────────┬────────┘
         │                                       │
   LINUX ZONE                              WINDOWS ZONE
   172.20.242.0/24                         172.20.240.0/24
         │                                       │
    ┌────┼────┬────────┐               ┌────┬────┼────┬────┐
    │    │    │        │               │    │    │    │    │
  Ecom  Mail Splunk  Wks             AD   Web  FTP  Wks
  .30   .40   .20   DHCP            .102 .101 .104 .100
```

---

## DEPLOY.SH REFERENCE

Run: `sudo ./deploy.sh`

### Main Menu

| Option | Runs On | What Happens |
|--------|---------|--------------|
| **1) Quick Harden** | THIS machine | Hardens SSH, firewall, services, permissions, kernel. Does NOT change passwords. Takes ~2 min. |
| **2) Ansible Control Panel** | OTHER machines | Opens submenu to manage all machines remotely via SSH/WinRM |
| **3) Advanced Options** | THIS machine | Individual scripts, SIEM agents, persistence hunting, IR tools |

### Ansible Menu (Option 2)

Ansible runs commands on OTHER machines from this one. Requires SSH (Linux) or WinRM (Windows) connectivity.

| Option | What Happens |
|--------|--------------|
| **1) Generate inventory** | Converts CSV file to inventory.ini format |
| **2) Test connectivity** | Pings all machines to verify Ansible can reach them. Run this first! |
| **3) Password Reset** | Prompts for ONE password, then: resets ALL user passwords on ALL machines, kills ALL active sessions (boots attackers) |
| **4) Deploy Hardening** | Copies toolkit to all Linux machines. Option to also run hardening. |
| **5) Deploy Splunk Forwarders** | Installs Splunk forwarder on all machines → 172.20.242.20 |
| **6) Gather Facts** | Collects system info from all machines, saves to files |

### Advanced Menu (Option 3)

| Option | What Happens |
|--------|--------------|
| **1) Interactive Harden** | Run individual hardening scripts (users, ssh, firewall, etc.) |
| **2) Service Hardening** | Harden specific services (web, mail, DNS, etc.) |
| **3) Deploy Splunk Forwarder** | Install Splunk forwarder on THIS machine |
| **4) Start Monitoring** | Start real-time file/process/network monitoring |
| **5) Hunt for Persistence** | Scan for backdoors, cron jobs, startup scripts |
| **6) Incident Response Tools** | Evidence collection, session killing, isolation |
| **7) User Enumeration** | List all users, UID 0 accounts, sudo/wheel members, SSH keys, sudoers config |

---

## WINDOWS SCRIPTS REFERENCE

Windows machines don't use `deploy.sh`. Copy toolkit to `C:\ccdc26` and run PowerShell directly.

### Quick Commands (run as Administrator)

```powershell
cd C:\ccdc26\windows-scripts

# Harden any Windows machine
.\hardening\Full-Harden.ps1 -q

# Harden Domain Controller (run on AD/DNS only)
.\hardening\AD-Harden.ps1 -q

# Install Splunk forwarder  
.\Install-SplunkForwarder.ps1 -Quick
```

### Script Reference

| Script | Runs On | What Happens |
|--------|---------|--------------|
| `Full-Harden.ps1 -q` | Any Windows | Patches EternalBlue, PrintNightmare, Mimikatz. Enables Defender ASR rules. Disables dangerous services. Removes backdoors. |
| `AD-Harden.ps1 -q` | Domain Controller only | Patches Zerologon, noPac. Hardens Kerberos. Cleans privileged groups. Enables LDAP signing. |
| `Install-SplunkForwarder.ps1 -Quick` | Any Windows | Installs Splunk forwarder → 172.20.242.20 |
| `lib\passwords.ps1` | Any Windows | Generates deterministic passwords from username+salt |

### CVEs Patched

| CVE | Name | Script |
|-----|------|--------|
| MS17-010 | EternalBlue | Full-Harden.ps1 |
| CVE-2021-34527 | PrintNightmare | Full-Harden.ps1 |
| CVE-2020-1472 | Zerologon | AD-Harden.ps1 |
| CVE-2021-42278/42287 | noPac | AD-Harden.ps1 |

---

## HOW ANSIBLE WORKS

Ansible runs on ONE machine (controller) and executes commands on OTHER machines via SSH/WinRM.

```
YOUR MACHINE (Controller)              TARGET MACHINES
┌─────────────────────┐                ┌─────────────┐
│ ./deploy.sh         │      SSH       │ Ubuntu Ecom │
│ Select: 2 (Ansible) │ ──────────────▶│ .30         │
│                     │                └─────────────┘
│ Reads:              │      SSH       ┌─────────────┐
│ - inventory.ini     │ ──────────────▶│ Fedora Mail │
│ - playbook.yml      │                │ .40         │
│                     │                └─────────────┘
│ Connects via        │     WinRM      ┌─────────────┐
│ SSH (Linux) or      │ ──────────────▶│ Windows AD  │
│ WinRM (Windows)     │                │ .102        │
└─────────────────────┘                └─────────────┘
```

**Your machine is NOT modified** - only the targets listed in inventory.ini.

---

## FIRST 5 MINUTES

### Linux (from Ansible controller)

```bash
# 1. VNC into any Linux box (e.g., Fedora Webmail)

# 2. Install prerequisites + clone toolkit
sudo dnf install -y git python3-pip   # Fedora
pip3 install ansible pywinrm
git clone https://github.com/YOUR_REPO/ccdc26.git /opt/ccdc26
cd /opt/ccdc26

# 3. Change all passwords on all machines (Ansible)
sudo ./deploy.sh   # Select 2 → 3
# Enter your team password when prompted

# 4. Harden this machine
sudo ./deploy.sh   # Select 1

# 5. Harden all other Linux machines (Ansible)
sudo ./deploy.sh   # Select 2 → 4 → 2
```

### Windows (on each Windows machine)

```powershell
# 1. VNC into Windows machine

# 2. Copy toolkit to C:\ccdc26 (network share, USB, or download ZIP)

# 3. Open PowerShell as Administrator
cd C:\ccdc26\windows-scripts

# 4. Harden this machine
.\hardening\Full-Harden.ps1 -q

# 5. On Domain Controller only:
.\hardening\AD-Harden.ps1 -q

# 6. Change administrator password
net user administrator "YourTeamP@ss!"
```

---

## EMERGENCY COMMANDS

### Change password (single machine)
```bash
# Linux
passwd                              # Current user
sudo passwd root                    # Root
echo "user:newpass" | sudo chpasswd # Any user

# Windows (PowerShell)
net user administrator "NewP@ss!"
```

### Kill attacker session
```bash
# Linux - find and kill
w                                   # See who's logged in
pkill -KILL -u suspicioususer       # Kill all their processes

# Windows
query user                          # See sessions
logoff <session_id>                 # Boot them
```

### Shutdown network interface (stops services from running)
```bash

# Linux - network shutdown / start up
sudo ip link set ens18 down
sudo ip link set ens18 up
```

### Block IP
```bash
# Linux (UFW)
sudo ufw deny from 10.0.0.100

# Linux (Iptables)
iptables -t filter -I INPUT -s 10.0.0.100 -j DROP
iptables -t filter -I OUTPUT -d 10.0.0.100 -j DROP

# Windows
New-NetFirewallRule -DisplayName "Block" -Direction Inbound -RemoteAddress 10.0.0.100 -Action Block
```

### Find reverse shells
```bash
# Linux
ss -tulpn | grep ESTABLISHED
lsof -i -P | grep LISTEN
ps auxf | grep -E "nc|ncat|bash -i"

# Windows
Get-NetTCPConnection | Where-Object {$_.State -eq "Established"}
```

---

## RULES

- Do NOT change IP addresses
- Do NOT scan other teams (instant DQ)
- MUST keep ICMP enabled
- MUST report password changes (except root/admin)
- MAX 3 VM scrubs (with penalty)
- Injects submitted as PDF

---

## SCORED SERVICES

| Service | Port | Server |
|---------|------|--------|
| HTTP | 80 | Ubuntu Ecom, Web 2019 |
| SMTP | 25 | Fedora Webmail |
| POP3 | 110 | Fedora Webmail |
| DNS | 53/udp | AD/DNS 2019 |

**Do NOT break these services!**

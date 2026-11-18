# CCDC26 Flag Drop Checklist

**Team 2 (BYU)** | **Flag Drop:** Jan 24, 2026, 9am MST

---

## Pre-Competition (Night Before / Morning Of)

- [ ] **Verify all team accounts work** on NISE and Stadium portals
- [ ] **Print QUICKREF.md** - one copy per team member
- [ ] **USB drives ready** with toolkit (backup if git fails)
- [ ] **Decide who does what** - assign machines to people

---

## Phase 1: First 5 Minutes (Critical)

**Goal:** Get onto all machines, change passwords, prevent immediate attacker access.

### Linux Controller Setup (1 person - Ubuntu Wks or Fedora)
- [ ] VNC into Linux workstation
- [ ] Clone toolkit: `git clone <repo> /opt/ccdc26`
- [ ] Install Ansible deps: `sudo dnf install -y git python3-pip sshpass && pip3 install ansible`
- [ ] Verify actual Ubuntu Wks IP (DHCP) - update `inventory.ini` if needed
- [ ] Test Linux connectivity: `ansible linux -i ansible/inventory.ini -m ping --ask-pass --ask-become-pass`

### Windows Machines (2-3 people in parallel - one per machine)
- [ ] VNC into each Windows machine
- [ ] **Immediately change admin password**: `net user administrator "YourTeamP@ss!"`
- [ ] Copy toolkit to `C:\ccdc26` (download ZIP or USB)
- [ ] Open PowerShell as Admin

---

## Phase 2: Password Reset (Minutes 5-10)

### Linux (via Ansible from controller)

```bash
cd /opt/ccdc26
sudo ./deploy.sh   # Select 2 → 3 (Password Reset + Kick Sessions)
```

This changes ALL Linux user passwords + kicks active attacker sessions.

### Windows (manual on each machine)

```powershell
# Change all local user passwords
Get-LocalUser | Where-Object {$_.Enabled} | ForEach-Object { 
    net user $_.Name "YourTeamP@ss!" 
}
```

- [ ] **Report password changes** to scoring (required per rules!)

---

## Phase 3: Initial Hardening (Minutes 10-25)

### Linux (via Ansible)

```bash
sudo ./deploy.sh   # Select 2 → 4 → 2 (Deploy + Run Hardening)
```

**OR run locally on each Linux box if Ansible is flaky:**

```bash
cd /opt/ccdc26
sudo ./deploy.sh --quick
```

### Windows (each machine)

```powershell
cd C:\ccdc26\windows-scripts

# All Windows machines
.\hardening\Full-Harden.ps1 -q

# Domain Controller ONLY (AD/DNS 172.20.240.102)
.\hardening\AD-Harden.ps1 -q
```

| Machine | Script | CVEs Patched |
|---------|--------|--------------|
| All Windows | `Full-Harden.ps1` | EternalBlue, PrintNightmare, Mimikatz |
| AD/DNS only | `AD-Harden.ps1` | Zerologon, noPac |

---

## Phase 4: Verify Scored Services (Minutes 25-35)

**Critical - don't break these!**

| Service | Machine | Port | Quick Test |
|---------|---------|------|------------|
| HTTP | Ubuntu Ecom (.30) | 80 | `curl http://localhost` |
| HTTP | Web 2019 (.101) | 80 | Browser check |
| SMTP | Fedora Webmail (.40) | 25 | `telnet localhost 25` |
| POP3 | Fedora Webmail (.40) | 110 | `telnet localhost 110` |
| DNS | AD/DNS 2019 (.102) | 53 | `nslookup <domain> localhost` |

- [ ] Test each service from the scoring engine's perspective (external)
- [ ] Check Stadium portal for service status

---

## Phase 5: Firewall Configuration (Minutes 35-45)

### Palo Alto (Linux zone)

Access from Ubuntu Wks browser at `https://172.20.242.150`

- [ ] Login: `admin / Changeme123`
- [ ] Allow inbound: 80 (HTTP), 25 (SMTP), 110 (POP3), ICMP
- [ ] Block common attack ports if not needed (22 from external)
- [ ] Keep ICMP enabled (required per rules!)

### Cisco FTD (Windows zone)

Access from Win11 Wks browser at `https://172.20.240.200`

- [ ] Login: `admin / !Changeme123`
- [ ] Allow inbound: 80 (HTTP), 53/udp (DNS), ICMP
- [ ] Consider allowing 172.20.242.0/24 → 172.20.240.0/24 for inter-zone management (optional)

### VyOS Router

SSH from any at `172.16.101.1`

- [ ] Login: `vyos / changeme`
- [ ] Change password
- [ ] Review/tighten ACLs if time permits

---

## Phase 6: SIEM/Visibility (When Breathing Room)

### Splunk Server (172.20.242.20)

```bash
# Verify Splunk is running
/opt/splunk/bin/splunk status

# Create indexes if not present
cd /opt/ccdc26/linux-scripts/tools
sudo ./splunk-server.sh indexes
```

### Deploy Forwarders

**Linux (via Ansible):**

```bash
sudo ./deploy.sh   # Select 2 → 5 (Deploy Splunk Forwarders)
```

**Windows (each machine):**

```powershell
cd C:\ccdc26\windows-scripts
.\Install-SplunkForwarder.ps1 -Quick
```

---

## Phase 7: Persistence Hunting (When Stable)

### Linux

```bash
cd /opt/ccdc26
sudo ./deploy.sh   # Select 3 → 5 (Hunt for Persistence)
```

### Windows

```powershell
# Check scheduled tasks
Get-ScheduledTask | Where-Object {$_.State -ne 'Disabled'}

# Check services
Get-Service | Where-Object {$_.StartType -eq 'Automatic'}

# Check startup items
Get-CimInstance Win32_StartupCommand
```

---

## Ongoing Priorities

1. **Monitor Stadium portal** for service status
2. **Watch for injects** on NISE portal
3. **Check `w` / `query user`** periodically for unauthorized sessions
4. **Respond to incidents** - use IR scripts in `linux-scripts/incident-response/`

---

## Emergency Commands (Keep Handy)

### Kill Attacker Session

```bash
# Linux
w                           # See who's logged in
pkill -KILL -u username     # Boot them

# Windows
query user
logoff <session_id>
```

### Block IP

```bash
# Linux (UFW)
sudo ufw deny from 10.0.0.100

# Linux (iptables)
sudo iptables -I INPUT -s 10.0.0.100 -j DROP
sudo iptables -I OUTPUT -d 10.0.0.100 -j DROP

# Windows
New-NetFirewallRule -DisplayName "Block" -Direction Inbound -RemoteAddress 10.0.0.100 -Action Block
```

### Find Reverse Shells

```bash
# Linux
ss -tulpn | grep ESTABLISHED
lsof -i -P | grep -E "nc|ncat|bash"
ps auxf | grep -E "nc|ncat|bash -i"

# Windows
Get-NetTCPConnection | Where-Object {$_.State -eq "Established"}
```

---

## Ansible Strategy Summary

| Target | Use Ansible? | Reason |
|--------|-------------|--------|
| Linux boxes | **Yes** (SSH) | Same subnet, reliable |
| Windows boxes | **No** | Cross-firewall (Cisco FTD blocks), WinRM finnicky |
| Firewalls | **No** | GUI-based management |

---

## Role Assignments (Suggested)

| Role | Primary Tasks | Machines |
|------|---------------|----------|
| **Linux Lead** | Ansible controller, Linux hardening, Splunk server | Ubuntu Wks (controller), Ecom, Webmail, Splunk |
| **Windows Lead** | AD hardening, DNS service | AD/DNS 2019, Win11 Wks |
| **Web Lead** | IIS hardening, web services | Web 2019 |
| **Network Lead** | Firewall rules, VyOS | Palo Alto, Cisco FTD, VyOS |
| **Inject/Flex** | Handle injects, backup IR | Float between tasks |

---

## Rules Reminders

- Do NOT change IP addresses
- Do NOT scan other teams (instant DQ)
- MUST keep ICMP enabled
- MUST report password changes (except root/admin)
- MAX 3 VM scrubs (with penalty)
- Injects submitted as PDF

---

## Machine Quick Reference

### Linux (172.20.242.0/24 - behind Palo Alto)

| Machine | IP | User | Scored Services |
|---------|-----|------|-----------------|
| Ubuntu Ecom | 172.20.242.30 | sysadmin | HTTP |
| Fedora Webmail | 172.20.242.40 | sysadmin | SMTP, POP3 |
| Splunk | 172.20.242.20 | root | - |
| Ubuntu Wks | **DHCP** | sysadmin | - |

### Windows (172.20.240.0/24 - behind Cisco FTD)

| Machine | IP | User | Scored Services |
|---------|-----|------|-----------------|
| AD/DNS 2019 | 172.20.240.102 | administrator | DNS |
| Web 2019 | 172.20.240.101 | administrator | HTTP |
| FTP 2022 | 172.20.240.104 | administrator | - |
| Win11 Wks | 172.20.240.100 | administrator | - |

### Network Devices

| Device | IP | Access From | User |
|--------|-----|-------------|------|
| Palo Alto | 172.20.242.150 | Ubuntu Wks (browser) | admin |
| Cisco FTD | 172.20.240.200 | Win11 Wks (browser) | admin |
| VyOS Router | 172.16.101.1 | Any (SSH) | vyos |

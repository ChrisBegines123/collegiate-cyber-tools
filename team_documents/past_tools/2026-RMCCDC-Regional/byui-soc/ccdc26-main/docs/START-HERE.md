# CCDC26 -- Competition Day Playbook

> This is the only doc you need at flag drop. Follow steps in order. No skipping.

> **Monarch** controls all Linux machines from one keyboard via SSH. One command runs on every machine simultaneously.
> **Dovetail** does the same for Windows machines via WinRM. Both dispatch the numbered scripts (00-05) in order.

---

## Step 0: Read the Packet (First 2 Minutes)

Before touching anything, open the competition packet and record:

| Info | Value | Where to write it |
|------|-------|--------------------|
| **Your subnet(s)** | _____________ | `config.env`, printed QUICKREF |
| **Machine IPs + roles** | _____________ | QUICKREF credential tables |
| **Default credentials** | _____________ | QUICKREF credential tables |
| **Scored services per machine** | _____________ | QUICKREF scored services table |
| **Firewall / router IPs + creds** | _____________ | QUICKREF network devices table |
| **Splunk server IP** | _____________ | `config.env` → `SPLUNK_SERVER` |
| **Scoring engine URL** | _____________ | Bookmark in browser |
| **Rules / restrictions** | _____________ | Read aloud to team |

Assign machines to people immediately. The person with the most Linux machines becomes Linux Lead (runs Monarch). Someone with DC access becomes Windows Lead (runs Dovetail).

---

## Step 1: Get the Toolkit (1 min)

### LINUX PERSON

```bash
sudo git clone https://github.com/byui-soc/ccdc26.git /opt/ccdc26
cd /opt/ccdc26
sudo ./deploy.sh --configure     # Fill in Splunk IP + any other values from packet
```

### WINDOWS PERSON (PowerShell as Admin)

```powershell
# Method 1: GitHub download
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://github.com/byui-soc/ccdc26/archive/refs/heads/main.zip" -OutFile C:\ccdc26.zip
Expand-Archive C:\ccdc26.zip -DestinationPath C:\; Rename-Item C:\ccdc26-main C:\ccdc26

# Method 2: From Linux controller (if no internet / GitHub blocked)
# On Linux first:  cd /opt && tar czf /tmp/ccdc26.tar.gz ccdc26/ && cd /tmp && python3 -m http.server 8080
# Then on Windows:
Invoke-WebRequest -Uri "http://LINUX_IP:8080/ccdc26.tar.gz" -OutFile C:\ccdc26.tar.gz
tar -xzf C:\ccdc26.tar.gz -C C:\
```

---

## LINUX PERSON (Minutes 2-15)

```bash
cd /opt/ccdc26/monarch
python3 -m monarch
```

| Step | Command | What it does |
|------|---------|--------------|
| 1 | `scan SUBNET PASSWORD` | Discover all Linux hosts via SSH |
| 2 | `script 00-snapshot.sh` | Baseline users, crons, services, ports |
| 3 | `rotate` | Change ALL passwords + kick sessions |
| 4 | `script 01-harden.sh` | SSH lockdown, kernel hardening, permissions |
| 5 | `script 02-firewall.sh` | iptables/ufw on all hosts |
| 6 | `script 03-services.sh` | Harden running services (auto-detects what's installed) |

> `03-services.sh` detects which services are running and hardens only those.
> It does NOT assume specific services exist.

---

## WINDOWS PERSON (Minutes 2-15, parallel)

```powershell
cd C:\ccdc26\dovetail\scripts
```

| Step | Command | What it does |
|------|---------|--------------|
| 1 | `.\00-snapshot.ps1` | Baseline users, services, tasks, ports |
| 2 | `.\01-blitz.ps1` | Harden this machine (CVE patches, Defender, services) |
| 3 | `.\02-ad.ps1` | **Domain Controller ONLY** -- Zerologon, noPac, Kerberos |
| 4 | Repeat on each Windows machine | Or use Dovetail from DC to dispatch |

**Dovetail dispatch (from DC, after hardening all machines):**

```powershell
cd C:\ccdc26\dovetail
.\dovetail.ps1 -Connect -Targets "domain"              # Connect to all Windows hosts
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1           # Harden all at once
```

---

## Verify Scored Services (Minutes 15-20)

**Do NOT skip this.** Check every scored service listed in the packet.

The exact services will vary -- use the table from the packet. Common quick tests:

| Service | Quick Test |
|---------|-----------|
| HTTP / HTTPS | `curl -sk http://<ip>` or browse to it |
| SMTP | `nc -zv <ip> 25` |
| POP3 / IMAP | `nc -zv <ip> 110` or `nc -zv <ip> 143` |
| DNS | `nslookup <domain> <dns-ip>` |
| FTP | `nc -zv <ip> 21` |
| SSH | `nc -zv <ip> 22` |
| RDP | `nc -zv <ip> 3389` |
| AD / LDAP | `nc -zv <ip> 389` |

- [ ] Check scoring portal for green checks
- [ ] If a service is down: restart it, check logs, undo firewall rule if needed
- [ ] **Fix broken services BEFORE continuing** -- points > hardening

---

## Firewalls (Minutes 20-30)

> The network topology varies by competition. Read the packet carefully to identify
> what firewalls/routers sit between your machines and the scoring engine.

### General Approach

1. **Identify the firewall(s)**: The packet will list firewall/router IPs and credentials. Could be Palo Alto, Cisco FTD/ASA, pfSense, FortiGate, VyOS, or anything else.

2. **Login and change default passwords first.**

3. **Add rules in this priority order:**

| Priority | Rule | Why |
|----------|------|-----|
| 1 | Scoring engine -> your machines (scored service ports + ICMP) | **Scored services must be reachable** |
| 2 | Your machines -> Splunk server (9997) | Log forwarding |
| 3 | Cross-zone if applicable (Linux <-> Windows on management ports) | Toolkit + Splunk cross-zone |
| 4 | Outbound for updates if allowed (80/443 temporarily) | Package downloads |

4. **Common cross-zone ports** (only if Linux and Windows are on separate subnets):

| Direction | Ports | Why |
|-----------|-------|-----|
| Linux -> Windows | 5985 (WinRM), 9997 (Splunk) | Management + logs |
| Windows -> Linux | 22 (SSH), 9997 (Splunk), 8000 (Splunk web) | Management + logs |

5. **If Windows machines have host firewalls** that block your Linux subnet:

```powershell
New-NetFirewallRule -DisplayName "Allow Linux Subnet" -Direction Inbound -RemoteAddress <linux-subnet>/24 -Action Allow
```

### Verify cross-zone connectivity

```bash
# From Linux:
ping <windows-ip>
nc -zv <windows-ip> 5985
```

```powershell
# From Windows:
Test-NetConnection -ComputerName <linux-ip> -Port 9997
```

---

## After Stabilizing (Minutes 30-45)

### Linux (from Monarch REPL)

```
> script 04-splunk.sh           # Deploy Splunk forwarders to all hosts
> script 05-monitor.sh          # Deploy file/process/network monitors
```

### Windows (each machine, or via Dovetail)

```powershell
.\03-audit.ps1                  # Audit policies + PowerShell logging
.\04-splunk.ps1                 # Install Splunk forwarder
.\05-monitor.ps1                # Start real-time monitoring
```

- [ ] Verify Splunk server is receiving data (check `index=* | stats count by host`)
- [ ] Confirm monitoring is active on all machines

---

## Ongoing Threat Hunting

### Linux

```
> script hunt-persistence.sh    # Cron, services, users, binaries, startup
```

### Windows

```powershell
.\hunt-persistence.ps1          # Registry, tasks, WMI, services, COM, SSPs
.\hunt-webshells.ps1 -Baseline  # Baseline web roots -- do this early!
.\hunt-webshells.ps1 -Compare   # Diff against baseline (run periodically)
```

---

## Emergency Commands

**Kill attacker session:**

```bash
w && pkill -KILL -u <username>                         # Linux
```

```powershell
query user; logoff <session_id>                        # Windows
```

**Block IP:**

```bash
sudo iptables -I INPUT -s <IP> -j DROP && sudo iptables -I OUTPUT -d <IP> -j DROP
```

```powershell
New-NetFirewallRule -DisplayName "Block" -Direction Inbound -RemoteAddress <IP> -Action Block
```

**Find reverse shells:**

```bash
ss -tnp | grep ESTAB                                   # Linux
```

```powershell
Get-NetTCPConnection | Where-Object {$_.State -eq "Established"} | ft
```

**Change a password:**

```bash
echo "user:newpass" | sudo chpasswd                     # Linux
```

```powershell
net user <username> "NewP@ss!"                          # Windows
```

**Restart a scored service:**

```bash
sudo systemctl restart <service>                        # Linux
```

```powershell
Restart-Service <name>                                  # Windows
```

---

## Rules Reminders

These are typical CCDC rules. **Confirm against the actual rulebook at competition.**

- Do NOT change IP addresses
- Do NOT scan other teams (instant DQ)
- MUST keep ICMP enabled
- MUST report password changes to scoring (except root/admin)
- VM scrubs have a limited count and scoring penalty
- Injects submitted as PDF (usually)

---

> **Need more detail?** See [CHECKLIST.md](CHECKLIST.md) (role assignments), [QUICKREF.md](QUICKREF.md) (script reference), [THREAT-HUNTING.md](THREAT-HUNTING.md) (hunting playbook), [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (common issues).

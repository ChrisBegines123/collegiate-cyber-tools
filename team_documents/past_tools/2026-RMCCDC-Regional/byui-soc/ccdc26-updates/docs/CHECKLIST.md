> **For the step-by-step workflow, see [START-HERE.md](START-HERE.md).**
> This checklist provides additional detail and role assignments.

# CCDC26 Flag Drop Checklist

**Team ___** | **Flag Drop:** _______________

---

## Pre-Competition (Night Before / Morning Of)

- [ ] Verify all team accounts on competition portals (NISE, Stadium, Nextcloud, etc.)
- [ ] Print QUICKREF.md -- one copy per team member
- [ ] Review scripts and docs one more time
- [ ] Agree on team password scheme (e.g. `Team3-<machine>-<random>!`)

---

## Phase 1: Read the Packet + Get Access (First 5 Minutes)

**Goal:** Understand what you have, get onto all machines, prevent immediate attacker access.

- [ ] **Read the packet** -- record all IPs, credentials, scored services, topology
- [ ] Fill in the QUICKREF credential tables (or write on printed copy)
- [ ] Assign machines to people based on what's in the packet

### Linux Controller (1 person)

- [ ] VNC/SSH into a Linux machine (workstation or whichever has internet)
- [ ] Clone toolkit: `sudo git clone https://github.com/byui-soc/ccdc26.git /opt/ccdc26`
- [ ] Configure: `cd /opt/ccdc26 && sudo ./deploy.sh --configure`
- [ ] Start Monarch: `cd monarch && python3 -m monarch`
- [ ] Scan: `scan SUBNET PASSWORD` (subnet and password from packet)
- [ ] Snapshot: `script 00-snapshot.sh`

### Windows Machines (2-3 people in parallel)

- [ ] VNC/RDP into each Windows machine
- [ ] **Immediately** change admin password: `net user administrator "YourTeamP@ss!"`
- [ ] Deploy toolkit (see Step 1 in START-HERE.md)
- [ ] Run snapshot: `cd C:\ccdc26\dovetail\scripts && .\00-snapshot.ps1`

---

## Phase 2: Password Reset (Minutes 5-10)

### Linux (from Monarch REPL)

```
> rotate
```

Changes ALL Linux user passwords + kicks active sessions.

### Windows (each machine)

```powershell
Get-LocalUser | Where-Object {$_.Enabled} | ForEach-Object { net user $_.Name "YourTeamP@ss!" }
```

- [ ] **Report password changes** to scoring if required by rules

---

## Phase 3: Initial Hardening (Minutes 10-20)

### Linux (from Monarch REPL)

```
> script 01-harden.sh
> script 02-firewall.sh
> script 03-services.sh
```

### Windows (each machine)

```powershell
cd C:\ccdc26\dovetail\scripts
.\01-blitz.ps1                  # All Windows machines
.\02-ad.ps1                     # Domain Controller ONLY
```

**Or via Dovetail from DC:**

```powershell
cd C:\ccdc26\dovetail
.\dovetail.ps1 -Connect -Targets "domain"
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1
```

---

## Phase 4: Verify Scored Services (Minutes 20-25)

**Do NOT skip this.** Check that hardening didn't break anything.

Refer to the packet for which services are scored on which machines. Use the generic test table in START-HERE.md. Common scored services include HTTP, HTTPS, DNS, SMTP, POP3, IMAP, FTP, SSH, RDP, LDAP -- but it depends on the environment.

- [ ] Test each scored service from the scoring engine's perspective
- [ ] Check scoring portal for service status
- [ ] If a service is down: restart it, check logs, undo firewall rule if needed
- [ ] **Fix broken services BEFORE moving on** -- points matter more than hardening

---

## Phase 5: Firewall Configuration (Minutes 25-35)

> The network topology varies by competition. You might have one firewall or three,
> and they could be any vendor. Read the packet to figure out what sits between your
> machines and the scoring engine.

### For Every Firewall / Router in the Packet

- [ ] Login with packet credentials
- [ ] **Change default password immediately**
- [ ] Add rule: Scoring engine can reach your scored service ports + ICMP
- [ ] Add rule: Your machines can reach Splunk (port 9997)
- [ ] If subnets are separated: add cross-zone rules (see START-HERE.md)
- [ ] Commit / deploy / save changes

### Host Firewalls (Windows)

If Linux and Windows are on different subnets:

```powershell
New-NetFirewallRule -DisplayName "Allow Linux Subnet" -Direction Inbound -RemoteAddress <linux-subnet>/24 -Action Allow
```

### Verify

```bash
ping <windows-ip>                          # From Linux
nc -zv <windows-ip> 5985                   # WinRM
```

```powershell
Test-NetConnection <linux-ip> -Port 9997   # From Windows
```

---

## Phase 6: SIEM + Monitoring (Minutes 35-45)

### Linux (from Monarch REPL)

```
> script 04-splunk.sh
> script 05-monitor.sh
```

### Windows (each machine)

```powershell
cd C:\ccdc26\dovetail\scripts
.\03-audit.ps1
.\04-splunk.ps1
.\05-monitor.ps1
```

- [ ] Verify Splunk server is receiving data
- [ ] Start monitoring on all Windows machines
- [ ] Baseline web roots if applicable: `.\hunt-webshells.ps1 -Baseline`

### Optional Security Tools -- ONLY AFTER ALL SCORED SERVICES ARE GREEN

> Do NOT run these until Phase 4 service verification passes.
> Each tool's risk level is noted. If anything breaks scoring, rollback instructions are included.

| Script | Risk | What it does | Rollback |
|--------|------|--------------|----------|
| `setup-wazuh.sh` | LOW | Wazuh HIDS agent -- FIM, rootkit detection, 3000+ rules | `systemctl stop wazuh-agent` |
| `setup-ids.sh` | LOW | Suricata IDS -- passive network monitoring, never drops traffic | `systemctl stop suricata` |
| `scan-vulns.sh` | LOW | Nuclei CVE scanner -- read-only, just reports findings | N/A (read-only) |
| `update-cms-creds.sh` | MEDIUM | Updates DB passwords in CMS configs (if CMS exists) | Restore config from `.bak` file |
| `setup-waf.sh` | MEDIUM | ModSecurity WAF in DetectionOnly mode (logs but does NOT block) | See below |

```
> script setup-wazuh.sh            # Safe: agent only, alerts go to manager -> Splunk
> script setup-ids.sh              # Safe: passive IDS, just watches traffic
> script scan-vulns.sh             # Safe: read-only CVE scan
> script update-cms-creds.sh       # Medium: test web app after running
> script setup-waf.sh              # Medium: log-only by default, web server restarts
```

### Windows Wazuh Agent

```powershell
.\setup-wazuh-agent.ps1 -ManagerIP "10.0.x.x"   # Or reads from config.ps1
```

**WAF rollback** (if web scoring breaks after setup-waf.sh):
```bash
# Option 1: Disable ModSecurity entirely
sed -i 's/^SecRuleEngine .*/SecRuleEngine Off/' /etc/modsecurity/modsecurity.conf
systemctl restart apache2   # or: systemctl restart nginx

# Option 2: Restore backup config
cp /etc/modsecurity/modsecurity.conf.bak.* /etc/modsecurity/modsecurity.conf
systemctl restart apache2   # or: systemctl restart nginx
```

---

## Phase 7: Persistence Hunting (When Stable)

### Linux

```
> script hunt-persistence.sh
```

### Windows

```powershell
cd C:\ccdc26\dovetail\scripts
.\hunt-persistence.ps1
.\hunt-webshells.ps1 -Compare
```

- [ ] Hunt persistence on every machine
- [ ] Scan for webshells on any machine running a web server

---

## Ongoing Priorities

1. **Monitor scoring portal** for service status
2. **Watch for injects** on competition portal
3. **Check `w` / `query user`** periodically for unauthorized sessions
4. **Re-run persistence hunts** after incidents
5. **Scan for webshells** periodically on web servers
6. **Check monitoring** alerts: `.\05-monitor.ps1 -Status`

---

## Role Assignments (Suggested -- adapt to your team size and the environment)

| Role | Primary Tasks | Machines |
|------|---------------|----------|
| **Linux Lead** | Monarch controller, Linux hardening, Splunk oversight | Controller machine + all Linux hosts via Monarch |
| **Windows Lead** | AD hardening, Dovetail dispatch, Windows services | DC + all Windows hosts via Dovetail |
| **Services Lead** | Verify scored services, fix breakages, web app hardening | Whichever machines run scored services |
| **Network Lead** | Firewall rules, router config, cross-zone connectivity | All network devices from packet |
| **Inject / Flex** | Handle injects, backup IR, assist wherever needed | Float between tasks |

> Adjust roles based on team size. With 3 people, combine Linux Lead + Network Lead
> and Windows Lead + Services Lead.

---

## Machine Quick Reference

**Fill in from competition packet.**

### Linux Hosts

| Machine | IP | User | Scored Services |
|---------|-----|------|-----------------|
| | | | |
| | | | |
| | | | |
| | | | |

### Windows Hosts

| Machine | IP | User | Scored Services |
|---------|-----|------|-----------------|
| | | | |
| | | | |
| | | | |
| | | | |

### Network Devices

| Device | Type | IP | Access From | User |
|--------|------|----|-------------|------|
| | | | | |
| | | | | |
| | | | | |

---

## Rules Reminders

These are typical CCDC rules. **Confirm against the actual rulebook at competition.**

- Do NOT change IP addresses
- Do NOT scan other teams (instant DQ)
- MUST keep ICMP enabled
- MUST report password changes (except root/admin typically)
- VM scrubs have limited count and scoring penalty
- Injects submitted as PDF (usually)

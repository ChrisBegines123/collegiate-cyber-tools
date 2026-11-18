# Threat Hunting Playbook

Use this when you suspect compromise or need to hunt proactively.

## When to Use This Document

| Situation | Jump to |
|-----------|---------|
| "I found a suspicious process" | ["I Found a Suspicious Process"](#i-found-a-suspicious-process) |
| "Unusual network traffic" | ["I See Unusual Network Traffic"](#i-see-unusual-network-traffic) |
| "A scored service keeps dying" | ["A Scored Service Is Down"](#a-scored-service-is-down) |
| "I think an account was compromised" | ["I Think an Account Is Compromised"](#i-think-an-account-is-compromised) |
| "I need to hunt for backdoors (Linux)" | [Linux Threat Hunting Checklist](#3-linux-threat-hunting-checklist) |
| "I need to hunt for backdoors (Windows)" | [Windows Threat Hunting Checklist](#4-windows-threat-hunting-checklist) |
| "What attacks does red team use?" | [Common CCDC Attack Patterns](#5-common-ccdc-attack-patterns) |
| "Active attacker on the network NOW" | [Active Attacker Detected](#81-active-attacker-detected) |

---

## 1. Quick Start -- First 5 Minutes of Hunting

### Linux (run on each box via Monarch)

```bash
# Full persistence scan (cron, services, users, binaries, startup)
> script hunt-persistence.sh

# Deploy all monitoring (file, process, network, log)
> script 05-monitor.sh

# Instant situational awareness -- run these manually:
w                                       # Who is logged in RIGHT NOW
ss -tulpn                               # All listening ports + process
ss -tnp | grep ESTAB                    # Established connections
ps auxf --sort=-%cpu | head -30         # Process tree, CPU sorted
last -20                                # Recent logins
find /tmp /var/tmp /dev/shm -type f     # Files in temp dirs
```

### Windows (run on each box as Administrator)

```powershell
cd C:\ccdc26\dovetail\scripts

# 13-category persistence hunt
.\hunt-persistence.ps1

# Full triage (sessions, processes, network, services, tasks, timeline, filesystem)
.\ir-triage.ps1

# Instant situational awareness:
query user                                                          # Active sessions
Get-NetTCPConnection | Where-Object {$_.State -eq "Established"} | ft  # Connections
Get-Process | Sort-Object CPU -Descending | Select -First 20       # Top processes
Get-ScheduledTask | Where-Object {$_.State -ne 'Disabled' -and $_.TaskPath -notmatch '\\Microsoft\\'}
```

---

## 2. Detection Priorities by Phase

### Minutes 0-15: Initial Access

Attackers will do these **immediately** at flag drop:

| Action | How to Detect |
|--------|---------------|
| Login with default creds | `w` / `query user` -- unknown sessions |
| Create backdoor accounts | `grep ':0:' /etc/passwd` / Event 4720 |
| Plant SSH keys | `find / -name authorized_keys -mmin -30` |
| Drop webshells | Check docroots: `/var/www/`, `C:\inetpub\wwwroot\` |
| Establish reverse shells | `ss -tnp \| grep ESTAB` / `Get-NetTCPConnection` |
| Disable logging | Check if `rsyslog`/`auditd` still running |

**MITRE ATT&CK:** T1078 (Valid Accounts), T1136 (Create Account), T1505.003 (Web Shell)

### Minutes 15-60: Persistence & Lateral Movement

| Action | How to Detect |
|--------|---------------|
| Cron/task-based callbacks | `crontab -l -u root` / `Get-ScheduledTask` |
| Service replacement | `systemctl list-units` / `Get-Service` check binary paths |
| WMI subscriptions | `.\hunt-persistence.ps1` |
| Registry run keys | `.\hunt-persistence.ps1` |
| Lateral movement via SSH/RDP | `ss -tnp \| grep :22` outbound / Event 4624 Type 10 |
| Credential dumping | Check for mimikatz/procdump processes |

**MITRE ATT&CK:** T1053 (Scheduled Task), T1543 (Create Service), T1546 (WMI), T1021 (Remote Services)

### Ongoing: Continuous Monitoring

```bash
# Linux: start monitors (logs to /var/log/ccdc-toolkit/)
> script 05-monitor.sh

# Linux: beacon detection (manual checks)
ss -ulnp | grep -v '127.0.0'                    # UDP listeners
ss -tnp | grep ':22' | grep ESTABLISHED         # Outbound SSH
```

```powershell
# Windows: start all monitors (process, network, session)
.\05-monitor.ps1
```

**MITRE ATT&CK:** T1071 (Application Layer Protocol), T1572 (Protocol Tunneling)

---

## 3. Linux Threat Hunting Checklist

### 3.1 Backdoor Accounts & SSH Keys

**What to look for:** UID 0 accounts, new users, unauthorized SSH keys

```bash
# UID 0 accounts (should only be root)
awk -F: '$3 == 0 {print $1}' /etc/passwd

# Users with login shells
grep -v '/nologin\|/false' /etc/passwd

# Recently added users
ls -lt /home/

# SSH keys -- check every user
for d in /home/* /root; do
    [ -f "$d/.ssh/authorized_keys" ] && echo "=== $d ===" && cat "$d/.ssh/authorized_keys"
done

# Sudoers modifications
cat /etc/sudoers
ls -la /etc/sudoers.d/
```

**Script:** `> script hunt-persistence.sh`
**Output:** Lists all UID 0 accounts, sudo/wheel members, SSH keys, shell users
**If found:** Remove the account (`userdel -r <user>`), delete unauthorized keys, check `/etc/sudoers.d/` for injected files

### 3.2 Malicious Cron Jobs

**What to look for:** Reverse shells, download-and-execute, encoded commands in cron

```bash
# All user crontabs
for user in $(cut -d: -f1 /etc/passwd); do
    crontab -l -u "$user" 2>/dev/null && echo "^^^ $user ^^^"
done

# System cron locations
cat /etc/crontab
ls -la /etc/cron.d/ /etc/cron.daily/ /etc/cron.hourly/
```

**Script:** `> script hunt-persistence.sh`
**Output:** All cron entries with suspicious pattern flagging
**Red flags:** `curl|wget|nc|bash -i|/dev/tcp|python -c|base64`
**If found:** `crontab -r -u <user>`, remove files from `/etc/cron.d/`

### 3.3 Rogue Services & Systemd Units

**What to look for:** New services, modified service binaries, oneshot services with ExecStart pointing to temp dirs

```bash
# Non-vendor systemd units
systemctl list-units --type=service --state=running
systemctl list-unit-files --type=service | grep enabled

# Recently created/modified units
find /etc/systemd/system /run/systemd/system -name '*.service' -mtime -7 2>/dev/null

# Check for suspicious ExecStart
grep -r 'ExecStart.*\(/tmp\|/dev/shm\|/var/tmp\|curl\|wget\|nc\|bash\)' /etc/systemd/system/
```

**Script:** `> script hunt-persistence.sh`
**If found:** `systemctl stop <svc> && systemctl disable <svc>`, remove the unit file, `systemctl daemon-reload`

### 3.4 SUID/SGID Binaries & Capability Abuse

**What to look for:** Unexpected SUID binaries, especially in /tmp or home dirs

```bash
# All SUID binaries
find / -perm -4000 -type f 2>/dev/null

# All SGID binaries
find / -perm -2000 -type f 2>/dev/null

# Files with capabilities
getcap -r / 2>/dev/null

# Recently changed SUID binaries
find / -perm -4000 -type f -mtime -7 2>/dev/null
```

**Script:** `> script hunt-persistence.sh`
**If found:** `chmod u-s <file>` to remove SUID, or delete if it's not a known system binary. Compare against a known-good baseline.

### 3.5 Shell Profile Modifications

**What to look for:** Reverse shells or malware loaders in `.bashrc`, `.profile`, `/etc/profile.d/`

```bash
# Check global profiles
cat /etc/profile
ls -la /etc/profile.d/
cat /etc/bash.bashrc

# Check per-user profiles
for d in /home/* /root; do
    for f in .bashrc .bash_profile .profile .bash_logout; do
        [ -f "$d/$f" ] && echo "=== $d/$f ===" && tail -5 "$d/$f"
    done
done
```

**Script:** `> script hunt-persistence.sh`
**Red flags:** `curl|wget|nc|/dev/tcp|base64|python|exec` in profile files
**If found:** Remove the malicious lines, check `diff` against a default copy

### 3.6 Network Anomalies (Reverse Shells, C2 Beacons)

**What to look for:** Outbound connections to unknown IPs, connections on unusual ports

```bash
# Established connections with process info
ss -tnp state established

# Look for common reverse shell ports
ss -tnp | grep -E ':(4444|5555|6666|7777|8888|9999|1234|31337) '

# Processes making network connections from /tmp
for pid in $(ls /proc | grep '^[0-9]'); do
    exe=$(readlink /proc/$pid/exe 2>/dev/null)
    if echo "$exe" | grep -qE '^(/tmp|/dev/shm|/var/tmp)'; then
        echo "PID $pid: $exe"
        ls -la /proc/$pid/fd 2>/dev/null | grep socket
    fi
done
```

**Detection:**
- `ss -tnp | grep ':22' | grep ESTABLISHED` -- flags outbound SSH
- `ss -ulnp | grep -v '127.0.0'` -- flags UDP beaconing

**If found:** Kill the process (`kill -9 <pid>`), block the remote IP (`iptables -I OUTPUT -d <ip> -j DROP`), check what spawned it (`cat /proc/<pid>/status | grep PPid`)

### 3.7 Web Shells

**What to look for:** Recently modified PHP/ASPX files, files with `eval`, `exec`, `system` calls

```bash
# Recently modified web files
find /var/www /srv/www -name '*.php' -mtime -7 2>/dev/null
find /var/www /srv/www -name '*.php' -newer /etc/passwd 2>/dev/null

# Files with suspicious content
grep -rl 'eval\|exec\|system\|passthru\|shell_exec\|base64_decode' /var/www/ 2>/dev/null

# One-liner web shells (small files)
find /var/www -name '*.php' -size -2k -exec grep -l 'eval\|exec\|system' {} \;
```

**If found:** Move to quarantine (`mv <file> /tmp/quarantine/`), do NOT delete (may need for evidence). Check web server access logs for the file being accessed.

### 3.8 Log Tampering

**What to look for:** Truncated logs, gaps in timestamps, missing auth logs

```bash
# Check log file sizes (0 = tampered)
ls -la /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages 2>/dev/null

# Check if logging services are running
systemctl status rsyslog auditd

# Gaps in auth log (look for time jumps)
awk '{print $1, $2, $3}' /var/log/auth.log 2>/dev/null | tail -50

# Check if history files are symlinked to /dev/null
ls -la /root/.bash_history /home/*/.bash_history 2>/dev/null
```

**If found:** Restart rsyslog/auditd. Attackers often: `> /var/log/auth.log`, `ln -sf /dev/null ~/.bash_history`, `unset HISTFILE`

---

## 4. Windows Threat Hunting Checklist

### 4.1 Registry Persistence (Run Keys, Winlogon, IFEO)

**What to look for:** Entries in Run/RunOnce keys, modified Winlogon Shell/Userinit, IFEO debuggers

```powershell
# Run keys
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue

# Winlogon
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" | Select Shell,Userinit

# IFEO (Image File Execution Options) -- should have no Debugger values
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" |
    ForEach-Object { $d = (Get-ItemProperty $_.PSPath).Debugger; if($d){"$($_.PSChildName): $d"} }
```

**Script:** `.\hunt-persistence.ps1`
**If found:** `.\hunt-persistence.ps1` flags and reports high-risk findings

### 4.2 Malicious Scheduled Tasks

**What to look for:** Non-Microsoft tasks, tasks running PowerShell/cmd with encoded commands, tasks created in last 7 days

```powershell
# Non-Microsoft active tasks
Get-ScheduledTask | Where-Object {$_.TaskPath -notmatch '\\Microsoft\\' -and $_.State -ne 'Disabled'} |
    Select TaskName,TaskPath,State | Format-Table

# Tasks with suspicious executables
Get-ScheduledTask | ForEach-Object {
    $a = $_.Actions; if($a.Execute -match 'powershell|cmd|wscript|mshta|certutil'){
        [PSCustomObject]@{Name=$_.TaskName;Exe=$a.Execute;Args=$a.Arguments}
    }
}
```

**Script:** `.\hunt-persistence.ps1`
**If found:** `Unregister-ScheduledTask -TaskName "<name>" -Confirm:$false`

### 4.3 WMI Event Subscriptions

**What to look for:** ANY WMI event subscriptions -- these are almost never legitimate in CCDC

```powershell
Get-WmiObject -Namespace root\Subscription -Class __EventFilter
Get-WmiObject -Namespace root\Subscription -Class __EventConsumer
Get-WmiObject -Namespace root\Subscription -Class __FilterToConsumerBinding
```

**Script:** `.\hunt-persistence.ps1`
**If found:** Remove all three objects (filter, consumer, binding).

### 4.4 Suspicious Services

**What to look for:** Services with binaries outside `C:\Windows\` or `C:\Program Files\`, unquoted paths, recently modified binaries

```powershell
# Services from unusual paths
Get-WmiObject Win32_Service | Where-Object {
    $_.PathName -and $_.PathName -notmatch '^"?C:\\Windows\\' -and
    $_.PathName -notmatch '^"?C:\\Program Files' -and $_.State -eq 'Running'
} | Select Name,PathName,StartName | Format-Table -Wrap
```

**Script:** `.\hunt-persistence.ps1`
**If found:** `Stop-Service <name> -Force; Set-Service <name> -StartupType Disabled`

### 4.5 IIS Webshells

**What to look for:** Recently modified `.aspx`/`.asp`/`.ashx` files, files with `eval`, `Process.Start`, `cmd.exe` references

```powershell
# Quick scan -- auto-detects IIS web roots
.\hunt-webshells.ps1
```

**If found:** Quarantine the file, check IIS logs (`C:\inetpub\logs\`) for who accessed it, check for follow-on persistence

### 4.6 Active Attacker Sessions

**What to look for:** Unknown usernames, RDP sessions from unexpected IPs

```powershell
# List all sessions with source IPs and known/unknown tagging
.\ir-kill.ps1

# Kill specific user + disable account + block IP
.\ir-kill.ps1
```

### 4.7 Encoded PowerShell

**What to look for:** Processes running with `-enc` / `-EncodedCommand` flags

```powershell
# Find encoded PowerShell
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match '-[Ee](nc|ncodedCommand)\s+[A-Za-z0-9+/=]{20,}'
} | Select ProcessId,CommandLine

# Decode it
[System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('<base64_string>'))
```

**If found:** Kill the process, trace parent process, check for scheduled task or service that spawned it

### 4.8 Lateral Movement Indicators

**What to look for:** PsExec, WMI remote execution, SMB connections to other team machines

```powershell
# Event 4624 Type 3 (Network logon) from unusual sources
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624} -MaxEvents 50 |
    Where-Object { $_.Properties[8].Value -eq '3' } |
    ForEach-Object { "$($_.TimeCreated) $($_.Properties[5].Value) from $($_.Properties[18].Value)" }

# PsExec artifacts
Get-Service PSEXESVC -ErrorAction SilentlyContinue
Get-ChildItem C:\Windows -Filter "PSEXE*" -ErrorAction SilentlyContinue
```

### 4.9 AD-Specific Attacks (DC Only)

**What to look for:** Kerberoasting, DCSync, Golden Ticket, account enumeration

```powershell
# Kerberoasting -- Event 4769 with encryption type 0x17 (RC4)
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4769} -MaxEvents 100 -ErrorAction SilentlyContinue |
    Where-Object { $_.Properties[5].Value -eq '0x17' } |
    ForEach-Object { "KERBEROAST: $($_.TimeCreated) Target: $($_.Properties[0].Value) From: $($_.Properties[6].Value)" }

# DCSync -- Event 4662 with replication GUIDs
Get-WinEvent -FilterHashtable @{LogName='Security';Id=4662} -MaxEvents 100 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2|1131f6ad-9c07-11d1-f79f-00c04fc2dcd2' }

# Privileged group changes (Domain Admins, Enterprise Admins)
Get-WinEvent -FilterHashtable @{LogName='Security';Id=@(4728,4732,4756)} -MaxEvents 20 -ErrorAction SilentlyContinue

# Unusual LDAP queries (high volume = enumeration)
Get-WinEvent -FilterHashtable @{LogName='Directory Service';Id=1644} -MaxEvents 20 -ErrorAction SilentlyContinue
```

**If found:** Reset the `krbtgt` password TWICE (for Golden Ticket). Disable compromised accounts. Run `.\02-ad.ps1` if not already done.

---

## 5. Common CCDC Attack Patterns

| # | Attack | Earliest | Detection |
|---|--------|----------|-----------|
| 1 | **Default credential login** | 0 min | `w` / `query user` -- unknown sessions before you changed passwords |
| 2 | **Web shell drop** | 0-5 min | New `.php`/`.aspx` in docroot. `hunt-webshells.ps1` |
| 3 | **Cron/task reverse shell** | 5-15 min | `* * * * * bash -i >& /dev/tcp/...`. `hunt-persistence.sh` |
| 4 | **SSH key planting** | 5-15 min | New entries in `~/.ssh/authorized_keys`. `hunt-persistence.sh` |
| 5 | **Backdoor UID 0 account** | 5-15 min | `awk -F: '$3==0' /etc/passwd` shows extra users |
| 6 | **Service binary replacement** | 15-30 min | Service binary hash changed. `hunt-persistence.sh` |
| 7 | **WMI persistence** | 15-30 min | `hunt-persistence.ps1` |
| 8 | **Password reuse / credential stuffing** | Ongoing | Event 4625 brute force from single IP |
| 9 | **PrintNightmare exploitation** | 0-15 min | Spooler crash, new DLLs in `C:\Windows\System32\spool\drivers\` |
| 10 | **EternalBlue (MS17-010)** | 0-15 min | SMB crash, SYSTEM shell. Patched by `01-blitz.ps1` |
| 11 | **Zerologon (CVE-2020-1472)** | 0-15 min | DC machine account password reset. Patched by `02-ad.ps1` |
| 12 | **DNS poisoning** | 15-60 min | `nslookup` returns wrong IPs. Check DNS zone files |
| 13 | **DNS tunneling / exfil** | 30+ min | High volume of TXT/NULL DNS queries. `ss -ulnp` manual check |
| 14 | **Registry run key persistence** | 15-30 min | `hunt-persistence.ps1` |
| 15 | **PowerShell profile backdoor** | 15-30 min | `hunt-persistence.ps1` |

---

## 6. Decision Trees

### "I Found a Suspicious Process"

```
Found suspicious process
├─ Get details: ps aux | grep <PID>  /  Get-Process -Id <PID> | fl *
├─ Check network connections
│  ├─ Linux:  ss -tnp | grep <PID>
│  └─ Windows: Get-NetTCPConnection -OwningProcess <PID>
├─ Check parent process
│  ├─ Linux:  cat /proc/<PID>/status | grep PPid
│  └─ Windows: (Get-CimInstance Win32_Process -Filter "ProcessId=<PID>").ParentProcessId
├─ Is it connecting to an external IP?
│  ├─ YES → Kill it: kill -9 <PID>  /  Stop-Process -Id <PID> -Force
│  │       Block IP: iptables -I OUTPUT -d <IP> -j DROP
│  │       Check: what spawned it? Cron? Service? Scheduled task?
│  │       Hunt for persistence that will respawn it
│  └─ NO → Check file hash, check binary path
│         Is binary in /tmp, /dev/shm, C:\Users\Public, C:\Windows\Temp?
│         ├─ YES → Kill it, collect the binary for evidence, hunt persistence
│         └─ NO → Monitor it, may be legitimate
```

### "I See Unusual Network Traffic"

```
Unusual network traffic detected
├─ Identify source process
│  ├─ Linux:  ss -tnp | grep <port>  →  get PID
│  └─ Windows: Get-NetTCPConnection -LocalPort <port> | select OwningProcess
├─ Is the remote IP in our network (172.20.x.x)?
│  ├─ YES → Lateral movement. Check if the remote box is compromised too.
│  │       Alert the person managing that box.
│  └─ NO → Possible C2 beacon or exfil
│         Block the IP immediately at the host firewall
│         Block at zone firewall(s) if possible
├─ Kill the process
├─ Check for persistence that will re-establish the connection
│  ├─ Linux: cron, services, profile scripts
│  └─ Windows: tasks, services, registry run keys, WMI
├─ If UDP and periodic → run ss -ulnp (Linux) / Get-NetUDPEndpoint (Windows)
```

### "A Scored Service Is Down"

```
Scored service not responding
├─ Is the process running?
│  ├─ Linux:  systemctl status <service>  /  ss -tlnp | grep <port>
│  └─ Windows: Get-Service <name>  /  Get-NetTCPConnection -State Listen
├─ Process NOT running
│  ├─ Try restart: systemctl restart <service>  /  Restart-Service <name>
│  ├─ Check config: apache2ctl configtest / httpd -t / named-checkconf
│  ├─ Check logs: journalctl -u <service> -n 50 / Event Viewer
│  ├─ Restore service: systemctl restart SERVICE_NAME (manual)
│  └─ Still won't start? Check if binary was replaced/deleted
│     Compare hash against known good, reinstall package if needed
├─ Process IS running but service fails
│  ├─ Check port binding: ss -tlnp | grep <port>
│  │   Something else listening? Kill it.
│  ├─ Check firewall: iptables -L -n / Get-NetFirewallRule
│  │   Did hardening block the port? Add exception.
│  ├─ Check from scoring engine perspective (external test)
│  └─ Check DNS if applicable: nslookup <domain> localhost
├─ If service keeps dying repeatedly
│  ├─ Attacker may be killing it. Start monitoring:
│  │   watch -n5 'systemctl status <service>'
│  ├─ Check for malicious cron/task that stops the service
│  └─ Consider: is the binary trojaned? Reinstall from package manager
```

### "I Think an Account Is Compromised"

```
Suspected compromised account
├─ Check active sessions
│  ├─ Linux:  w  →  is the user logged in?
│  └─ Windows: query user  /  .\ir-kill.ps1
├─ Kill their sessions immediately
│  ├─ Linux:  pkill -9 -u <username>
│  └─ Windows: .\ir-kill.ps1
├─ Change the password
│  ├─ Linux:  echo "<user>:<newpass>" | chpasswd
│  └─ Windows: net user <user> "<newpass>"
├─ Check for persistence left behind
│  ├─ SSH keys: cat /home/<user>/.ssh/authorized_keys
│  ├─ Cron: crontab -l -u <user>
│  ├─ Profile: cat /home/<user>/.bashrc  (check last lines)
│  ├─ Windows: .\hunt-persistence.ps1
│  └─ Scheduled tasks owned by user
├─ Check what they did
│  ├─ Linux:  cat /home/<user>/.bash_history
│  ├─ Linux:  grep <user> /var/log/auth.log
│  └─ Windows: Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624} |
│              Where {$_.Properties[5].Value -eq '<user>'}
├─ If it's a service account or admin account
│  └─ Assume they pivoted. Check all machines this account has access to.
```

---

## 7. Splunk Quick Queries

> Splunk server: check `config.env` for `SPLUNK_SERVER` IP

Copy-paste these into the Splunk search bar. Adjust `index=` as needed.

### 7.1 Failed Logins (Brute Force)

```spl
index=* (source="/var/log/auth.log" OR source="/var/log/secure" OR EventCode=4625)
| stats count by src_ip, user
| where count > 5
| sort -count
```

### 7.2 Successful Logins from Unusual Sources

```spl
index=* (EventCode=4624 OR "Accepted password" OR "Accepted publickey")
| stats count values(src_ip) by user, host
| sort -count
```

### 7.3 New Processes from Temp Directories

```spl
index=* (EventCode=4688 OR source="/var/log/audit/audit.log" type=EXECVE)
| search (CommandLine="*\\Temp\\*" OR CommandLine="*/tmp/*" OR CommandLine="*/dev/shm/*")
| table _time host user CommandLine
```

### 7.4 Suspicious Network Connections

```spl
index=* sourcetype=*network* OR sourcetype=*firewall*
| search dest_port IN (4444,5555,6666,7777,8888,9999,1234,31337)
| table _time src_ip dest_ip dest_port action
```

### 7.5 Service Installations (Windows)

```spl
index=* EventCode=7045
| table _time host ServiceName ImagePath AccountName
| sort -_time
```

### 7.6 Scheduled Task Creation

```spl
index=* (EventCode=4698 OR "crontab" OR "CRON")
| table _time host user TaskName CommandLine
| sort -_time
```

### 7.7 PowerShell Script Block Logging

```spl
index=* EventCode=4104
| search ScriptBlockText!="prompt"
| table _time host ScriptBlockText
| sort -_time
```

### 7.8 Account Creation / Privilege Escalation

```spl
index=* (EventCode=4720 OR EventCode=4728 OR EventCode=4732 OR EventCode=4756)
| table _time host EventCode user TargetUserName GroupName
| sort -_time
```

### 7.9 Web Shell Access (HTTP POST to Unusual Files)

```spl
index=* sourcetype=*access* method=POST
| search (uri="*.aspx" OR uri="*.php" OR uri="*.jsp" OR uri="*.ashx")
| stats count by uri, src_ip, status
| where count > 3
| sort -count
```

### 7.10 DNS Anomalies (Tunneling / Exfil)

```spl
index=* sourcetype=*dns*
| eval query_len=len(query)
| where query_len > 50 OR query_type="TXT" OR query_type="NULL"
| stats count by query, query_type, src_ip
| sort -count
```

---

## 8. Emergency Response Procedures

### 8.1 Active Attacker Detected

**Situation:** You see an unknown session, suspicious process, or active C2 connection.

1. **DO NOT PANIC.** Breathe. You have time.
2. **Identify** -- What machine? What user? What IP?
3. **Kill their session**
   - Linux: `pkill -9 -u <user>` or `> script ir-kill.sh`
   - Windows: `.\ir-kill.ps1`
4. **Block their IP** at the host AND at the zone firewall(s)
   - Linux: `iptables -I INPUT -s <IP> -j DROP && iptables -I OUTPUT -d <IP> -j DROP`
   - Windows: `New-NetFirewallRule -DisplayName "Block" -Direction Inbound -RemoteAddress <IP> -Action Block`
5. **Change passwords** for any accounts they touched
6. **Hunt for persistence** -- they likely left a backdoor
   - Linux: `> script hunt-persistence.sh`
   - Windows: `.\hunt-persistence.ps1`
7. **Check other machines** -- did they pivot?
8. **Collect evidence** (if time permits)
   - Linux: `> script ir-collect.sh`
   - Windows: `.\ir-triage.ps1`

### 8.2 Mass Compromise (Multiple Machines)

**Situation:** Attacker is on 3+ machines simultaneously.

1. **Triage** -- which machines are scored services on? Prioritize those.
2. **Change ALL passwords** via Monarch: `> rotate`
3. **Kill sessions everywhere**
   - Linux (Monarch): `> rotate`
   - Windows: run `.\ir-kill.ps1` on each
4. **Hunt persistence on every machine** -- divide team members
5. **Block attacker IP(s)** at all zone firewalls -- this stops them from ALL machines at once
6. **Deploy monitoring** on all boxes to catch re-entry
7. **Consider VM scrub** if a machine is deeply compromised (limited count, costs points)

### 8.3 Ransomware / Wiper Detected

**Situation:** Files being encrypted or deleted en masse.

1. **IMMEDIATELY** isolate the machine from the network
   - Linux: `sudo ip link set <iface> down` (find name with `ip link show`)
   - Windows: `Disable-NetAdapter -Name "Ethernet" -Confirm:$false`
2. **Kill the encrypting/deleting process** -- `kill -9` / `Stop-Process -Force`
3. **Assess damage** -- are scored service files intact?
4. **If scored service data is destroyed** → VM scrub is likely fastest recovery
5. **If caught early** → restore from backups/package manager, restart services
6. **Bring network back up carefully** after removing malware
   - Linux: `sudo ip link set <iface> up`
   - Windows: `Enable-NetAdapter -Name "Ethernet"`
7. **Hunt for the entry point** -- how did ransomware get in?

### 8.4 Scored Service Keeps Going Down

**Situation:** Service comes back up but keeps dying every few minutes.

1. **Check for kill cron/task**
   - Linux: `grep -r 'stop\|kill\|pkill' /var/spool/cron/ /etc/cron.d/`
   - Windows: `Get-ScheduledTask | Where {$_.Actions.Execute -match 'stop|kill|taskkill'}`
2. **Check if binary was replaced** with a crashing version
   - Linux: `rpm -V <package>` or `dpkg --verify <package>`
   - Reinstall: `apt install --reinstall <package>` / `dnf reinstall <package>`
3. **Check for competing process** on the same port
   - `ss -tlnp | grep :<port>` -- is something else binding the port?
4. **Watch it in real time** -- `watch -n2 'systemctl status <service>; ss -tlnp | grep :<port>'`
5. **Check resource exhaustion** -- disk full? Out of memory?
   - `df -h` / `free -m`
6. **Set up monitoring** to catch the kill event
   - `> script 05-monitor.sh`
   - `.\05-monitor.ps1`

---

## 9. Quick Command Reference

| Operation | Linux | Windows |
|-----------|-------|---------|
| **List all users** | `cut -d: -f1 /etc/passwd` | `Get-LocalUser` |
| **List active sessions** | `w` | `query user` |
| **Find process by name** | `ps aux \| grep <name>` | `Get-Process -Name <name>` |
| **Find process by PID** | `ps -p <PID> -f` | `Get-Process -Id <PID>` |
| **Process tree** | `ps auxf` | `Get-CimInstance Win32_Process \| Select ProcessId,ParentProcessId,Name` |
| **List network connections** | `ss -tulpn` | `Get-NetTCPConnection` |
| **Established only** | `ss -tnp state established` | `Get-NetTCPConnection -State Established` |
| **Kill process** | `kill -9 <PID>` | `Stop-Process -Id <PID> -Force` |
| **Kill all user procs** | `pkill -9 -u <user>` | `.\ir-kill.ps1` |
| **Block an IP** | `iptables -I INPUT -s <IP> -j DROP` | `New-NetFirewallRule -DisplayName "Block" -Direction Inbound -RemoteAddress <IP> -Action Block` |
| **Unblock an IP** | `iptables -D INPUT -s <IP> -j DROP` | `Remove-NetFirewallRule -DisplayName "Block"` |
| **Check recent logins** | `last -20` | `Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624} -MaxEvents 20` |
| **Check failed logins** | `grep "Failed password" /var/log/auth.log` | `Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 20` |
| **Find recently modified files** | `find / -mmin -60 -type f 2>/dev/null` | `Get-ChildItem C:\ -Recurse -File \| Where {$_.LastWriteTime -gt (Get-Date).AddHours(-1)}` |
| **Check cron / tasks** | `crontab -l; ls /etc/cron.d/` | `Get-ScheduledTask \| Where {$_.State -ne 'Disabled'}` |
| **Check services** | `systemctl list-units --type=service --state=running` | `Get-Service \| Where {$_.Status -eq 'Running'}` |
| **Change password** | `echo "user:pass" \| chpasswd` | `net user <user> "<pass>"` |
| **Restart service** | `systemctl restart <service>` | `Restart-Service <name>` |
| **Firewall rules** | `iptables -L -n` | `Get-NetFirewallRule \| Where {$_.Enabled -eq 'True'}` |
| **Check listening ports** | `ss -tlnp` | `Get-NetTCPConnection -State Listen` |
| **DNS lookup test** | `nslookup <domain> localhost` | `Resolve-DnsName <domain> -Server localhost` |
| **Download file** | `curl -O <url>` or `wget <url>` | `Invoke-WebRequest -Uri <url> -OutFile <file>` |
| **File hash** | `sha256sum <file>` | `Get-FileHash <file> -Algorithm SHA256` |

---

## Appendix: Script Quick Reference

**Linux Scripts (via Monarch: `> script SCRIPTNAME`)**

| Script | Purpose |
|--------|---------|
| `00-snapshot.sh` | Forensic baseline before changes |
| `01-harden.sh` | Full system hardening (users, SSH, kernel, permissions, services) |
| `02-firewall.sh` | Auto-detect services, apply firewall rules |
| `03-services.sh` | Harden running services (web, DB, mail, FTP, DNS) |
| `04-splunk.sh` | Deploy Splunk forwarder |
| `05-monitor.sh` | Deploy auditd + monitoring |
| `hunt-persistence.sh` | Full persistence hunt (cron, services, users, SUID, PAM, LD_PRELOAD) |
| `hunt-pii.sh` | PII/compliance scanner |
| `ir-triage.sh` | Quick system triage |
| `ir-kill.sh` | Kill attacker sessions |
| `ir-collect.sh` | Forensic evidence collection |
| `ir-isolate.sh` | Network isolation |

**Windows Scripts (from `C:\ccdc26\dovetail\scripts\`)**

| Script | Purpose |
|--------|---------|
| `00-snapshot.ps1` | Forensic baseline (AD, DNS, tasks, services) |
| `01-blitz.ps1` | Full hardening (CVEs, Defender, firewall, services) |
| `02-ad.ps1` | DC hardening (Zerologon, noPac, Kerberos, krbtgt) |
| `03-audit.ps1` | Audit policies + PowerShell logging |
| `04-splunk.ps1` | Deploy Splunk forwarder |
| `05-monitor.ps1` | Real-time process/network/session monitoring |
| `hunt-persistence.ps1` | 13-category persistence scan |
| `hunt-webshells.ps1` | IIS webshell detection |
| `hunt-golden.ps1` | Golden ticket detection |
| `ir-triage.ps1` | Incident triage |
| `ir-kill.ps1` | Kill sessions + block IPs |
| `sanity-check.ps1` | Validate hardening applied |

### Findings Logs

| Platform | Location |
|----------|----------|
| Linux | `/var/log/ccdc-toolkit/findings.log` |
| Linux monitors | `/var/log/ccdc-toolkit/file-monitor.log`, `process-monitor.log`, `network-monitor.log` |
| Windows persistence | `C:\ccdc26\logs\findings.log` |
| Windows monitors | `C:\ccdc26\logs\process-monitor.log`, `network-monitor.log`, `session-monitor.log` |
| Windows webshell | `C:\ccdc26\logs\webshell-scan.log` |
| Windows triage evidence | `C:\ccdc26\evidence\triage-<timestamp>\` |

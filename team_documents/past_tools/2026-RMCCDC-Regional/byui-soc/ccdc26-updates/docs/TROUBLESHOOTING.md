# CCDC26 Troubleshooting Guide

Common issues and solutions for Monarch, Dovetail, Splunk, and network connectivity.

---

## Table of Contents

1. [Monarch Issues (Linux)](#monarch-issues-linux)
2. [Dovetail / WinRM Issues (Windows)](#dovetail--winrm-issues-windows)
3. [Network Connectivity Issues](#network-connectivity-issues)
4. [Splunk Forwarder Issues](#splunk-forwarder-issues)

---

## Monarch Issues (Linux)

### Problem: Python not found or wrong version

```bash
# Check version (need 3.8+)
python3 --version

# Fedora/RHEL
sudo dnf install -y python3

# Ubuntu/Debian
sudo apt install -y python3
```

### Problem: paramiko / dependencies install fails

```bash
# Install build deps first
sudo dnf install -y python3-pip python3-devel gcc       # Fedora/RHEL
sudo apt install -y python3-pip python3-dev gcc          # Ubuntu/Debian

# Then install
pip3 install paramiko
```

If pip is broken or missing:

```bash
python3 -m ensurepip --upgrade
python3 -m pip install paramiko
```

### Problem: sshpass not found

```bash
sudo dnf install -y sshpass       # Fedora/RHEL
sudo apt install -y sshpass       # Ubuntu/Debian
```

### Problem: SSH connection refused / timeout

**Symptoms:** `scan` finds no hosts, `shell` hangs or fails.

1. Verify the target is reachable: `ping <target-ip>`
2. Verify SSH is running on target: `nc -zv <target-ip> 22`
3. Check if host firewall is blocking: `sudo iptables -L -n | grep 22`
4. Try manual SSH: `ssh sysadmin@<target-ip>` -- does it prompt for password?
5. Check Monarch password: `list` -- verify stored password is correct
6. Update password: `edit <host> password <newpass>`

### Problem: "Host key verification failed"

Monarch should handle this automatically. If not:

```bash
ssh-keyscan -H <target-ip> >> ~/.ssh/known_hosts
```

### Problem: Script fails on some hosts

```bash
# Run on just that host to see errors
> script -H <host> 01-harden.sh

# Or get a shell and run manually
> shell <host>
$ cd /opt/ccdc26/monarch/scripts && bash 01-harden.sh
```

### Problem: Monarch REPL won't start

```bash
# Verify you're in the right directory
cd /opt/ccdc26/monarch

# Run directly
python3 -m monarch

# If module not found, check structure
ls monarch/__main__.py    # Should exist
```

---

## Dovetail / WinRM Issues (Windows)

### Problem: WinRM service not running

```powershell
# Check service
Get-Service WinRM

# Enable and start
winrm quickconfig -y
Enable-PSRemoting -Force
Set-Service WinRM -StartupType Automatic
Start-Service WinRM

# Verify
Test-WSMan localhost
```

### Problem: Dovetail -Connect fails / timeout

1. Check WinRM port from source machine:

```powershell
Test-NetConnection -ComputerName <target-ip> -Port 5985
```

2. If blocked, check Windows Firewall on target:

```powershell
# On target machine:
Get-NetFirewallRule -Name "*WinRM*" | Where-Object { $_.Enabled -eq $true }

# Add rule if missing:
New-NetFirewallRule -DisplayName "WinRM" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow
```

3. If cross-zone (Linux → Windows), configure the zone firewall to allow source subnet → target port 5985

### Problem: WinRM authentication fails

```powershell
# Verify credentials work locally
Enter-PSSession -ComputerName <target> -Credential (Get-Credential)

# For non-domain machines, use -NonDomain flag:
.\dovetail.ps1 -Connect -Targets "<ip>" -NonDomain

# Check trusted hosts on target
Get-Item WSMan:\localhost\Client\TrustedHosts

# Allow all (CCDC acceptable):
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### Problem: Dovetail dispatch hangs

1. Check session health:

```powershell
Get-PSSession | Format-Table ComputerName, State
```

2. Repair broken sessions:

```powershell
.\dovetail.ps1 -Repair
```

3. If a specific host is stuck, exclude it:

```powershell
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1 -Exclude "BROKEN_HOST"
```

### Problem: Firewall blocks Dovetail from DC to other machines

```powershell
# On each target machine, allow WinRM from DC subnet
New-NetFirewallRule -DisplayName "WinRM from DC" -Direction Inbound -RemoteAddress <dc-subnet>/24 -LocalPort 5985 -Protocol TCP -Action Allow
```

---

## Network Connectivity Issues

### Problem: Linux hosts cannot reach Windows hosts

**Root causes:** Zone firewall blocking cross-zone traffic, Windows Firewall, WinRM not enabled.

1. Configure zone firewall: Allow Linux subnet → Windows subnet (TCP 5985, ICMP)
2. On Windows hosts:

```powershell
New-NetFirewallRule -DisplayName "Allow Linux Subnet" -Direction Inbound -RemoteAddress <linux-subnet>/24 -Action Allow
```

3. Test: `ping <windows-ip>` and `nc -zv <windows-ip> 5985`

### Problem: Windows hosts cannot reach Linux hosts

1. Check zone firewall rules: Allow Windows subnet → Linux subnet
2. On Linux hosts:

```bash
sudo iptables -A INPUT -s <windows-subnet>/24 -j ACCEPT
```

---

## Splunk Forwarder Issues

### Problem: Forwarder cannot connect to server

1. Test connectivity:

```bash
nc -zv <splunk-server-ip> 9997                                    # Linux
```

```powershell
Test-NetConnection -ComputerName <splunk-server-ip> -Port 9997    # Windows
```

2. Check firewall rules: Forwarder needs outbound TCP 9997, server needs inbound TCP 9997
3. Verify server is listening:

```bash
ss -tlnp | grep 9997          # On Splunk server
```

4. Check forwarder config:

```bash
cat /opt/splunkforwarder/etc/system/local/outputs.conf             # Linux
```

```powershell
Get-Content "C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf"  # Windows
```

### Problem: Forwarder installed but no data in Splunk

1. Check forwarder status:

```bash
/opt/splunkforwarder/bin/splunk status                             # Linux
```

```powershell
Get-Service SplunkForwarder                                        # Windows
```

2. Check forwarder logs for errors:

```bash
tail -50 /opt/splunkforwarder/var/log/splunk/splunkd.log
```

3. Verify indexes exist on server:

```bash
/opt/splunk/bin/splunk list index -auth admin:changeme | grep -E "linux-|windows-"
```

### Problem: Splunk forwarder binary not found after install

Download failed silently. Manual install:

```bash
cd /tmp
wget https://download.splunk.com/products/universalforwarder/releases/10.2.0/linux/splunkforwarder-10.2.0-d749cb17ea65-linux-amd64.tgz
tar -xzf splunkforwarder-*.tgz -C /opt/
ls /opt/splunkforwarder/bin/splunk    # Verify
```

---

## Quick Diagnostics

```bash
# Test network from Linux
ping <target-ip>
nc -zv <target-ip> <port>

# Check Monarch host list
cd /opt/ccdc26/monarch && python3 -m monarch list

# Check Splunk forwarder
/opt/splunkforwarder/bin/splunk status

# Check firewall rules (Linux)
sudo iptables -L -n -v
sudo ufw status verbose
```

```powershell
# Test WinRM
Test-WSMan <target>
Get-PSSession | ft ComputerName, State

# Check Splunk forwarder
Get-Service SplunkForwarder

# Check firewall rules (Windows)
Get-NetFirewallRule | Where-Object {$_.Enabled -eq 'True'} | ft Name, Direction, Action
```

# CCDC26 Troubleshooting Guide

Common issues and solutions for the CCDC26 defense toolkit.

## Table of Contents

1. [Network Connectivity Issues](#network-connectivity-issues)
2. [Ansible Connection Problems](#ansible-connection-problems)
3. [Splunk Forwarder Issues](#splunk-forwarder-issues)
4. [Windows WinRM Issues](#windows-winrm-issues)
5. [OS Detection Problems](#os-detection-problems)

---

## Network Connectivity Issues

### Problem: Linux hosts cannot reach Windows hosts

**Symptoms**:
- Ping from Linux to Windows fails
- Ansible cannot connect to Windows hosts
- `ansible windows -i inventory.ini -m win_ping` fails

**Root Causes**:
1. Cisco FTD firewall blocking traffic from Linux subnet (172.20.242.0/24) to Windows subnet (172.20.240.0/24)
2. Windows Firewall not configured to allow Linux subnet
3. WinRM not enabled on Windows hosts

**Solutions**:

1. **Configure Windows Firewall** (on each Windows host):
   ```powershell
   # Run as Administrator:
   cd C:\ccdc26\windows-scripts
   .\Setup-WinRM-Ansible.ps1
   ```
   This script:
   - Enables WinRM service
   - Configures firewall to allow Linux subnet (172.20.242.0/24)
   - Tests connectivity

2. **Configure Cisco FTD Firewall** (manual step):
   - Access FTD web interface: https://172.20.240.200 (from Windows host)
   - Create rule allowing:
     - Source: 172.20.242.0/24 (Linux subnet)
     - Destination: 172.20.240.0/24 (Windows subnet)
     - Service: TCP 5985 (WinRM), ICMP
   - Apply and commit changes

3. **Test connectivity**:
   ```bash
   # From Linux host:
   ping 172.20.240.100  # Should succeed
   nc -zv 172.20.240.100 5985  # Should show port open
   
   # From Ansible controller:
   ansible-playbook -i ansible/inventory.ini ansible/test-network-connectivity.yml
   ```

### Problem: Windows hosts cannot reach Linux hosts

**Symptoms**:
- Ping from Windows to Linux fails
- Windows cannot SSH to Linux hosts

**Solutions**:
1. Check Palo Alto firewall rules (allow Windows subnet to Linux subnet)
2. Verify Linux firewall allows Windows subnet:
   ```bash
   # On Linux host:
   sudo ufw allow from 172.20.240.0/24
   # Or for iptables:
   sudo iptables -A INPUT -s 172.20.240.0/24 -j ACCEPT
   ```

---

## Ansible Connection Problems

### Problem: "Host key checking failed"

**Solution**:
```bash
# Option 1: Disable globally (CCDC acceptable)
export ANSIBLE_HOST_KEY_CHECKING=False

# Option 2: Configure in ansible.cfg (already set)
# See ansible/ansible.cfg

# Option 3: Accept keys manually
ssh sysadmin@172.20.242.30  # Type 'yes' when prompted
```

### Problem: "Missing sudo password"

**Symptoms**:
- Ansible fails with "Missing sudo password" error
- Some hosts work, others don't

**Solutions**:
1. **Check inventory.ini** - Ensure `ansible_become_pass` is set per-host:
   ```ini
   ecom ansible_host=172.20.242.30 ansible_user=sysadmin ansible_password=changeme ansible_become_pass=changeme
   ```

2. **Use prompt mode** (in deploy.sh):
   - Select option 2 (Ansible Control Panel)
   - Select option 9 (Change auth mode)
   - Choose option 1 (Prompt for passwords)

3. **Verify sudo configuration** on target host:
   ```bash
   # On target Linux host:
   sudo -l  # Should show NOPASSWD or require password
   ```

### Problem: "Module not found" or Python interpreter errors

**Symptoms**:
- Ansible fails with "The module was not found" or "No module named..."
- Oracle Linux or Fedora hosts fail

**Solutions**:
1. **Verify Python 3 is installed**:
   ```bash
   # On target host:
   python3 --version
   which python3
   ```

2. **Set Python interpreter in inventory.ini**:
   ```ini
   [linux:vars]
   ansible_python_interpreter=/usr/bin/python3
   # Or for Oracle Linux:
   ansible_python_interpreter=/usr/libexec/platform-python
   ```

3. **The playbook now auto-detects Python** - this should be handled automatically.

### Problem: WinRM connection timeout

**Symptoms**:
- Ansible hangs when connecting to Windows hosts
- Timeout errors after 30+ seconds

**Solutions**:
1. **Check WinRM service** (on Windows host):
   ```powershell
   Get-Service WinRM  # Should be Running
   Test-WSMan localhost  # Should succeed
   ```

2. **Verify firewall rules**:
   ```powershell
   Get-NetFirewallRule -Name "*WinRM*" | Where-Object { $_.Enabled -eq $true }
   ```

3. **Increase timeout in ansible.cfg** (already configured):
   ```ini
   [winrm]
   connection_timeout = 60
   operation_timeout = 60
   ```

4. **Test connectivity manually**:
   ```powershell
   # From Windows host:
   Test-NetConnection -ComputerName <linux-ip> -Port 5985
   ```

---

## Splunk Forwarder Issues

### Problem: Splunk forwarder cannot connect to server

**Symptoms**:
- Forwarder installed but no data in Splunk
- Connection refused errors in splunkd.log

**Solutions**:
1. **Test connectivity** (on forwarder host):
   ```bash
   # Linux:
   nc -zv 172.20.242.20 9997
   
   # Windows:
   Test-NetConnection -ComputerName 172.20.242.20 -Port 9997
   ```

2. **Check firewall rules**:
   - Forwarder: Allow outbound TCP 9997
   - Server: Allow inbound TCP 9997 from forwarder subnets

3. **Verify server is receiving**:
   ```bash
   # On Splunk server (172.20.242.20):
   /opt/splunk/bin/splunk list forward-server -auth admin:changeme
   ss -tlnp | grep 9997
   ```

4. **Check forwarder configuration**:
   ```bash
   # Linux:
   cat /opt/splunkforwarder/etc/system/local/outputs.conf
   
   # Windows:
   Get-Content "C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf"
   ```

### Problem: Splunk forwarder binary not found after installation

**Symptoms**:
- Installation appears to complete but `/opt/splunkforwarder/bin/splunk` doesn't exist
- Download fails silently

**Solutions**:
1. **Verify download URL** - The scripts use version 10.2.0 with build hash:
   ```bash
   # Test URL directly:
   curl -I "https://download.splunk.com/products/universalforwarder/releases/10.2.0/linux/splunkforwarder-10.2.0-d749cb17ea65-linux-amd64.tgz"
   ```

2. **Manual installation**:
   ```bash
   cd /tmp
   wget https://download.splunk.com/products/universalforwarder/releases/10.2.0/linux/splunkforwarder-10.2.0-d749cb17ea65-linux-amd64.tgz
   tar -xzf splunkforwarder-10.2.0-d749cb17ea65-linux-amd64.tgz -C /opt/
   ls -la /opt/splunkforwarder/bin/splunk  # Verify it exists
   ```

### Problem: Indexes not found on Splunk server

**Symptoms**:
- Forwarders sending data but events show "index not found"
- Data goes to default index

**Solutions**:
1. **Create indexes on server** (run on 172.20.242.20):
   ```bash
   cd /opt/ccdc26/linux-scripts/tools
   ./splunk-server.sh indexes
   ```

2. **Verify indexes exist**:
   ```bash
   /opt/splunk/bin/splunk list index -auth admin:changeme | grep -E "linux-|windows-"
   ```

---

## Windows WinRM Issues

### Problem: WinRM service not running

**Symptoms**:
- Ansible cannot connect to Windows hosts
- `ansible windows -i inventory.ini -m win_ping` fails

**Solutions**:
1. **Run setup script**:
   ```powershell
   # As Administrator:
   cd C:\ccdc26\windows-scripts
   .\Setup-WinRM-Ansible.ps1
   ```

2. **Manual setup**:
   ```powershell
   winrm quickconfig -y
   Enable-PSRemoting -Force
   Set-Service WinRM -StartupType Automatic
   Start-Service WinRM
   ```

3. **Verify service**:
   ```powershell
   Get-Service WinRM  # Should show Running
   Test-WSMan localhost  # Should succeed
   ```

### Problem: WinRM authentication fails

**Symptoms**:
- Ansible connects but authentication fails
- "Authentication failure" errors

**Solutions**:
1. **Check inventory.ini credentials**:
   ```ini
   [windows]
   ad-dns ansible_host=172.20.240.102 ansible_user=administrator ansible_password=!Password123
   ```

2. **Verify WinRM transport** (in inventory.ini):
   ```ini
   [windows:vars]
   ansible_connection=winrm
   ansible_winrm_transport=ntlm  # or basic, credssp
   ```

3. **Test authentication manually**:
   ```powershell
   # From Linux (if pywinrm installed):
   python3 -c "import winrm; s = winrm.Session('172.20.240.102', auth=('administrator', '!Password123')); print(s.run_cmd('hostname').stdout)"
   ```

---

## OS Detection Problems

### Problem: Ansible cannot detect OS correctly

**Symptoms**:
- Playbook fails with "OS not supported"
- Oracle Linux detected as unknown
- Fedora uses wrong package manager

**Solutions**:
1. **The playbook now has improved OS detection** - it handles:
   - Oracle Linux (detected as RHEL family)
   - Fedora (uses dnf instead of yum)
   - Python interpreter auto-detection

2. **Manual OS detection**:
   ```bash
   ansible all -i inventory.ini -m setup -a "filter=ansible_distribution*"
   ```

3. **Override in inventory.ini** (if needed):
   ```ini
   splunk ansible_host=172.20.242.20 ansible_user=sysadmin ansible_python_interpreter=/usr/libexec/platform-python
   ```

---

## Quick Diagnostic Commands

### Test Ansible connectivity:
```bash
# Test all hosts:
ansible all -i ansible/inventory.ini -m ping

# Test Windows only:
ansible windows -i ansible/inventory.ini -m win_ping

# Test Linux only:
ansible linux -i ansible/inventory.ini -m ping
```

### Test network connectivity:
```bash
# Run comprehensive network test:
ansible-playbook -i ansible/inventory.ini ansible/test-network-connectivity.yml
```

### Check Splunk forwarder status:
```bash
# On forwarder (Linux):
/opt/splunkforwarder/bin/splunk status
tail -f /opt/splunkforwarder/var/log/splunk/splunkd.log

# On forwarder (Windows):
Get-Service SplunkForwarder
& "C:\Program Files\SplunkUniversalForwarder\bin\splunk.exe" status

# On server (172.20.242.20):
/opt/splunk/bin/splunk list forward-server -auth admin:changeme
/opt/splunk/bin/splunk search "index=linux-* | stats count by host" -auth admin:changeme
```

### Check firewall rules:
```bash
# Linux (iptables):
sudo iptables -L -n -v

# Linux (ufw):
sudo ufw status verbose

# Windows:
Get-NetFirewallRule -Name "*WinRM*" | Format-Table Name, Enabled, Direction
```

---

## Getting Help

If issues persist:

1. Check logs:
   - Ansible: Add `-v` or `-vvv` for verbose output
   - Splunk: Check `/opt/splunkforwarder/var/log/splunk/splunkd.log` (Linux) or `C:\Program Files\SplunkUniversalForwarder\var\log\splunk\splunkd.log` (Windows)
   - System: Check `/var/log/` (Linux) or Event Viewer (Windows)

2. Run diagnostics:
   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/test-network-connectivity.yml
   ansible all -i ansible/inventory.ini -m setup
   ```

3. Review documentation:
   - [README.md](README.md) - Main documentation
   - [ansible/README.md](ansible/README.md) - Ansible-specific docs
   - [QUICKREF.md](QUICKREF.md) - Quick reference for competition

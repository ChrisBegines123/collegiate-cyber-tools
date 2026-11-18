# CCDC26 Testing Plan

## Test Environment

| Target | Platform | IP | Purpose |
|--------|----------|-----|---------|
| ccdc-ecom | Ubuntu 22.04 (Docker) | 10.99.0.11 | Linux dispatch target |
| ccdc-webmail | Fedora 39 (Docker) | 10.99.0.12 | Linux dispatch target |
| ccdc-splunk | Rocky 9 (Docker) | 10.99.0.13 | Linux dispatch target |
| ccdc-workstation | Alpine 3.19 (Docker) | 10.99.0.14 | Linux dispatch target |
| ccdc-controller | Ubuntu 22.04 (Docker) | 10.99.0.10 | Monarch REPL host |
| win2k25 | Windows Server 2022 (KVM) | 192.168.122.x | Windows dispatch target |

---

## Test Status Summary

### Linux (Monarch) -- Docker containers

| Test | Status | Notes |
|------|--------|-------|
| SSH connectivity to all 4 targets | PASS | All distros respond |
| 00-snapshot.sh dispatch | PASS | Tarball created on Ubuntu |
| 01-harden.sh execution (Ubuntu) | PASS | All 8 phases complete |
| 01-harden.sh execution (Fedora) | NOT TESTED | |
| 01-harden.sh execution (Rocky) | NOT TESTED | |
| 01-harden.sh execution (Alpine) | NOT TESTED | |
| 02-firewall.sh execution | NOT TESTED | Locked out SSH on first attempt (see notes) |
| 03-services.sh (no services) | NOT TESTED | |
| 04-splunk.sh (no Splunk server) | NOT TESTED | Expected graceful failure |
| 05-monitor.sh auditd rules | NOT TESTED | |
| hunt-persistence.sh | NOT TESTED | |
| hunt-pii.sh | NOT TESTED | |
| IR scripts (triage, kill, collect, isolate) | NOT TESTED | |
| Monarch REPL scan command | NOT TESTED | Raw SSH used instead |
| Monarch REPL rotate command | NOT TESTED | |
| Monarch REPL script dispatch | NOT TESTED | |
| Monarch REPL shell command | NOT TESTED | |
| sanity_check.py | NOT TESTED | |

### Windows (Dovetail) -- KVM VM

| Test | Status | Notes |
|------|--------|-------|
| Windows Server installed | PASS | Windows Server 2022 on KVM, hostname WIN-USVJMMIONJ1 |
| WinRM enabled and reachable | PASS | Basic + NTLM auth, port 5985; NTLM breaks after blitz (expected), Basic works |
| Toolkit copied to C:\ccdc26 | PASS | HTTP download + tar extraction, all 11 scripts verified |
| 00-snapshot.ps1 | PASS | 14 files/127KB captured; AD sections skip gracefully on non-DC |
| 01-blitz.ps1 | PASS | 13 phases in 6.3s; **fixed: LOLBin rules moved after firewall nuke, NetBIOS CIM method, password file msg** |
| 02-ad.ps1 (non-DC, should skip) | PASS | Silent exit, no errors, no changes |
| 03-audit.ps1 | PASS | 59 audit subcategories, cmdline auditing, PS logging, firewall logging, registry SACLs |
| 04-splunk.ps1 (no Splunk server) | NOT TESTED | Expected graceful failure |
| 05-monitor.ps1 | PASS | 3 background jobs started (process/network/session); note: jobs are session-scoped in WinRM |
| hunt-persistence.ps1 | PASS | All 13 categories execute, 198 findings (expected built-ins), completed in 5.4s |
| hunt-webshells.ps1 (no IIS) | PASS | **Fixed: now detects IIS not installed and exits 0 with info message** |
| hunt-golden.ps1 | PASS | Graceful "no suspicious tickets" on standalone server |
| ir-triage.ps1 | PASS | Shows processes, connections, tasks, filesystem anomalies; 32 findings (DISM temp files) |
| ir-kill.ps1 | PASS | **Fixed: qwinsta parser no longer truncates usernames**; shows sessions, identifies team members |
| sanity-check.ps1 | PASS | 26 PASS / 0 FAIL / 0 WARN after blitz |
| Dovetail dispatch from host | PASS | **Fixed: added Basic auth + AllowUnencrypted for NonDomain mode**; dispatch+collect works |
| deploy.ps1 bootstrap download | NOT TESTED | |

---

## Phase 1: Windows VM Post-Install Setup

Complete these steps as soon as Windows Server 2022 setup finishes.

### 1.1 Set Administrator Password

The installer will prompt for this. Use something memorable for testing: `Changeme123!`

### 1.2 Get the VM's IP Address

From the Windows desktop, open PowerShell as Admin:
```powershell
ipconfig | findstr "IPv4"
```
Expected: `192.168.122.x` (from libvirt DHCP)

Verify from your Arch host:
```bash
sudo virsh domifaddr win2k25
ping 192.168.122.x
```

### 1.3 Enable WinRM

On the Windows VM, PowerShell as Admin:
```powershell
winrm quickconfig -y
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any
```

Verify from your Arch host:
```bash
# Install pywinrm if not present
pip3 install pywinrm

# Test WinRM connectivity
python3 -c "
import winrm
s = winrm.Session('http://192.168.122.x:5985/wsman', auth=('Administrator', 'Changeme123!'), transport='basic')
r = s.run_cmd('hostname')
print(r.std_out.decode())
"
```

### 1.4 Copy Toolkit to VM

**Option A: Shared folder (fastest)**
```bash
# From Arch host -- serve the repo
cd /home/thule/Cyber/CCDC/ccdc26
python3 -m http.server 8080 &
```
Then in the Windows VM PowerShell:
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "http://192.168.122.1:8080/" -UseBasicParsing
# If that works, the host is reachable. Now download the repo as a zip:
# (You need to zip it first on the host, or use git in the VM)
```

**Option B: Git clone in VM**
```powershell
# If git is available or you install it:
git clone https://github.com/byui-soc/ccdc26.git C:\ccdc26
```

**Option C: Manual copy via RDP**
```bash
# From Arch host
sudo virt-viewer win2k25
# Use RDP clipboard or drag-and-drop
```

### 1.5 Take a VM Snapshot

Before running any scripts, take a clean snapshot so you can revert:
```bash
sudo virsh snapshot-create-as win2k25 "clean-install" "Fresh Windows Server 2022 with WinRM"
```

Revert anytime with:
```bash
sudo virsh snapshot-revert win2k25 "clean-install"
```

---

## Phase 2: Windows Script Testing (Individual)

Run each script individually on the Windows VM. Test in this order.
After EACH test, verify the VM is still functional (RDP works, PowerShell works).

### 2.1 Test 00-snapshot.ps1

```powershell
cd C:\ccdc26\dovetail\scripts
.\00-snapshot.ps1
```

**Verify:**
- [ ] Script completes without errors
- [ ] Snapshot directory created at `C:\ccdc26\snapshots\`
- [ ] Contains: users, groups, services, tasks, firewall rules, processes, network connections
- [ ] If not a DC: AD-specific sections skip gracefully (no errors)

### 2.2 Test 01-blitz.ps1 (CRITICAL -- most important test)

**Take a snapshot first:**
```bash
sudo virsh snapshot-create-as win2k25 "pre-blitz" "Before 01-blitz.ps1"
```

```powershell
cd C:\ccdc26\dovetail\scripts
.\01-blitz.ps1
```

**Verify:**
- [ ] Script completes without errors
- [ ] SMBv1 disabled: `Get-SmbServerConfiguration | Select EnableSMB1Protocol` -> False
- [ ] Print Spooler stopped but Manual: `Get-Service Spooler | Select Status, StartType`
- [ ] LSASS RunAsPPL set: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL`
- [ ] WDigest disabled: `reg query "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" /v UseLogonCredential`
- [ ] Windows Firewall enabled: `Get-NetFirewallProfile | Select Name, Enabled, DefaultInboundAction`
- [ ] LOLBin rules exist: `Get-NetFirewallRule -DisplayName "CCDC-Block*" | Select DisplayName, Enabled`
- [ ] UAC enforced: `reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA`
- [ ] Defender ASR rules: `Get-MpPreference | Select -ExpandProperty AttackSurfaceReductionRules_Ids | Measure-Object` -> 15
- [ ] IFEO debugger keys removed: `reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sethc.exe" /v Debugger` -> not found
- [ ] Password file created: `dir C:\ccdc26\logs\passwords-*`
- [ ] PowerShell logging enabled: `reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"`
- [ ] WinRM still works (can you still remote in?)
- [ ] RDP still works?

### 2.3 Test sanity-check.ps1

Run AFTER 01-blitz.ps1 to validate it worked:
```powershell
.\sanity-check.ps1
```

**Verify:**
- [ ] All checks show PASS
- [ ] Note any FAIL items -- these are bugs in 01-blitz.ps1

### 2.4 Test 02-ad.ps1 (non-DC behavior)

This VM is NOT a Domain Controller, so 02-ad.ps1 should exit silently:
```powershell
.\02-ad.ps1
```

**Verify:**
- [ ] Script exits immediately with no errors
- [ ] No changes made to the system

### 2.5 Test 03-audit.ps1

```powershell
.\03-audit.ps1
```

**Verify:**
- [ ] Audit policies set: `auditpol /get /category:*` (should show Success and Failure for most)
- [ ] Command line auditing: `reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled`
- [ ] PowerShell transcription directory created: `dir C:\ccdc26\logs\powershell`
- [ ] Firewall logging enabled: `netsh advfirewall show allprofiles | findstr "LogFile"`

### 2.6 Test 05-monitor.ps1

```powershell
.\05-monitor.ps1
```

**Verify:**
- [ ] Background jobs started: `Get-Job`
- [ ] Process monitor running
- [ ] Network monitor running
- [ ] Session monitor running
- [ ] Open a new cmd.exe -- does the monitor detect the new process?

### 2.7 Test hunt-persistence.ps1

```powershell
.\hunt-persistence.ps1
```

**Verify:**
- [ ] All 13 categories execute (Registry, ScheduledTasks, WMI, Services, Startup, DLLHijacking, COM, SSP, PrintMonitors, NetworkProviders, PowerShellProfile, BitsJobs, ADBackdoors)
- [ ] No crashes or unhandled exceptions
- [ ] Findings reported (some are expected on a fresh install: Run keys, services, etc.)
- [ ] Summary shows total findings count

### 2.8 Test ir-triage.ps1

```powershell
.\ir-triage.ps1
```

**Verify:**
- [ ] Shows active sessions
- [ ] Shows running processes
- [ ] Shows network connections
- [ ] Shows scheduled tasks
- [ ] Completes without errors

### 2.9 Test hunt-golden.ps1

```powershell
.\hunt-golden.ps1
```

**Verify:**
- [ ] Runs without errors (may report "no Kerberos sessions" on a non-DC standalone server)
- [ ] Graceful exit if no tickets found

### 2.10 Test hunt-webshells.ps1 (no IIS)

```powershell
.\hunt-webshells.ps1
```

**Verify:**
- [ ] Detects that IIS is not installed
- [ ] Exits gracefully with informative message (not a crash)

### 2.11 Test ir-kill.ps1

```powershell
.\ir-kill.ps1
```

**Verify:**
- [ ] Lists current sessions
- [ ] Can enumerate users
- [ ] Doesn't kill your own session unprompted

---

## Phase 3: Windows Dovetail Dispatch Testing

Test dispatching scripts FROM the Arch host TO the Windows VM via WinRM.

### 3.1 Test Dovetail directly

From Arch host (with pywinrm installed):
```powershell
# First test raw WinRM from pwsh
pwsh -Command '
$cred = Get-Credential  # Enter Administrator / Changeme123!
$session = New-PSSession -ComputerName 192.168.122.x -Credential $cred -Authentication Basic -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Invoke-Command -Session $session -ScriptBlock { hostname }
Remove-PSSession $session
'
```

### 3.2 Test Dovetail script dispatch

```powershell
cd /home/thule/Cyber/CCDC/ccdc26/dovetail
pwsh -File dovetail.ps1 -Script scripts/00-snapshot.ps1 -Targets 192.168.122.x -Credential (Get-Credential)
```

**Verify:**
- [ ] Dovetail connects to the VM
- [ ] Script is dispatched and executes
- [ ] Output is collected and displayed

---

## Phase 4: Linux Testing (Docker -- fill remaining gaps)

### 4.1 Monarch REPL Integration

```bash
cd /home/thule/Cyber/CCDC/ccdc26/test
docker compose exec controller bash
cd /opt/ccdc26/monarch
pip3 install -r requirements.txt
python3 -m monarch
```

In the REPL:
```
> scan 10.99.0.0/24 changeme
> list
> profile
> shell ecom
> exit   (from the shell)
> script 00-snapshot.sh
> rotate
> script 01-harden.sh
```

**Verify:**
- [ ] `scan` discovers all 4 targets
- [ ] `list` shows discovered hosts with aliases
- [ ] `profile` shows OS information
- [ ] `shell` gives interactive SSH
- [ ] `script` dispatches and shows output per host
- [ ] `rotate` changes passwords and updates conf.json

### 4.2 Cross-Distro Hardening

After `scan` and `rotate`, dispatch `01-harden.sh` and verify on each distro:
```
> script 01-harden.sh
```

Then SSH into each and check:
```
> shell webmail    # Fedora
> shell splunk     # Rocky
> shell workstation # Alpine
```

**Verify per host:**
- [ ] SSH config hardened (`PermitRootLogin no` in sshd_config)
- [ ] Sysctl parameters applied (`sysctl net.ipv4.ip_forward` = 0)
- [ ] Dangerous services stopped
- [ ] File permissions fixed

### 4.3 Firewall Testing

**Known issue:** 02-firewall.sh locked out SSH on first test because iptables blocked the Docker bridge. Need to test the anti-lockout mechanism.

Reset containers first:
```bash
cd /home/thule/Cyber/CCDC/ccdc26/test
docker compose down && docker compose up -d
```

Then from controller:
```
> scan 10.99.0.0/24 changeme
> script 02-firewall.sh
```

**Verify:**
- [ ] Firewall rules applied
- [ ] SSH still works after (anti-lockout triggered)
- [ ] iptables LOG chains present (`iptables -L | grep LOG`)

### 4.4 Persistence Hunt on Dirty Container

Plant fake persistence, then test detection:
```bash
# From controller, SSH into ecom
sshpass -p changeme ssh root@10.99.0.11

# Plant fake backdoors:
echo '* * * * * /tmp/evil.sh' | crontab -
touch /tmp/.hidden-backdoor && chmod +x /tmp/.hidden-backdoor
cp /bin/bash /tmp/bash && chmod u+s /tmp/bash
echo '/tmp/libevil.so' > /etc/ld.so.preload
useradd -o -u 0 -g 0 backdoor
exit
```

Then dispatch:
```
> script hunt-persistence.sh -H ecom
```

**Verify:**
- [ ] Finds the cron backdoor
- [ ] Finds the hidden executable in /tmp
- [ ] Finds the SUID bash in /tmp
- [ ] Finds the LD_PRELOAD entry
- [ ] Finds the UID 0 backdoor account
- [ ] Reports total findings count

### 4.5 PII Scanner with Planted Data

```bash
# SSH into ecom
sshpass -p changeme ssh root@10.99.0.11
echo "SSN: 123-45-6789" > /home/test-pii.txt
echo "CC: 4111111111111111" >> /home/test-pii.txt
echo "Email: secret@company.com" >> /home/test-pii.txt
exit
```

```
> script hunt-pii.sh -H ecom
```

**Verify:**
- [ ] Finds the SSN
- [ ] Finds the credit card number
- [ ] Finds the email address

### 4.6 Sanity Check (Python)

After hardening + firewall on all hosts:
```python
# From controller
cd /opt/ccdc26/monarch
python3 -c "from monarch.sanity_check import sanity_test; sanity_test()"
```

**Verify:**
- [ ] Default password `changeme` fails (rotation worked)
- [ ] Port 9999 blocked (firewall worked)
- [ ] Pubkey auth disabled (SSH hardening worked)
- [ ] Results written to `sanity_test_results.log`

---

## Phase 5: End-to-End Simulation

Full competition-day dry run. Reset everything first.

### 5.1 Reset Environment

```bash
# Reset Docker containers
cd /home/thule/Cyber/CCDC/ccdc26/test
docker compose down && docker compose up -d

# Revert Windows VM to clean snapshot
sudo virsh snapshot-revert win2k25 "clean-install"
```

### 5.2 Time the Full Workflow

Start a timer and execute the START-HERE.md playbook exactly as written:

**Linux lead (in controller container):**
```
1. cd /opt/ccdc26/monarch && ./run.sh
2. > scan 10.99.0.0/24 changeme
3. > script 00-snapshot.sh
4. > rotate
5. > script 01-harden.sh
6. > script 02-firewall.sh
7. > script 03-services.sh
```

**Windows lead (in VM):**
```
1. Copy toolkit to C:\ccdc26
2. cd C:\ccdc26\dovetail\scripts
3. .\00-snapshot.ps1
4. .\01-blitz.ps1
5. .\03-audit.ps1
```

**Record:**
- [ ] Total time for Linux (scan through services): _____ minutes
- [ ] Total time for Windows (copy through audit): _____ minutes
- [ ] Any errors encountered: _____
- [ ] Any scripts that need fixing: _____

### 5.3 Post-Hardening Validation

After both sides finish:
```
Linux:  python3 -c "from monarch.sanity_check import sanity_test; sanity_test()"
Windows: .\sanity-check.ps1
```

- [ ] All Linux sanity checks pass
- [ ] All Windows sanity checks pass

---

## Known Issues and Limitations

| Issue | Impact | Workaround |
|-------|--------|------------|
| 01-harden.sh restarts SSHD, killing container if SSHD is PID 1 | Container dies | Fixed with entrypoint.sh wrapper |
| 02-firewall.sh may block Docker bridge subnet | Locks out SSH | Anti-lockout safety should catch this; needs testing |
| 04-splunk.sh fails without Splunk server | Expected | Verify graceful error message only |
| Alpine lacks some GNU tools (hostname, etc.) | Script compatibility | Test each script on Alpine specifically |
| Windows VM is standalone (not DC) | Can't test 02-ad.ps1 fully | Need separate DC VM for AD testing |
| No Splunk server in test environment | Can't test log ingestion | Add Splunk container in future |
| Docker containers reset on rebuild | Test state lost | Use snapshots for Windows VM |
| ~~01-blitz.ps1 LOLBin rules deleted by firewall nuke~~ | LOLBin outbound rules lost | **Fixed**: moved LOLBin section after firewall nuke-and-rebuild |
| ~~01-blitz.ps1 NetBIOS CIM method error~~ | Non-fatal stderr noise | **Fixed**: use Invoke-CimMethod instead of direct method call |
| ~~hunt-webshells.ps1 exits 1 when no IIS~~ | Confusing error message | **Fixed**: detects IIS absence, exits 0 with info message |
| ~~ir-kill.ps1 truncates usernames~~ | "dministrator" instead of "Administrator" | **Fixed**: rewrote qwinsta parser to use whitespace splitting |
| ~~dovetail.ps1 NonDomain auth fails~~ | Cannot dispatch to non-domain targets | **Fixed**: added Basic auth + AllowUnencrypted for NonDomain mode |
| 01-blitz.ps1 service Stop-Service collection error | Non-fatal stderr noise | Race condition in service enumeration; cosmetic only |
| 05-monitor.ps1 jobs ephemeral in WinRM | Background jobs die with session | Designed for interactive use; run directly on VM |
| 01-blitz.ps1 breaks NTLM auth (LmCompatibilityLevel=5) | Can't use NTLM after hardening | Expected; use Basic auth or Kerberos (domain) post-hardening |

# Dovetail User Guide

Dovetail is the Windows orchestration tool. It dispatches PowerShell scripts
to multiple Windows machines simultaneously from a single controller (usually
the Domain Controller).

Dovetail uses WinRM (Windows Remote Management) -- the Windows equivalent of
SSH. It establishes persistent sessions to all Windows machines and runs
scripts on them as background jobs.

---

## Prerequisites

Dovetail runs FROM a Windows machine (typically the DC) TO other Windows machines.
Before using Dovetail:

1. **WinRM must be enabled on all target machines:**

```powershell
# Run on EACH Windows machine (or include in 01-blitz.ps1 -- already done):
winrm quickconfig -y
Enable-PSRemoting -Force
```

2. **Firewall must allow WinRM (port 5985) between Windows machines.**
   The `01-blitz.ps1` script already opens this port.

3. **If machines are NOT domain-joined**, you also need:

```powershell
# On the controller machine:
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

---

## Starting Dovetail

From the Domain Controller (or any Windows machine with the toolkit):

```powershell
cd C:\ccdc26\dovetail
```

---

## Connecting to Targets

### Domain mode (automatic discovery)

If you're on a Domain Controller, Dovetail can auto-discover all
domain-joined Windows machines:

```powershell
.\dovetail.ps1 -Connect -Targets "domain"
```

This queries Active Directory for all computer objects with "Windows"
in their OS name, then establishes WinRM sessions to each one.

### Manual mode (specific IPs)

For non-domain machines or when AD discovery isn't working:

```powershell
.\dovetail.ps1 -Connect -Targets "10.0.2.100,10.0.2.101,10.0.2.102"
```

### Non-domain mode

If the targets aren't joined to the same domain as the controller:

```powershell
.\dovetail.ps1 -Connect -Targets "10.0.2.100,10.0.2.101" -NonDomain
```

This uses Basic authentication instead of Kerberos. You'll be prompted
for credentials (use the local Administrator account on the targets).

---

## Dispatching Scripts

Once connected, dispatch any script from `dovetail/scripts/`:

```powershell
# Harden all connected machines
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1

# AD hardening (DC only -- script auto-skips non-DCs)
.\dovetail.ps1 -Script .\scripts\02-ad.ps1

# Deploy audit policies
.\dovetail.ps1 -Script .\scripts\03-audit.ps1

# Deploy Splunk forwarders
.\dovetail.ps1 -Script .\scripts\04-splunk.ps1

# Start monitoring
.\dovetail.ps1 -Script .\scripts\05-monitor.ps1
```

### Target specific machines

Only dispatch to certain hosts:

```powershell
# Only the web server and FTP server
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1 -Include "WEB01","FTP01"

# Everything EXCEPT the DC
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1 -Exclude "DC01"
```

---

## The Competition Workflow

### From the DC (after manually hardening the DC itself):

```powershell
cd C:\ccdc26\dovetail

# 1. Connect to all Windows machines
.\dovetail.ps1 -Connect -Targets "domain"

# 2. Harden all machines at once
.\dovetail.ps1 -Script .\scripts\01-blitz.ps1

# 3. Deploy audit policies
.\dovetail.ps1 -Script .\scripts\03-audit.ps1

# 4. Deploy Splunk forwarders
.\dovetail.ps1 -Script .\scripts\04-splunk.ps1

# 5. Start monitoring
.\dovetail.ps1 -Script .\scripts\05-monitor.ps1
```

### On the DC itself (run directly, not via Dovetail):

```powershell
cd C:\ccdc26\dovetail\scripts

# These run locally on the DC:
.\00-snapshot.ps1
.\01-blitz.ps1
.\02-ad.ps1                    # AD-specific hardening
.\03-audit.ps1
```

### Ongoing threat hunting (via Dovetail):

```powershell
.\dovetail.ps1 -Script .\scripts\hunt-persistence.ps1
.\dovetail.ps1 -Script .\scripts\hunt-webshells.ps1
```

---

## Session Management

### Check session health

```powershell
Get-PSSession | Format-Table ComputerName, State, Availability
```

Healthy sessions show `State: Opened, Availability: Available`.

### Repair broken sessions

If a machine rebooted or WinRM dropped:

```powershell
.\dovetail.ps1 -Repair
```

This reconnects to any machines with broken sessions.

### View output from dispatched scripts

Dovetail saves output per-host in the `dovetail/` directory. Look for
files like `WEB01.txt`, `DC01.txt`, etc.

---

## Running Scripts Directly (No Dovetail)

You don't need Dovetail to use the scripts. On any individual Windows
machine, you can run them directly:

```powershell
cd C:\ccdc26\dovetail\scripts
.\01-blitz.ps1                 # Harden this machine
.\hunt-persistence.ps1         # Hunt on this machine
.\ir-triage.ps1                # Triage this machine
.\sanity-check.ps1             # Validate hardening
```

Dovetail just lets you do this on ALL machines from one keyboard.

---

## Script Reference

### Numbered scripts (run in order):

| Script | What it does | Needs Dovetail? |
|--------|-------------|-----------------|
| `00-snapshot.ps1` | Forensic baseline before changes | No |
| `01-blitz.ps1` | Full hardening (CVEs, Defender, firewall, services) | No |
| `02-ad.ps1` | DC-only: Kerberos, Zerologon, krbtgt rotation | No (run on DC) |
| `03-audit.ps1` | Audit policies, PowerShell logging, SACLs | No |
| `04-splunk.ps1` | Deploy Splunk forwarder | No |
| `05-monitor.ps1` | Start process/network/session monitoring | No |

### Hunt scripts (run on-demand):

| Script | What it does |
|--------|-------------|
| `hunt-persistence.ps1` | 13-category persistence scan + AD backdoors |
| `hunt-webshells.ps1` | IIS webshell detection (baseline + diff) |
| `hunt-golden.ps1` | Golden ticket / Kerberos ticket analysis |
| `sanity-check.ps1` | Validate hardening applied correctly |
| `collect-logs.ps1` | Archive all event logs + service logs to ZIP |

### IR scripts (run during incidents):

| Script | What it does |
|--------|-------------|
| `ir-triage.ps1` | Quick overview: sessions, processes, network |
| `ir-kill.ps1` | Kill attacker sessions, block IPs |

---

## Troubleshooting

### "WinRM cannot connect"

1. On the target, verify WinRM is running:
```powershell
Get-Service WinRM                  # Should be Running
Test-WSMan localhost               # Should succeed
```

2. Check firewall allows port 5985:
```powershell
Get-NetFirewallRule -Name "*WinRM*" | Where-Object {$_.Enabled}
```

3. If not domain-joined, add to TrustedHosts:
```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### "Access denied" or "Authentication failed"

- Verify you're using the correct credentials (local Admin or domain Admin)
- For non-domain: use `-NonDomain` flag
- Check that the account isn't locked out: `Get-LocalUser Administrator`

### Script dispatched but no output

- Check session health: `Get-PSSession | ft ComputerName, State`
- Repair: `.\dovetail.ps1 -Repair`
- Run directly on the machine to see errors: `.\scripts\01-blitz.ps1`

### "The WinRM client cannot process the request"

Usually means the session timed out. Reconnect:
```powershell
.\dovetail.ps1 -Connect -Targets "domain"
```

### Cross-zone (Linux -> Windows) WinRM doesn't work

This requires the zone firewall to allow TCP 5985 from the Linux
subnet to the Windows subnet. See the firewall section in START-HERE.md.

Dovetail is designed to run FROM a Windows machine TO other Windows machines
(same subnet). Cross-zone WinRM from Linux is not needed for normal operation.

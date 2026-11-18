# CCDC26 Windows Defense Toolkit

Comprehensive PowerShell scripts for Windows system hardening, Active Directory security, and security monitoring during CCDC competition.

## Quick Start

```powershell
# Run as Administrator!

# Option 1: Interactive menu
.\deploy.ps1

# Option 2: Quick harden (all defaults)
.\deploy.ps1 -Quick

# Option 3: Run specific scripts
.\hardening\Full-Harden.ps1      # Local system hardening
.\hardening\AD-Harden.ps1        # Domain Controller hardening
.\Install-SplunkForwarder.ps1    # Splunk forwarder setup
```

## Directory Structure

```
windows-scripts/
├── hardening/
│   ├── Full-Harden.ps1         # Main Windows hardening script
│   ├── AD-Harden.ps1           # Active Directory specific hardening
│   └── lib/
│       ├── common.ps1          # Shared utility functions
│       ├── auditing.ps1        # Advanced audit configuration
│       └── passwords.ps1       # Zulu-style password generation
├── Install-SplunkForwarder.ps1 # Splunk forwarder for log collection
└── README.md                   # This file
```

## Scripts Overview

### Full-Harden.ps1

Main hardening script for all Windows systems. Includes:

**CVE Patches & Mitigations:**
- MS17-010 (EternalBlue) - OS-specific patches
- CVE-2021-34527 (PrintNightmare) - Spooler disabled, registry mitigations
- Mimikatz mitigations - WDigest disabled, LSASS protection
- SMB hardening - SMBv1 disabled, SMBv2/v3 enabled with signing

**Windows Defender:**
- Real-time protection enabled
- 15 Attack Surface Reduction (ASR) rules
- Exclusions removed
- Tamper protection enabled

**Backdoor Removal:**
- Accessibility feature abuse (sethc.exe, Utilman.exe, etc.)
- Scheduled task auditing
- Image File Execution Options cleanup

**Service Lockdown:**
- Print Spooler disabled
- Remote Registry disabled
- Telnet, TFTP, SMBv1 features disabled

**Usage:**
```powershell
# Interactive menu
.\hardening\Full-Harden.ps1

# Quick mode (all defaults)
.\hardening\Full-Harden.ps1 -q
```

### AD-Harden.ps1

Domain Controller specific hardening. Includes:

**CVE Patches:**
- CVE-2020-1472 (Zerologon) - Secure channel protection
- CVE-2021-42278/42287 (noPac) - Machine account quota = 0

**Kerberos Hardening:**
- ASREP-roastable accounts fixed (pre-auth required)
- Kerberoastable accounts fixed (AES encryption enabled)
- DCSync permissions audited

**User Management:**
- Mass disable all users (except specified)
- Competition user creation with deterministic passwords
- Privileged group cleanup (Domain Admins, Enterprise Admins, etc.)

**Additional:**
- LDAP signing requirements
- AD state backup before changes
- Security GPO creation

**Usage:**
```powershell
# Must run on Domain Controller!
.\hardening\AD-Harden.ps1

# Quick mode
.\hardening\AD-Harden.ps1 -q
```

### lib/common.ps1

Shared utilities (source in other scripts):
- Color-coded output functions (Info, Success, Warn, Error)
- OS version detection
- Backup functions for files and registry
- Service management helpers
- Firewall helpers
- Registry helpers
- Common port definitions

### lib/passwords.ps1

Zulu-style deterministic password generation:
- Generates passphrases from salt + username
- Same inputs always produce same output
- Enables team coordination without sharing plaintext

**Usage:**
```powershell
# Interactive mode
.\hardening\lib\passwords.ps1

# In scripts
. .\hardening\lib\passwords.ps1
$password = Get-DeterministicPassword -Username "admin" -Salt "ccdc2026secret"
# Returns: "dragon-falcon-sunset-prism-echo1"
```

### lib/auditing.ps1

Comprehensive Windows auditing:
- All audit policy subcategories enabled
- Command line auditing (Event ID 4688)
- PowerShell Script Block Logging
- PowerShell Module Logging
- PowerShell Transcription
- Firewall logging (all profiles)
- Sysmon installation (optional)

### Install-SplunkForwarder.ps1

Deploys Splunk Universal Forwarder to the competition Splunk server (172.20.242.20):

**Windows Event Logs Collected:**
- Security (logons, auth, privilege use) → `windows-security`
- System → `windows-system`
- Application → `windows-application`
- PowerShell (script block logging) → `windows-powershell`
- Windows Defender → `windows-security`
- Windows Firewall → `windows-security`
- Sysmon (if installed) → `windows-sysmon`
- Task Scheduler → `windows-security`
- Remote Desktop Services → `windows-security`
- DNS Server (if DC) → `windows-dns`
- Active Directory (if DC) → `windows-security`

**Setup:**
```powershell
# Quick setup (recommended)
.\Install-SplunkForwarder.ps1 -Quick

# Or interactive menu
.\Install-SplunkForwarder.ps1

# Forwards to: 172.20.242.20:9997
```

## Priority Order During Competition

### First 15 Minutes (Critical)
1. Run `Full-Harden.ps1 -q` on all Windows systems
2. Run `AD-Harden.ps1 -q` on Domain Controllers
3. Change all passwords (use passwords.ps1 for consistency)

### Next 30 Minutes (Important)
4. Deploy Splunk forwarders
5. Configure firewall ports
6. Audit scheduled tasks
7. Review privileged group membership

### Ongoing
- Monitor Splunk dashboards
- Re-audit for persistence
- Respond to alerts

## CVEs Addressed

| CVE | Name | Script | Action |
|-----|------|--------|--------|
| MS17-010 | EternalBlue | Full-Harden.ps1 | OS-specific patch |
| CVE-2021-34527 | PrintNightmare | Full-Harden.ps1 | Spooler disabled, registry |
| CVE-2020-1472 | Zerologon | AD-Harden.ps1 | Secure channel protection |
| CVE-2021-42278/42287 | noPac | AD-Harden.ps1 | Machine account quota |
| - | Mimikatz | Full-Harden.ps1 | WDigest, LSASS protection |
| - | ASREP Roasting | AD-Harden.ps1 | Pre-auth required |
| - | Kerberoasting | AD-Harden.ps1 | AES encryption |
| - | DCSync | AD-Harden.ps1 | Permission audit |

## Requirements

- Windows Server 2012+ or Windows 10+
- PowerShell 5.0+
- Administrator privileges
- For AD scripts: Domain Admin on a DC

## Logs & Output

All actions are logged to:
```
C:\CCDC-Toolkit\logs\actions.log     # Action log
C:\CCDC-Toolkit\logs\findings.log    # Security findings
C:\CCDC-Toolkit\backups\             # Config backups
```

## Tips

1. **Always run as Administrator**
2. **Test in a VM first** before competition
3. **Keep a terminal open** in case you lock yourself out
4. **Use passwords.ps1** for consistent passwords across team
5. **Backup before changes** (scripts do this automatically)
6. **Document changes** for scoring

## Author
Brady Hodge - BYU-SOC Team (CCDC26)

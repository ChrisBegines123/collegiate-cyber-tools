# Active Directory Hardening Scripts

Purple Knight / BloodHound remediation scripts for RMCCDC Domain Controllers.

## Quick Start

```powershell
# Run everything in one shot (recommended for competition start)
.\RapidDeploy_AllInOne.ps1 -Force

# Verify settings applied
.\Verify_Hardening.ps1
```

## Scripts

| Script | Time | Purpose |
|--------|------|---------|
| **RapidDeploy_AllInOne.ps1** | 2-3 min | All fixes in one execution - use at competition start |
| Phase1_Critical_Hardening.ps1 | 2 min | Critical fixes (first 5 minutes) |
| Phase2_HighPriority_Hardening.ps1 | 5 min | High priority (5-15 minutes) |
| Phase3_Auditing_Hardening.ps1 | 5 min | Auditing and detection (15-30 minutes) |
| **Verify_Hardening.ps1** | 30 sec | Confirms all settings are applied |

## What Gets Hardened

### Phase 1 - Critical (0-5 min)
- Disable Print Spooler (PrintNightmare CVE-2021-34527)
- Set MachineAccountQuota to 0 (RBCD/noPac prevention)
- Require LDAP Signing
- Detect admin sessions on workstations

### Phase 2 - High Priority (5-15 min)
- Remove nested groups from Enterprise Admins
- Strengthen password policy (14 char min, lockout 5)
- Secure DNS zones (Secure dynamic updates only)
- Fix PasswordNeverExpires on privileged accounts
- Audit Domain Admin membership
- Check RDP access for Domain Users
- Zerologon mitigation (CVE-2020-1472)

### Phase 3 - Auditing (15-30 min)
- Enable advanced audit policy (12 categories)
- Enable command-line process auditing (Event 4688)
- Enable PowerShell ScriptBlock logging (Event 4104)
- Enable PowerShell Module logging
- Disable LLMNR (Responder mitigation)
- Disable NBT-NS (Responder mitigation)
- Disable SMBv1 (EternalBlue mitigation)

## Relationship to windows-scripts/

This folder contains **Purple Knight / BloodHound specific** remediation.

The `windows-scripts/` folder contains **comprehensive Windows hardening** including:
- Mimikatz mitigations (WDigest, LSASS PPL)
- Windows Defender configuration
- Attack Surface Reduction rules
- UAC hardening
- Accessibility backdoor removal
- EternalBlue patch installation

**Recommended: Run BOTH for maximum coverage.**

```powershell
# 1. AD-specific hardening (this folder)
.\AD\RapidDeploy_AllInOne.ps1 -Force

# 2. Comprehensive Windows hardening
.\deploy.ps1 -Quick

# 3. Verify
.\AD\Verify_Hardening.ps1
```

## Print Spooler

Both AD scripts and windows-scripts **DISABLE** Print Spooler (PrintNightmare CVE-2021-34527).

If printing is needed for an inject:
```powershell
# Re-enable temporarily
Set-Service Spooler -StartupType Manual
Start-Service Spooler

# Disable again after
Stop-Service Spooler -Force
Set-Service Spooler -StartupType Disabled
```

## Parameters

All scripts support:
- `-WhatIf` - Preview mode, no changes made
- `-Force` - Skip confirmation prompts (RapidDeploy only)

```powershell
# Preview what would change
.\RapidDeploy_AllInOne.ps1 -WhatIf

# Run without prompts
.\RapidDeploy_AllInOne.ps1 -Force
```

## Verification

Run after hardening to confirm settings:

```powershell
.\Verify_Hardening.ps1
```

Checks:
- Print Spooler disabled
- MachineAccountQuota = 0
- LDAP Signing required
- Min password length >= 14
- Lockout threshold 1-5
- DNS zones secured
- No nested EA groups
- No PasswordNeverExpires
- LLMNR disabled
- SMBv1 disabled
- Command-line auditing enabled
- PowerShell logging enabled
- Zerologon patched

## Additional Resources

- `RMCCDC_AD_Hardening_Checklist.md` - Detailed checklist with manual steps
- `windows-scripts/README.md` - Comprehensive Windows hardening documentation

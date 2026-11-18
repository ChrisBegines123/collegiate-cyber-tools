# RMCCDC Active Directory Hardening Checklist
## Competition Day Rapid Deployment Guide

**Domain:** CCDCTEAM.COM  
**Based on:** Purple Knight Assessment (84% -> target 95%+) + BloodHound Attack Path Analysis  
**Last Updated:** January 2026

---

## Timeline Overview

| Phase | Time | Actions |
|-------|------|---------|
| **Phase 1** | 0-5 min | Run initial assessment script, disable Print Spooler |
| **Phase 2** | 5-15 min | Fix critical attack paths, remove nested EA |
| **Phase 3** | 15-30 min | Apply GPO hardening, password policy |
| **Phase 4** | 30-60 min | Enable advanced auditing, verify fixes |

---

## PHASE 1: CRITICAL (First 5 Minutes)

### 1.1 Disable Print Spooler (PrintNightmare)
**Purple Knight Finding:** Print Spooler service enabled on DC  
**Risk:** Remote code execution via PrintNightmare (CVE-2021-34527)

```powershell
Stop-Service Spooler -Force
Set-Service Spooler -StartupType Disabled
```

- [ ] Print Spooler stopped
- [ ] Print Spooler startup disabled

### 1.2 Force Logoff Admin Sessions on Workstations
**BloodHound Finding:** Administrator has sessions on WINDOWSPC, FILESERVER  
**Risk:** Credential theft via Mimikatz -> instant Domain Admin

```powershell
# Check for admin sessions on non-DCs
$computers = @("WINDOWSPC", "FILESERVER")
foreach ($computer in $computers) {
    Write-Host "Sessions on $computer`:" -ForegroundColor Cyan
    Invoke-Command -ComputerName $computer -ScriptBlock { query user } -ErrorAction SilentlyContinue
}

# Force logoff (replace SessionID as needed)
# Invoke-Command -ComputerName WINDOWSPC -ScriptBlock { logoff <SessionID> }
```

- [ ] Admin sessions identified
- [ ] Admin sessions logged off from workstations
- [ ] Admin sessions logged off from member servers

### 1.3 Set MachineAccountQuota to 0
**Purple Knight + BloodHound Finding:** MachineAccountQuota = 10  
**Risk:** Any user can create machine accounts for RBCD attacks

```powershell
Set-ADDomain -Identity (Get-ADDomain).DNSRoot -Replace @{"ms-DS-MachineAccountQuota"="0"}
```

- [ ] MachineAccountQuota set to 0

---

## PHASE 2: HIGH PRIORITY (5-15 Minutes)

### 2.1 Remove Nested Enterprise Admin Path
**BloodHound Finding:** ADMIN -> COMPUTER group -> Enterprise Admins  
**Risk:** Hidden privilege escalation path invisible to standard audits

```powershell
# Identify the nested path
Get-ADGroupMember "Enterprise Admins" -Recursive | Select Name, objectClass

# Remove COMPUTER group from Enterprise Admins
Remove-ADGroupMember -Identity "Enterprise Admins" -Members "COMPUTER" -Confirm:$false
```

- [ ] Nested EA path verified
- [ ] COMPUTER group removed from Enterprise Admins

### 2.2 Require LDAP Signing
**Purple Knight Finding:** LDAP signing not required  
**Risk:** LDAP relay attacks, credential interception

```powershell
# Registry method (immediate)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerIntegrity" -Value 2 -Type DWord

# Verify
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" | Select LDAPServerIntegrity
```

- [ ] LDAP signing required (LDAPServerIntegrity = 2)

### 2.3 Strengthen Password Policy
**Purple Knight Finding:** MinPasswordLength = 7 (needs 14+)  
**Risk:** Weak passwords easily cracked by red team

```powershell
Set-ADDefaultDomainPasswordPolicy -Identity (Get-ADDomain).DNSRoot `
    -MinPasswordLength 14 `
    -LockoutThreshold 5 `
    -LockoutDuration "00:30:00" `
    -LockoutObservationWindow "00:30:00" `
    -PasswordHistoryCount 24 `
    -ComplexityEnabled $true
```

- [ ] MinPasswordLength ≥ 14
- [ ] LockoutThreshold = 5
- [ ] Complexity enabled

### 2.4 Secure DNS Zones
**Purple Knight Finding:** DNS zones allow non-secure dynamic updates  
**Risk:** DNS poisoning, MITM attacks

```powershell
Get-DnsServerZone | Where-Object { $_.DynamicUpdate -eq "NonsecureAndSecure" } | 
    ForEach-Object { 
        Set-DnsServerPrimaryZone -Name $_.ZoneName -DynamicUpdate Secure 
        Write-Host "Secured: $($_.ZoneName)"
    }
```

**Note on DHCP:** "Secure only" does NOT break domain-joined DHCP clients - they authenticate via Kerberos. Non-domain machines won't auto-register DNS, but DHCP server can register on their behalf if configured. For CCDC, this is actually better security.

- [ ] All DNS zones set to Secure dynamic update only

### 2.5 Fix Privileged Account Password Expiration
**Purple Knight + BloodHound Finding:** 18 accounts with PasswordNeverExpires  
**Affected:** RICHARD.G.JOHNSON, ADMIN, DAVID.WEISNEWSKI, etc.  
**Risk:** Long-term persistence for attackers

```powershell
# Fix all non-service accounts
Get-ADUser -Filter {PasswordNeverExpires -eq $true -and Enabled -eq $true} |
    Where-Object { $_.SamAccountName -notmatch "^(krbtgt|AZUREADSSOACC)$" } |
    ForEach-Object {
        Set-ADUser -Identity $_ -PasswordNeverExpires $false
        Write-Host "Fixed: $($_.SamAccountName)"
    }
```

- [ ] Richard.G.Johnson fixed
- [ ] Admin account fixed
- [ ] Other accounts fixed (18 total)

### 2.6 Disable SMBv1 (EternalBlue Mitigation)
**Risk:** EternalBlue (MS17-010), WannaCry, NotPetya - critical RCE vulnerability

```powershell
# Disable SMBv1 Server
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

# Verify
Get-SmbServerConfiguration | Select EnableSMB1Protocol
```

- [ ] SMBv1 disabled on DC
- [ ] SMBv1 disabled on member servers
- [ ] SMBv1 disabled on workstations

### 2.7 Zerologon Mitigation (CVE-2020-1472)
**Risk:** Complete domain takeover via Netlogon protocol vulnerability

```powershell
# Enable secure channel protection
$netlogonPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
Set-ItemProperty -Path $netlogonPath -Name "FullSecureChannelProtection" -Value 1 -Type DWord -Force

# Remove any vulnerable channel allowlist
Remove-ItemProperty -Path $netlogonPath -Name "vulnerablechannelallowlist" -Force -ErrorAction SilentlyContinue

# Verify
Get-ItemProperty $netlogonPath | Select FullSecureChannelProtection
```

- [ ] FullSecureChannelProtection = 1
- [ ] Vulnerable channel allowlist removed

---

## PHASE 3: MEDIUM PRIORITY (15-30 Minutes)

### 3.1 Restrict Domain Admin Logon Rights
**BloodHound Finding:** DA can log into any workstation  
**Risk:** Credential exposure on compromised systems

**GPO Path:** Computer Configuration > Policies > Windows Settings > Security Settings > Local Policies > User Rights Assignment

| Setting | Value |
|---------|-------|
| Deny log on locally | Domain Admins, Enterprise Admins |
| Deny log on through RDP | Domain Admins, Enterprise Admins |

*Apply to Workstations OU only, NOT Domain Controllers*

```powershell
# Manual verification after GPO
gpresult /r /scope:computer | Select-String "Deny"
```

- [ ] GPO created for workstation tier
- [ ] DA/EA denied local logon on workstations
- [ ] DA/EA denied RDP on workstations

### 3.2 Remove Domain Users from RDP Access
**BloodHound Finding:** Domain Users can RDP to WINDOWSPC, FILESERVER  
**Risk:** Any compromised user can lateral move

```powershell
# Check current RDP users on remote systems
$computers = @("WINDOWSPC", "FILESERVER")
foreach ($computer in $computers) {
    Invoke-Command -ComputerName $computer -ScriptBlock {
        Get-LocalGroupMember "Remote Desktop Users" -ErrorAction SilentlyContinue
    }
}

# Remove Domain Users from RDP (run on each workstation)
# Remove-LocalGroupMember -Group "Remote Desktop Users" -Member "CCDCTEAM\Domain Users"
```

- [ ] Domain Users removed from RDP on WINDOWSPC
- [ ] Domain Users removed from RDP on FILESERVER

### 3.3 Disable RC4 for Kerberos
**Purple Knight Finding:** RC4_HMAC_MD5 enabled  
**Risk:** Kerberoasting, pass-the-hash easier with weak encryption

**GPO Path:** Computer Configuration > Policies > Windows Settings > Security Settings > Local Policies > Security Options > Network security: Configure encryption types allowed for Kerberos

| Enable | Disable |
|--------|---------|
| AES128_HMAC_SHA1 | DES_CBC_CRC |
| AES256_HMAC_SHA1 | DES_CBC_MD5 |
| Future encryption types | RC4_HMAC_MD5 |

```powershell
# Registry verification
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -Name SupportedEncryptionTypes -ErrorAction SilentlyContinue
```

- [ ] AES128 enabled
- [ ] AES256 enabled
- [ ] RC4 disabled
- [ ] DES disabled

### 3.4 Clean Pre-Windows 2000 Compatible Access Group
**Purple Knight Finding:** Authenticated Users in Pre-Windows 2000 group  
**Risk:** Anonymous LDAP enumeration

```powershell
# Check membership
Get-ADGroupMember "Pre-Windows 2000 Compatible Access"

# Remove Authenticated Users (may need GUI for well-known SIDs)
# ADUC > Groups > Pre-Windows 2000 Compatible Access > Members > Remove
```

- [ ] Authenticated Users removed
- [ ] Only required accounts remain

### 3.5 Review and Remove Unnecessary Domain Admins
**BloodHound Finding:** Multiple DA accounts  
**Current DAs:** Administrator, RICHARD.G.JOHNSON

```powershell
# List all Domain Admins
Get-ADGroupMember "Domain Admins" | Select Name, SamAccountName, objectClass

# Evaluate if RICHARD.G.JOHNSON needs DA (use delegation instead)
# Remove-ADGroupMember -Identity "Domain Admins" -Members "RICHARD.G.JOHNSON" -Confirm:$false
```

- [ ] DA membership reviewed
- [ ] Unnecessary DAs removed or converted to delegated admins

---

## PHASE 4: HARDENING & AUDITING (30-60 Minutes)

### 4.1 Enable Advanced Audit Policy
**Required for Splunk detection of attacks**

```powershell
# Enable command-line auditing
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord

# Audit policy via auditpol
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable
auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable
auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable
```

- [ ] Command-line auditing enabled
- [ ] Kerberos auditing enabled
- [ ] Directory service auditing enabled
- [ ] Account management auditing enabled

### 4.2 Protect Sensitive Accounts
**Add high-value accounts to Protected Users group**

```powershell
# Add accounts (breaks NTLM - test first!)
Add-ADGroupMember -Identity "Protected Users" -Members "Administrator"
# Add-ADGroupMember -Identity "Protected Users" -Members "RICHARD.G.JOHNSON"
```

**Warning:** Protected Users disables NTLM. May break legacy apps.

- [ ] Impact assessed
- [ ] Critical accounts added (if safe)

### 4.3 Set AdminSDHolder Monitoring
**Detect permission changes on privileged accounts**

```powershell
# View current AdminSDHolder ACL
(Get-Acl "AD:\CN=AdminSDHolder,CN=System,$((Get-ADDomain).DistinguishedName)").Access | 
    Select IdentityReference, ActiveDirectoryRights | Format-Table
```

- [ ] Baseline AdminSDHolder permissions documented
- [ ] Splunk alert created for changes (EventCode=5136)

### 4.4 Disable LLMNR and NBT-NS
**Prevent credential capture via Responder**

**GPO Path:** Computer Configuration > Administrative Templates > Network > DNS Client
- Turn off multicast name resolution: **Enabled**

**NBT-NS via registry on each system:**
```powershell
# Disable NBT-NS
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
foreach ($adapter in $adapters) {
    $adapter.SetTcpipNetbios(2)  # 2 = Disable NetBIOS over TCP/IP
}
```

- [ ] LLMNR disabled via GPO
- [ ] NBT-NS disabled on DC
- [ ] NBT-NS disabled on member servers/workstations

---

## VERIFICATION CHECKLIST

Run after all phases complete:

| Check | Command | Expected |
|-------|---------|----------|
| Print Spooler | `Get-Service Spooler` | Stopped/Disabled |
| MachineAccountQuota | `(Get-ADDomain).ms-DS-MachineAccountQuota` | 0 |
| LDAP Signing | `reg query "HKLM\SYSTEM\...\NTDS\Parameters" /v LDAPServerIntegrity` | 2 |
| Password Length | `(Get-ADDefaultDomainPasswordPolicy).MinPasswordLength` | >=14 |
| DNS Zones | `Get-DnsServerZone \| Select ZoneName,DynamicUpdate` | Secure |
| SMBv1 | `(Get-SmbServerConfiguration).EnableSMB1Protocol` | False |
| Zerologon | `(Get-ItemProperty "HKLM:\...\Netlogon\Parameters").FullSecureChannelProtection` | 1 |
| Enterprise Admins | `Get-ADGroupMember "Enterprise Admins" -Recursive` | No nested groups |
| Domain Admins | `Get-ADGroupMember "Domain Admins"` | Minimal accounts |
| Admin Sessions | `query user /server:WORKSTATION` | No admin sessions |

---

## KEY EVENT IDS FOR SPLUNK

| Event ID | Attack | Query Priority |
|----------|--------|----------------|
| 4769 | Kerberoasting | HIGH - watch for RC4 |
| 4768 | AS-REP Roast | HIGH |
| 4662 | DCSync | CRITICAL |
| 4741 | Machine Account Created | HIGH (RBCD) |
| 5136 | AD Object Modified | HIGH (RBCD, AdminSDHolder) |
| 4624 Type 3 | Pass-the-Hash | MEDIUM |
| 4624 Type 10 | RDP Logon | MEDIUM |
| 4625 | Failed Logon | Password Spray |
| 4648 | Explicit Credentials | Lateral Movement |
| 4663 | LSASS Access | Credential Dump |

---

## QUICK REFERENCE - WHAT'S ALREADY GOOD

From your assessment, these items are already secure:

[+] No Kerberoastable accounts (no SPNs on user accounts)  
[+] No AS-REP Roastable accounts (preauth enabled on all)  
[+] No unconstrained delegation on non-DCs  
[+] No constrained delegation misconfigurations  
[+] Password policy has 24 history, lockout at 5 attempts  
[+] SMB signing enabled on workstations

---

## ADDITIONAL HARDENING (windows-scripts/)

These scripts in the `AD/` folder focus on Purple Knight and BloodHound findings. For comprehensive Windows hardening, also run the scripts in `windows-scripts/`:

### Recommended Run Order

```powershell
# 1. AD-specific hardening (this folder)
.\AD\RapidDeploy_AllInOne.ps1 -Force

# 2. Comprehensive Windows hardening
.\deploy.ps1 -Quick

# 3. Verify all settings
.\AD\Verify_Hardening.ps1
```

### Additional Coverage from windows-scripts/

| Feature | Script |
|---------|--------|
| Mimikatz mitigations (WDigest, LSASS PPL) | Full-Harden.ps1 |
| Windows Defender + ASR rules | Full-Harden.ps1 |
| UAC hardening | Full-Harden.ps1 |
| Accessibility backdoor removal | Full-Harden.ps1 |
| EternalBlue patch installation | Full-Harden.ps1 |
| Scheduled task auditing | Full-Harden.ps1 |
| ASREP/Kerberoasting fixes | AD-Harden.ps1 |
| DCSync permission audit | AD-Harden.ps1 |

### Print Spooler Note

Both script sets **DISABLE** Print Spooler (PrintNightmare CVE-2021-34527).

If you need printing for an inject, re-enable temporarily:
```powershell
Set-Service Spooler -StartupType Manual
Start-Service Spooler
# Disable again after inject completes
```

---

*Generated for RMCCDC - CCDCTEAM.COM*  
*Run Purple Knight and BloodHound again after hardening to verify improvements*

#Requires -RunAsAdministrator
# CCDC26 - AD Hardening Monolith (DC-ONLY, SELF-CONTAINED)
# Runs unattended via Dovetail. Exits silently on non-DCs.

$ErrorActionPreference = "Continue"

# Exit silently if not a DC
try {
    $domainRole = (Get-CimInstance Win32_ComputerSystem).DomainRole
    if ($domainRole -lt 4) { exit 0 }
} catch { exit 0 }

$LogDir = "C:\ccdc26\logs"
$BackupDir = "C:\ccdc26\backups"
@($LogDir, $BackupDir) | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null } }

function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
function OK      { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
function Err     { param([string]$M) Write-Host "[ERR]  $M" -ForegroundColor Red }
function Section { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Magenta; Write-Host "" }
function Log     { param([string]$M) $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $M" | Out-File "$LogDir\ad-harden.log" -Append -Encoding UTF8 }

try { Import-Module ActiveDirectory -ErrorAction Stop } catch { Err "ActiveDirectory module not available"; exit 1 }

$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName
$domainName = $domain.DNSRoot
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]

$startTime = Get-Date
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  CCDC26 AD Hardening - Domain Controller" -ForegroundColor Cyan
Write-Host "  Domain:   $domainName" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Time:     $(Get-Date)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════════════════
# 1. AD STATE BACKUP
# ═══════════════════════════════════════════════════════════════════════════
Section "AD State Backup"

$backupPath = "$BackupDir\AD_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

Get-ADUser -Filter * -Properties Name, SamAccountName, Enabled, PasswordLastSet, LastLogonDate, MemberOf, Created |
    Select-Object Name, SamAccountName, Enabled, PasswordLastSet, LastLogonDate, Created,
        @{N='Groups';E={($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=','' }) -join '; '}} |
    Export-Csv "$backupPath\Users.csv" -NoTypeInformation

$privGroups = @("Domain Admins","Enterprise Admins","Schema Admins","Administrators",
                "Account Operators","Server Operators","Backup Operators","DnsAdmins")
foreach ($g in $privGroups) {
    try {
        Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue |
            Select-Object Name, SamAccountName, ObjectClass |
            Export-Csv "$backupPath\Group_$($g -replace ' ','_').csv" -NoTypeInformation
    } catch {}
}

try {
    Get-GPO -All | Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime |
        Export-Csv "$backupPath\GPOs.csv" -NoTypeInformation
} catch {}

try {
    Get-DnsServerZone -ErrorAction SilentlyContinue |
        Export-Csv "$backupPath\DNSZones.csv" -NoTypeInformation
} catch {}

OK "AD state backed up to $backupPath"
Log "AD backup created: $backupPath"

# ═══════════════════════════════════════════════════════════════════════════
# 2. ZEROLOGON FIX (CVE-2020-1472)
# ═══════════════════════════════════════════════════════════════════════════
Section "Zerologon Mitigation"

$netlogonPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
Set-ItemProperty -Path $netlogonPath -Name "FullSecureChannelProtection" -Value 1 -Type DWord -Force
Remove-ItemProperty -Path $netlogonPath -Name "vulnerablechannelallowlist" -Force -ErrorAction SilentlyContinue
OK "Zerologon: FullSecureChannelProtection = 1"
Log "Zerologon mitigation applied"

# ═══════════════════════════════════════════════════════════════════════════
# 3. noPac FIX (CVE-2021-42278/42287)
# ═══════════════════════════════════════════════════════════════════════════
Section "noPac Mitigation"

try {
    Set-ADDomain -Identity $domainName -Replace @{"ms-DS-MachineAccountQuota"="0"}
    OK "MachineAccountQuota set to 0"
    Log "noPac: MachineAccountQuota = 0"
} catch {
    Warn "Could not set MachineAccountQuota: $_"
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. FIX ASREP-ROASTABLE ACCOUNTS
# ═══════════════════════════════════════════════════════════════════════════
Section "ASREP-Roastable Accounts"

$asrepVuln = Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} -Properties DoesNotRequirePreAuth
if ($asrepVuln.Count -gt 0) {
    foreach ($u in $asrepVuln) {
        Set-ADAccountControl -Identity $u.SamAccountName -DoesNotRequirePreAuth $false
        OK "Enabled Kerberos preauth: $($u.SamAccountName)"
        Log "Fixed ASREP-roastable: $($u.SamAccountName)"
    }
} else {
    OK "No ASREP-roastable accounts found"
}

# ═══════════════════════════════════════════════════════════════════════════
# 5. FIX KERBEROASTABLE ACCOUNTS
# ═══════════════════════════════════════════════════════════════════════════
Section "Kerberoastable Accounts"

$spnUsers = Get-ADUser -Filter {ServicePrincipalName -like "*"} -Properties ServicePrincipalName, 'msDS-SupportedEncryptionTypes' |
    Where-Object { $_.SamAccountName -ne "krbtgt" }

foreach ($u in $spnUsers) {
    $encTypes = $u.'msDS-SupportedEncryptionTypes'
    if (($encTypes -band 0x18) -eq 0) {
        Set-ADUser -Identity $u.SamAccountName -Replace @{'msDS-SupportedEncryptionTypes' = 24}
        OK "Enabled AES for service account: $($u.SamAccountName)"
        Log "Fixed Kerberoastable: $($u.SamAccountName)"
    }
}
if ($spnUsers.Count -eq 0) { OK "No service accounts with SPNs found" }

# ═══════════════════════════════════════════════════════════════════════════
# 6. CLEAN PRIVILEGED GROUPS
# ═══════════════════════════════════════════════════════════════════════════
Section "Privileged Group Cleanup"

$protectedUsers = @($currentUser, "Administrator")
$groupsToClean = @{
    "Domain Admins"     = @("Administrator")
    "Enterprise Admins" = @("Administrator")
    "Schema Admins"     = @("Administrator")
    "DnsAdmins"         = @()
    "Account Operators" = @()
    "Server Operators"  = @()
    "Backup Operators"  = @()
}

foreach ($group in $groupsToClean.Keys) {
    try {
        $members = Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue
        if (-not $members) { continue }

        $allowed = $groupsToClean[$group] + $protectedUsers

        foreach ($member in $members) {
            if ($member.SamAccountName -notin $allowed) {
                try {
                    Remove-ADGroupMember -Identity $group -Members $member.SamAccountName -Confirm:$false
                    OK "Removed $($member.SamAccountName) from $group"
                    Log "Removed $($member.SamAccountName) from $group"
                } catch {
                    Warn "Could not remove $($member.SamAccountName) from ${group}: $_"
                }
            }
        }
    } catch {
        Warn "Could not process group: $group"
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# 7. DISABLE GUEST / krbtgt ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════
Section "Account Lockdown"

try {
    $guest = Get-ADUser -Filter {SamAccountName -eq "Guest"} -ErrorAction SilentlyContinue
    if ($guest -and $guest.Enabled) {
        Disable-ADAccount -Identity "Guest"
        OK "Guest account disabled"
    }
} catch {}

try {
    $krbtgt = Get-ADUser -Filter {SamAccountName -eq "krbtgt"} -ErrorAction SilentlyContinue
    if ($krbtgt -and $krbtgt.Enabled) {
        Disable-ADAccount -Identity "krbtgt"
        OK "krbtgt account disabled"
    }
} catch {}
Log "Guest and krbtgt accounts locked down"

# ═══════════════════════════════════════════════════════════════════════════
# 8. KRBTGT PASSWORD ROTATION (TWICE for golden ticket invalidation)
# ═══════════════════════════════════════════════════════════════════════════
Section "krbtgt Password Rotation"

$chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*()"
function New-RandomPW { return -join (1..32 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }) }

Info "Rotating krbtgt password (pass 1 of 2)..."
try {
    $pw1 = New-RandomPW
    Set-ADAccountPassword -Identity "krbtgt" -NewPassword (ConvertTo-SecureString $pw1 -AsPlainText -Force) -Reset
    OK "krbtgt password rotated (pass 1)"
    Log "krbtgt password rotated (pass 1)"
} catch {
    Warn "krbtgt rotation pass 1 failed: $_"
}

Info "Waiting 10 seconds before second rotation..."
Start-Sleep -Seconds 10

Info "Rotating krbtgt password (pass 2 of 2)..."
try {
    $pw2 = New-RandomPW
    Set-ADAccountPassword -Identity "krbtgt" -NewPassword (ConvertTo-SecureString $pw2 -AsPlainText -Force) -Reset
    OK "krbtgt password rotated (pass 2) -- golden tickets invalidated"
    Log "krbtgt password rotated (pass 2)"
} catch {
    Warn "krbtgt rotation pass 2 failed: $_"
}

# ═══════════════════════════════════════════════════════════════════════════
# 9. LDAP SIGNING
# ═══════════════════════════════════════════════════════════════════════════
Section "LDAP Signing"

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LDAP" -Name "LDAPClientIntegrity" -Value 2 -Type DWord -Force
$ntdsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"
if (-not (Test-Path $ntdsPath)) { New-Item -Path $ntdsPath -Force | Out-Null }
Set-ItemProperty -Path $ntdsPath -Name "LDAPServerIntegrity" -Value 2 -Type DWord -Force
OK "LDAP client + server signing required"
Log "LDAP signing enforced"

# ═══════════════════════════════════════════════════════════════════════════
# 10. REGISTRY SACLs (credential theft detection)
# ═══════════════════════════════════════════════════════════════════════════
Section "Registry SACLs for Credential Theft Detection"

$sensitiveKeys = @(
    "HKLM:\SAM",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\JD",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Skew1",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\GBG",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Data"
)
$saclOK = 0
foreach ($keyPath in $sensitiveKeys) {
    if (-not (Test-Path $keyPath)) { continue }
    try {
        $acl = Get-Acl -Path $keyPath -Audit -ErrorAction Stop
        $auditRule = New-Object System.Security.AccessControl.RegistryAuditRule(
            [System.Security.Principal.SecurityIdentifier]::new("S-1-1-0"),
            [System.Security.AccessControl.RegistryRights]::ReadKey,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AuditFlags]::Success
        )
        $acl.AddAuditRule($auditRule)
        Set-Acl -Path $keyPath -AclObject $acl -ErrorAction Stop
        $saclOK++
    } catch {}
}
OK "Registry SACLs set on $saclOK sensitive keys"
Log "Registry SACLs configured"

# ═══════════════════════════════════════════════════════════════════════════
# 11. DCYNC AUDIT
# ═══════════════════════════════════════════════════════════════════════════
Section "DCSync Permission Audit"

try {
    $acl = Get-Acl "AD:\$domainDN"
    $dsRepGetChanges    = "1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"
    $dsRepGetChangesAll = "1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"

    $dcsyncIdentities = @()
    foreach ($ace in $acl.Access) {
        if ($ace.ObjectType -in @($dsRepGetChanges, $dsRepGetChangesAll)) {
            $dcsyncIdentities += $ace.IdentityReference.Value
        }
    }
    $dcsyncIdentities = $dcsyncIdentities | Select-Object -Unique

    $expected = @("NT AUTHORITY\ENTERPRISE DOMAIN CONTROLLERS",
                  "$domainName\Domain Controllers",
                  "NT AUTHORITY\SYSTEM",
                  "BUILTIN\Administrators",
                  "$domainName\Enterprise Admins")

    foreach ($id in $dcsyncIdentities) {
        $isExpected = $expected | Where-Object { $id -like "*$_*" -or $id -eq $_ }
        if (-not $isExpected) {
            Warn "SUSPICIOUS DCSync permission: $id"
            Log "SUSPICIOUS DCSync: $id"
        }
    }
    OK "DCSync audit complete"
} catch {
    Warn "DCSync audit failed: $_"
}

# ═══════════════════════════════════════════════════════════════════════════
# 12. PASSWORD POLICY
# ═══════════════════════════════════════════════════════════════════════════
Section "Domain Password Policy"

try {
    $minLen = (Get-ADDefaultDomainPasswordPolicy).MinPasswordLength
    if ($minLen -lt 14) {
        Set-ADDefaultDomainPasswordPolicy -Identity $domainName -MinPasswordLength 14 -LockoutThreshold 5 `
            -LockoutDuration "00:15:00" -LockoutObservationWindow "00:15:00" `
            -ComplexityEnabled $true -PasswordHistoryCount 24
        OK "Domain password policy updated (min 14 chars, lockout 5 attempts)"
    } else {
        OK "Password policy already strong (min length: $minLen)"
    }
} catch {
    Warn "Could not update password policy: $_"
}
Log "Password policy checked/updated"

# ═══════════════════════════════════════════════════════════════════════════
# 13. FIX PASSWORDNEVEREXPIRES
# ═══════════════════════════════════════════════════════════════════════════
Section "PasswordNeverExpires Cleanup"

$pneUsers = Get-ADUser -Filter {PasswordNeverExpires -eq $true -and Enabled -eq $true} |
    Where-Object { $_.SamAccountName -notin @("krbtgt") }
foreach ($u in $pneUsers) {
    Set-ADUser -Identity $u.SamAccountName -PasswordNeverExpires $false
    OK "Cleared PasswordNeverExpires: $($u.SamAccountName)"
}
if ($pneUsers.Count -eq 0) { OK "No accounts with PasswordNeverExpires" }
Log "PasswordNeverExpires cleanup done"

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  AD HARDENING COMPLETE in $elapsed seconds" -ForegroundColor Green
Write-Host "  Backup: $backupPath" -ForegroundColor Green
Write-Host "  Log:    $LogDir\ad-harden.log" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Log "AD hardening completed in ${elapsed}s"

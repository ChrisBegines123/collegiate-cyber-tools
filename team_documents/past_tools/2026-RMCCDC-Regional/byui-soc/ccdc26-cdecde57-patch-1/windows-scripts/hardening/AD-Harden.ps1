# CCDC26 Windows Toolkit - Active Directory Hardening
# Domain Controller and AD-specific hardening
# Run as Domain Admin on a Domain Controller

#Requires -RunAsAdministrator

#=============================================================================
# INITIALIZATION
#=============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\lib\common.ps1"
. "$ScriptDir\lib\passwords.ps1"

Require-Administrator

# Verify we're on a Domain Controller
$OSInfo = Get-OSInfo
if (-not $OSInfo.IsDomainController) {
    Error "This script must be run on a Domain Controller"
    Write-Host "For non-DC Windows systems, use Full-Harden.ps1" -ForegroundColor Yellow
    exit 1
}

# Import AD module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Error "ActiveDirectory module not available"
    exit 1
}
Import-Module ActiveDirectory

Header "CCDC26 Active Directory Hardening"
Write-Host "Domain: $($OSInfo.DomainName)" -ForegroundColor Gray
Write-Host "Computer: $($OSInfo.ComputerName)" -ForegroundColor Gray
Write-Host ""

#=============================================================================
# BACKUP FUNCTIONS
#=============================================================================
function Backup-ADState {
    Header "Creating AD State Backup"
    
    $backupDir = "C:\CCDC-Toolkit\backups\AD_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    # Backup GPO list
    Get-GPO -All | Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime | 
        Export-Csv "$backupDir\GPOs.csv" -NoTypeInformation
    
    # Backup privileged groups
    $privGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators", 
                    "Account Operators", "Server Operators", "Backup Operators", "DnsAdmins")
    
    foreach ($group in $privGroups) {
        try {
            Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue | 
                Select-Object Name, SamAccountName, ObjectClass |
                Export-Csv "$backupDir\Group_$($group -replace ' ', '_').csv" -NoTypeInformation
        }
        catch { }
    }
    
    # Backup all users
    Get-ADUser -Filter * -Properties * | 
        Select-Object Name, SamAccountName, Enabled, PasswordLastSet, LastLogonDate, MemberOf |
        Export-Csv "$backupDir\Users.csv" -NoTypeInformation
    
    # Backup DNS zones
    try {
        Get-DnsServerZone -ErrorAction SilentlyContinue | 
            Export-Csv "$backupDir\DNSZones.csv" -NoTypeInformation
    }
    catch { }
    
    Success "AD state backed up to: $backupDir"
    Log-Action "Created AD state backup at $backupDir"
    
    return $backupDir
}

#=============================================================================
# USER MANAGEMENT
#=============================================================================
function Invoke-MassDisableUsers {
    Header "Mass Disable AD Users"
    
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
    
    Write-Host "This will DISABLE all AD users except:" -ForegroundColor Yellow
    Write-Host "  - $currentUser (you)" -ForegroundColor Gray
    Write-Host "  - krbtgt (required)" -ForegroundColor Gray
    Write-Host "  - Administrator (built-in)" -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Prompt-YesNo "Continue with mass disable?"
    if (-not $confirm) {
        Info "Skipping mass disable"
        return
    }
    
    $protectedUsers = @($currentUser, "krbtgt", "Administrator")
    
    $users = Get-ADUser -Filter {Enabled -eq $true} | Where-Object {
        $_.SamAccountName -notin $protectedUsers
    }
    
    $disabledCount = 0
    foreach ($user in $users) {
        try {
            Disable-ADAccount -Identity $user.SamAccountName
            $disabledCount++
            Log-Action "Disabled AD user: $($user.SamAccountName)"
        }
        catch {
            Warn "Could not disable: $($user.SamAccountName)"
        }
    }
    
    Success "Disabled $disabledCount AD users"
}

function Add-CompetitionUsers {
    Header "Adding Competition Users"
    
    $salt = Read-Host "Enter team password salt"
    if ([string]::IsNullOrEmpty($salt)) {
        Error "Salt cannot be empty"
        return
    }
    
    # Create competition admin users
    $users = @(
        @{Name = "ccdcadmin1"; Admin = $true},
        @{Name = "ccdcadmin2"; Admin = $true},
        @{Name = "ccdcuser1"; Admin = $false}
    )
    
    foreach ($userDef in $users) {
        $username = $userDef.Name
        $password = Get-DeterministicPassword -Username $username -Salt $salt
        $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        
        try {
            # Check if user exists
            $existingUser = Get-ADUser -Filter {SamAccountName -eq $username} -ErrorAction SilentlyContinue
            
            if ($existingUser) {
                # Reset password
                Set-ADAccountPassword -Identity $username -NewPassword $securePassword -Reset
                Enable-ADAccount -Identity $username
                Success "Reset password for existing user: $username"
            }
            else {
                # Create new user
                New-ADUser -Name $username `
                    -SamAccountName $username `
                    -UserPrincipalName "$username@$($OSInfo.DomainName)" `
                    -AccountPassword $securePassword `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -CannotChangePassword $false
                
                Success "Created user: $username"
            }
            
            # Add to appropriate groups
            if ($userDef.Admin) {
                Add-ADGroupMember -Identity "Domain Admins" -Members $username -ErrorAction SilentlyContinue
                Add-ADGroupMember -Identity "Administrators" -Members $username -ErrorAction SilentlyContinue
                Info "  Added to Domain Admins"
            }
            
            Add-ADGroupMember -Identity "Remote Desktop Users" -Members $username -ErrorAction SilentlyContinue
            
            Write-Host "  Password: $password" -ForegroundColor Green
            Log-Action "Created/updated competition user: $username"
        }
        catch {
            Error "Failed to create/update user $username : $_"
        }
    }
}

function Reset-AllADPasswords {
    Header "Reset All AD User Passwords"
    
    $salt = Read-Host "Enter team password salt"
    if ([string]::IsNullOrEmpty($salt)) {
        Error "Salt cannot be empty"
        return
    }
    
    Write-Host "This will reset passwords for ALL enabled AD users" -ForegroundColor Yellow
    $confirm = Prompt-YesNo "Continue?"
    if (-not $confirm) {
        return
    }
    
    $users = Get-ADUser -Filter {Enabled -eq $true} | Where-Object {
        $_.SamAccountName -ne "krbtgt"
    }
    
    $outputFile = "C:\CCDC-Toolkit\logs\password_reset_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    
    foreach ($user in $users) {
        $username = $user.SamAccountName
        $password = Get-DeterministicPassword -Username $username -Salt $salt
        
        try {
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
            Set-ADAccountPassword -Identity $username -NewPassword $securePassword -Reset
            
            "$username : $password" | Out-File -FilePath $outputFile -Append
            Success "Reset password: $username"
        }
        catch {
            Warn "Failed to reset: $username"
        }
    }
    
    Success "Password list saved to: $outputFile"
    Warn "DELETE THIS FILE AFTER USE!"
    Log-Action "Reset all AD passwords"
}

#=============================================================================
# PRIVILEGED GROUP MANAGEMENT
#=============================================================================
function Clean-PrivilegedGroups {
    Header "Cleaning Privileged Groups"
    
    # Groups and their expected members
    $groupConfig = @{
        "Domain Admins" = @("Administrator")
        "Enterprise Admins" = @("Administrator")
        "Schema Admins" = @("Administrator")
        "DnsAdmins" = @()
        "Account Operators" = @()
        "Server Operators" = @()
        "Backup Operators" = @()
        "Remote Desktop Users" = @()
        "Remote Management Users" = @()
    }
    
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
    
    foreach ($group in $groupConfig.Keys) {
        Header "Processing: $group"
        
        try {
            $members = Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue
            
            if (-not $members) {
                Info "  No members"
                continue
            }
            
            $allowedMembers = $groupConfig[$group]
            # Always allow current user and CCDC admins
            $allowedMembers += @($currentUser, "ccdcadmin1", "ccdcadmin2")
            
            foreach ($member in $members) {
                if ($member.SamAccountName -in $allowedMembers) {
                    Info "  Keeping: $($member.SamAccountName)"
                }
                else {
                    Write-Host "  Found: $($member.SamAccountName)" -ForegroundColor Yellow
                    $remove = Prompt-YesNo "  Remove from $group?"
                    if ($remove) {
                        Remove-ADGroupMember -Identity $group -Members $member.SamAccountName -Confirm:$false
                        Success "  Removed: $($member.SamAccountName)"
                        Log-Action "Removed $($member.SamAccountName) from $group"
                    }
                }
            }
        }
        catch {
            Warn "Could not process group: $group"
        }
    }
}

#=============================================================================
# KERBEROS HARDENING
#=============================================================================
function Fix-ASREPRoastableAccounts {
    Header "Fixing ASREP-Roastable Accounts"
    
    # Find accounts with "Do not require Kerberos preauthentication"
    $vulnerable = Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} -Properties DoesNotRequirePreAuth
    
    if ($vulnerable.Count -eq 0) {
        Success "No ASREP-roastable accounts found"
        return
    }
    
    Write-Host "Found $($vulnerable.Count) vulnerable accounts:" -ForegroundColor Yellow
    foreach ($user in $vulnerable) {
        Write-Host "  - $($user.SamAccountName)" -ForegroundColor Red
        Log-Finding "ASREP-roastable account: $($user.SamAccountName)"
    }
    
    $fix = Prompt-YesNo "Enable Kerberos preauth for all?"
    if ($fix) {
        foreach ($user in $vulnerable) {
            Set-ADAccountControl -Identity $user.SamAccountName -DoesNotRequirePreAuth $false
            Success "Fixed: $($user.SamAccountName)"
            Log-Action "Enabled Kerberos preauth for: $($user.SamAccountName)"
        }
    }
}

function Fix-KerberoastableAccounts {
    Header "Fixing Kerberoastable Accounts"
    
    # Find user accounts with SPNs (excluding computer accounts and krbtgt)
    $spnUsers = Get-ADUser -Filter {ServicePrincipalName -like "*"} -Properties ServicePrincipalName, msDS-SupportedEncryptionTypes |
        Where-Object { $_.SamAccountName -ne "krbtgt" }
    
    if ($spnUsers.Count -eq 0) {
        Success "No service accounts with SPNs found"
        return
    }
    
    Write-Host "Found $($spnUsers.Count) accounts with SPNs:" -ForegroundColor Yellow
    foreach ($user in $spnUsers) {
        $encTypes = $user.'msDS-SupportedEncryptionTypes'
        $aesEnabled = ($encTypes -band 0x18) -ne 0  # AES128 or AES256
        
        $status = if ($aesEnabled) { "[AES OK]" } else { "[VULNERABLE]" }
        $color = if ($aesEnabled) { "Green" } else { "Red" }
        
        Write-Host "  $status $($user.SamAccountName)" -ForegroundColor $color
        Write-Host "        SPNs: $($user.ServicePrincipalName -join ', ')" -ForegroundColor Gray
        
        if (-not $aesEnabled) {
            Log-Finding "Kerberoastable account (no AES): $($user.SamAccountName)"
        }
    }
    
    $fix = Prompt-YesNo "Enable AES encryption for accounts without it?"
    if ($fix) {
        foreach ($user in $spnUsers) {
            $encTypes = $user.'msDS-SupportedEncryptionTypes'
            if (($encTypes -band 0x18) -eq 0) {
                # Enable AES128 + AES256 (0x18 = 24)
                Set-ADUser -Identity $user.SamAccountName -Replace @{'msDS-SupportedEncryptionTypes' = 24}
                Success "Enabled AES for: $($user.SamAccountName)"
                Log-Action "Enabled AES encryption for: $($user.SamAccountName)"
            }
        }
    }
}

function Audit-DCSync {
    Header "Auditing DCSync Permissions"
    
    # Get the domain DN
    $domainDN = (Get-ADDomain).DistinguishedName
    
    # Get ACLs on domain object
    $acl = Get-Acl "AD:\$domainDN"
    
    # DCSync-relevant GUIDs
    $dsReplicationGetChanges = "1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"
    $dsReplicationGetChangesAll = "1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"
    
    $dcsyncUsers = @()
    
    foreach ($ace in $acl.Access) {
        if ($ace.ObjectType -in @($dsReplicationGetChanges, $dsReplicationGetChangesAll)) {
            $dcsyncUsers += $ace.IdentityReference.Value
        }
    }
    
    $dcsyncUsers = $dcsyncUsers | Select-Object -Unique
    
    if ($dcsyncUsers.Count -gt 0) {
        Write-Host "Accounts with replication permissions (potential DCSync):" -ForegroundColor Yellow
        foreach ($user in $dcsyncUsers) {
            # Expected accounts
            $expected = @("NT AUTHORITY\ENTERPRISE DOMAIN CONTROLLERS", 
                         "$($OSInfo.DomainName)\Domain Controllers",
                         "NT AUTHORITY\SYSTEM",
                         "BUILTIN\Administrators",
                         "$($OSInfo.DomainName)\Enterprise Admins")
            
            $isExpected = $expected | Where-Object { $user -like "*$_*" }
            
            if ($isExpected) {
                Info "  [EXPECTED] $user"
            }
            else {
                Finding "  [SUSPICIOUS] $user"
                Log-Finding "Suspicious DCSync permission: $user"
            }
        }
    }
}

#=============================================================================
# ZEROLOGON MITIGATION
#=============================================================================
function Patch-Zerologon {
    Header "Applying Zerologon Mitigation (CVE-2020-1472)"
    
    $netlogonPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
    
    # Enable secure channel protection
    Set-ItemProperty -Path $netlogonPath -Name "FullSecureChannelProtection" -Value 1 -Type DWord -Force
    Success "Secure channel protection enabled"
    
    # Remove any vulnerable channel allowlist
    Remove-ItemProperty -Path $netlogonPath -Name "vulnerablechannelallowlist" -Force -ErrorAction SilentlyContinue
    Success "Vulnerable channel allowlist removed"
    
    Log-Action "Applied Zerologon mitigations (CVE-2020-1472)"
}

#=============================================================================
# NOPAC MITIGATION
#=============================================================================
function Patch-NoPac {
    Header "Applying noPac Mitigation (CVE-2021-42278/42287)"
    
    # Set machine account quota to 0
    try {
        Set-ADDomain -Identity $OSInfo.DomainName -Replace @{"ms-DS-MachineAccountQuota"="0"}
        Success "Machine account quota set to 0"
        Log-Action "Set ms-DS-MachineAccountQuota to 0 (noPac mitigation)"
    }
    catch {
        Warn "Could not set machine account quota: $_"
    }
}

#=============================================================================
# LDAP SIGNING
#=============================================================================
function Enable-LDAPSigning {
    Header "Enabling LDAP Signing Requirements"
    
    # Client signing
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LDAP" -Name "LDAPClientIntegrity" -Value 2 -Type DWord -Force
    Success "LDAP client signing required"
    
    # Server signing (NTDS)
    $ntdsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"
    if (-not (Test-Path $ntdsPath)) {
        New-Item -Path $ntdsPath -Force | Out-Null
    }
    Set-ItemProperty -Path $ntdsPath -Name "LDAPServerIntegrity" -Value 2 -Type DWord -Force
    Success "LDAP server signing required"
    
    Log-Action "Enabled LDAP signing requirements"
}

#=============================================================================
# GPO SECURITY
#=============================================================================
function Create-SecurityGPO {
    Header "Creating Security GPO"
    
    $gpoName = "CCDC-Security-Hardening"
    
    # Check if GPO exists
    $existingGPO = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if ($existingGPO) {
        $overwrite = Prompt-YesNo "GPO '$gpoName' already exists. Recreate?"
        if ($overwrite) {
            Remove-GPO -Name $gpoName -Confirm:$false
        }
        else {
            return
        }
    }
    
    # Create GPO
    $gpo = New-GPO -Name $gpoName -Comment "CCDC26 Security Hardening GPO"
    
    # Link to domain
    $domainDN = (Get-ADDomain).DistinguishedName
    New-GPLink -Name $gpoName -Target $domainDN -LinkEnabled Yes -ErrorAction SilentlyContinue
    
    # Configure GPO settings via registry preferences
    $gpoPath = "\\$($OSInfo.DomainName)\SYSVOL\$($OSInfo.DomainName)\Policies\{$($gpo.Id)}"
    
    Info "GPO created: $gpoName"
    Info "Apply additional settings via Group Policy Management Console"
    
    Write-Host "`nRecommended GPO settings:" -ForegroundColor Yellow
    Write-Host "  - Computer > Policies > Windows Settings > Security Settings" -ForegroundColor Gray
    Write-Host "  - Account Policies > Password Policy" -ForegroundColor Gray
    Write-Host "  - Local Policies > User Rights Assignment" -ForegroundColor Gray
    Write-Host "  - Local Policies > Security Options" -ForegroundColor Gray
    
    Log-Action "Created security GPO: $gpoName"
}

#=============================================================================
# QUICK AD HARDEN
#=============================================================================
function Invoke-QuickADHarden {
    Header "QUICK AD HARDEN MODE"
    
    $startTime = Get-Date
    
    # Backup first
    Backup-ADState
    
    # CVE patches
    Patch-Zerologon
    Patch-NoPac
    Enable-LDAPSigning
    
    # Kerberos hardening
    Fix-ASREPRoastableAccounts
    Fix-KerberoastableAccounts
    
    # Audit
    Audit-DCSync
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Header "Quick AD Harden Complete"
    Success "Completed in $([math]::Round($duration, 1)) seconds"
    
    Write-Host ""
    Write-Host "IMPORTANT NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Run Full-Harden.ps1 for base Windows hardening" -ForegroundColor Gray
    Write-Host "2. Use 'Add-CompetitionUsers' to create team accounts" -ForegroundColor Gray
    Write-Host "3. Use 'Invoke-MassDisableUsers' to disable all other users" -ForegroundColor Gray
    Write-Host "4. Use 'Clean-PrivilegedGroups' to remove unauthorized admins" -ForegroundColor Gray
    Write-Host "5. Reset all passwords with 'Reset-AllADPasswords'" -ForegroundColor Gray
    Write-Host ""
    
    Log-Action "Quick AD harden completed"
}

#=============================================================================
# MAIN MENU
#=============================================================================
function Show-Menu {
    Write-Host ""
    Write-Host "AD Hardening Options:" -ForegroundColor Cyan
    Write-Host "1)  Quick AD Harden (CVE patches + Kerberos fixes)"
    Write-Host "2)  Backup AD State"
    Write-Host "3)  Mass Disable Users"
    Write-Host "4)  Add Competition Users"
    Write-Host "5)  Reset All AD Passwords"
    Write-Host "6)  Clean Privileged Groups"
    Write-Host "7)  Fix ASREP-Roastable Accounts"
    Write-Host "8)  Fix Kerberoastable Accounts"
    Write-Host "9)  Audit DCSync Permissions"
    Write-Host "10) Apply Zerologon Mitigation"
    Write-Host "11) Apply noPac Mitigation"
    Write-Host "12) Enable LDAP Signing"
    Write-Host "13) Create Security GPO"
    Write-Host ""
    
    $choice = Read-Host "Select option [1-13]"
    
    switch ($choice) {
        "1"  { Invoke-QuickADHarden }
        "2"  { Backup-ADState }
        "3"  { Invoke-MassDisableUsers }
        "4"  { Add-CompetitionUsers }
        "5"  { Reset-AllADPasswords }
        "6"  { Clean-PrivilegedGroups }
        "7"  { Fix-ASREPRoastableAccounts }
        "8"  { Fix-KerberoastableAccounts }
        "9"  { Audit-DCSync }
        "10" { Patch-Zerologon }
        "11" { Patch-NoPac }
        "12" { Enable-LDAPSigning }
        "13" { Create-SecurityGPO }
        default { Error "Invalid option" }
    }
}

# Main entry point
if ($args -contains "-q" -or $args -contains "--quick") {
    Invoke-QuickADHarden
}
else {
    Show-Menu
}

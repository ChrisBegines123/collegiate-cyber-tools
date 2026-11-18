#Requires -RunAsAdministrator
# CCDC26 - Comprehensive Auditing Configuration (SELF-CONTAINED)
# Enables all audit subcategories, PowerShell logging, firewall logging, registry SACLs.

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
function OK      { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
function Section { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Magenta; Write-Host "" }
function Log     { param([string]$M) $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $M" | Out-File "$LogDir\audit-setup.log" -Append -Encoding UTF8 }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CCDC26 Audit Configuration" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$startTime = Get-Date

# ═══════════════════════════════════════════════════════════════════════════
# 1. ADVANCED AUDIT SUBCATEGORIES
# ═══════════════════════════════════════════════════════════════════════════
Section "Advanced Audit Policy"

$auditCategories = @(
    "Security State Change","Security System Extension","System Integrity",
    "IPsec Driver","Other System Events",
    "Logon","Logoff","Account Lockout","IPsec Main Mode","IPsec Quick Mode",
    "IPsec Extended Mode","Special Logon","Other Logon/Logoff Events",
    "Network Policy Server","User / Device Claims","Group Membership",
    "File System","Registry","Kernel Object","SAM","Certification Services",
    "Application Generated","Handle Manipulation","File Share",
    "Filtering Platform Packet Drop","Filtering Platform Connection",
    "Other Object Access Events","Detailed File Share","Removable Storage",
    "Central Policy Staging",
    "Sensitive Privilege Use","Non Sensitive Privilege Use","Other Privilege Use Events",
    "Process Creation","Process Termination","DPAPI Activity","RPC Events",
    "Plug and Play Events","Token Right Adjusted Events",
    "Audit Policy Change","Authentication Policy Change","Authorization Policy Change",
    "MPSSVC Rule-Level Policy Change","Filtering Platform Policy Change",
    "Other Policy Change Events",
    "User Account Management","Computer Account Management","Security Group Management",
    "Distribution Group Management","Application Group Management",
    "Other Account Management Events",
    "Directory Service Access","Directory Service Changes",
    "Directory Service Replication","Detailed Directory Service Replication",
    "Credential Validation","Kerberos Service Ticket Operations",
    "Other Account Logon Events","Kerberos Authentication Service"
)

$ok = 0; $fail = 0
foreach ($cat in $auditCategories) {
    $r = auditpol /set /subcategory:"$cat" /success:enable /failure:enable 2>&1
    if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail++ }
}
OK "Enabled $ok audit subcategories ($fail failed/unsupported)"
Log "Audit subcategories: $ok OK, $fail failed"

# Registry-based auditing
$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$auditSettings = @{
    AuditLogonEvents=3; AuditAccountLogon=3; AuditAccountManage=3
    AuditDSAccess=3; AuditObjectAccess=3; AuditPolicyChange=3
    AuditPrivilegeUse=3; AuditProcessTracking=3; AuditSystemEvents=3
}
foreach ($s in $auditSettings.GetEnumerator()) {
    Set-ItemProperty -Path $lsaPath -Name $s.Key -Value $s.Value -Type DWord -Force -ErrorAction SilentlyContinue
}
OK "Registry audit settings configured"

# ═══════════════════════════════════════════════════════════════════════════
# 2. COMMAND LINE AUDITING
# ═══════════════════════════════════════════════════════════════════════════
Section "Command Line Auditing"

$auditPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
if (-not (Test-Path $auditPath)) { New-Item -Path $auditPath -Force | Out-Null }
Set-ItemProperty -Path $auditPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord -Force
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable 2>$null | Out-Null
OK "Command line in process creation events enabled (Event ID 4688)"
Log "Command line auditing enabled"

# ═══════════════════════════════════════════════════════════════════════════
# 3. POWERSHELL LOGGING
# ═══════════════════════════════════════════════════════════════════════════
Section "PowerShell Logging"

# Script Block Logging
$sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $sbPath)) { New-Item -Path $sbPath -Force | Out-Null }
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockInvocationLogging" -Value 1 -Type DWord -Force
OK "Script Block Logging enabled"

# Module Logging
$mlPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
if (-not (Test-Path $mlPath)) { New-Item -Path $mlPath -Force | Out-Null }
Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord -Force
$mlMod = "$mlPath\ModuleNames"
if (-not (Test-Path $mlMod)) { New-Item -Path $mlMod -Force | Out-Null }
Set-ItemProperty -Path $mlMod -Name "*" -Value "*" -Type String -Force
OK "Module Logging enabled (all modules)"

# Transcription
$transPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"
if (-not (Test-Path $transPath)) { New-Item -Path $transPath -Force | Out-Null }
Set-ItemProperty -Path $transPath -Name "EnableTranscripting" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $transPath -Name "EnableInvocationHeader" -Value 1 -Type DWord -Force
$transDir = "C:\ccdc26\logs\powershell"
if (-not (Test-Path $transDir)) { New-Item -ItemType Directory -Path $transDir -Force | Out-Null }
Set-ItemProperty -Path $transPath -Name "OutputDirectory" -Value $transDir -Type String -Force
OK "Transcription enabled -> $transDir"
Log "PowerShell logging fully enabled"

# ═══════════════════════════════════════════════════════════════════════════
# 4. FIREWALL LOGGING
# ═══════════════════════════════════════════════════════════════════════════
Section "Firewall Logging"

$profiles = @("Domain","Public","Private")
foreach ($p in $profiles) {
    try {
        Set-NetFirewallProfile -Profile $p -LogAllowed True -LogBlocked True `
            -LogFileName "%systemroot%\system32\LogFiles\Firewall\pfirewall.log" `
            -LogMaxSizeKilobytes 20000 -ErrorAction SilentlyContinue
    } catch {
        netsh advfirewall set ${p}profile logging filename "%systemroot%\system32\LogFiles\Firewall\pfirewall.log" 2>$null
        netsh advfirewall set ${p}profile logging maxfilesize 20000 2>$null
        netsh advfirewall set ${p}profile logging droppedconnections enable 2>$null
        netsh advfirewall set ${p}profile logging allowedconnections enable 2>$null
    }
}
OK "Firewall logging enabled (all profiles)"
Log "Firewall logging configured"

# ═══════════════════════════════════════════════════════════════════════════
# 5. REGISTRY SACLs (SAM/LSA credential theft detection)
# ═══════════════════════════════════════════════════════════════════════════
Section "Registry SACL Monitoring"

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
    } catch {
        Warn "SACL failed on ${keyPath}: $_"
    }
}
OK "Registry SACLs set on $saclOK sensitive keys (triggers 4656/4663)"
Log "Registry SACLs configured"

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Audit Configuration Complete ($elapsed s)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Security Event Log (4624/4625/4688/...)" -ForegroundColor Gray
Write-Host "  PowerShell: Script Block + Module + Transcription" -ForegroundColor Gray
Write-Host "  Firewall: pfirewall.log" -ForegroundColor Gray
Write-Host "  Transcripts: $transDir" -ForegroundColor Gray
Log "Audit configuration completed in ${elapsed}s"

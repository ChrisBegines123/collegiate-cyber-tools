#Requires -RunAsAdministrator
# CCDC26 - BLITZ: Monolith Windows Hardening (SELF-CONTAINED)
# Run unattended via Dovetail or standalone. NO external dependencies.
# Consolidates: Full-Harden.ps1 + common.ps1 + auditing.ps1 + passwords.ps1

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
$BackupDir = "C:\ccdc26\backups"
if (-not (Test-Path $LogDir))    { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

# ── Inline helpers ──
function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
function OK      { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
function Err     { param([string]$M) Write-Host "[ERR]  $M" -ForegroundColor Red }
function Section { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Magenta; Write-Host "" }
function Log     { param([string]$M) $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $M" | Out-File "$LogDir\blitz.log" -Append -Encoding UTF8 }

function Get-IsServer { return (Get-CimInstance Win32_OperatingSystem).Caption -match "Server" }
function Get-IsDC {
    try { return (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4 } catch { return $false }
}
function Get-IsDomainJoined { return (Get-CimInstance Win32_ComputerSystem).PartOfDomain }

$startTime = Get-Date
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  CCDC26 BLITZ - Windows Hardening Monolith" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Time:     $(Get-Date)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════════════════
# 1. CVE PATCHES
# ═══════════════════════════════════════════════════════════════════════════
Section "CVE Patches & Vulnerability Mitigations"

# EternalBlue: disable SMBv1
Info "Disabling SMBv1 (EternalBlue mitigation)..."
try {
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
    OK "SMBv1 server disabled"
} catch {
    dism /online /disable-feature /featurename:SMB1Protocol /NoRestart 2>$null | Out-Null
    OK "SMBv1 disabled via DISM"
}
try {
    $smbClient = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol-Client -ErrorAction SilentlyContinue
    if ($smbClient -and $smbClient.State -eq "Enabled") {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol-Client -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
} catch {}
Log "Disabled SMBv1"

# PrintNightmare
Info "Applying PrintNightmare mitigations..."
$printerPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers"
if (-not (Test-Path $printerPath)) { New-Item -Path $printerPath -Force | Out-Null }
Set-ItemProperty -Path $printerPath -Name "RegisterSpoolerRemoteRpcEndPoint" -Value 2 -Type DWord -Force
$ppPath = "$printerPath\PointAndPrint"
if (-not (Test-Path $ppPath)) { New-Item -Path $ppPath -Force | Out-Null }
Set-ItemProperty -Path $ppPath -Name "RestrictDriverInstallationToAdministrators" -Value 1 -Type DWord -Force
Remove-ItemProperty -Path $ppPath -Name "NoWarningNoElevationOnInstall" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $ppPath -Name "UpdatePromptSettings" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
Set-Service -Name "Spooler" -StartupType Manual -ErrorAction SilentlyContinue
OK "PrintNightmare mitigations applied (Spooler set to Manual)"
Log "PrintNightmare mitigations applied"

# Mimikatz mitigations
Info "Applying Mimikatz / credential theft mitigations..."
$wdigestPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
if (-not (Test-Path $wdigestPath)) { New-Item -Path $wdigestPath -Force | Out-Null }
Set-ItemProperty -Path $wdigestPath -Name "UseLogonCredential" -Value 0 -Type DWord -Force

$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
Set-ItemProperty -Path $lsaPath -Name "RunAsPPL" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $lsaPath -Name "NoLmHash" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $lsaPath -Name "LmCompatibilityLevel" -Value 5 -Type DWord -Force

$lsassAudit = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe"
if (-not (Test-Path $lsassAudit)) { New-Item -Path $lsassAudit -Force | Out-Null }
Set-ItemProperty -Path $lsassAudit -Name "AuditLevel" -Value 8 -Type DWord -Force

# Credential Guard (Win10/2016+)
$dgPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
if (-not (Test-Path $dgPath)) { New-Item -Path $dgPath -Force | Out-Null }
Set-ItemProperty -Path $dgPath -Name "EnableVirtualizationBasedSecurity" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $dgPath -Name "RequirePlatformSecurityFeatures" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
$lsaCfg = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
Set-ItemProperty -Path $lsaCfg -Name "LsaCfgFlags" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

OK "Credential theft mitigations applied (WDigest, LSASS PPL, LM hash, Credential Guard)"
Log "Mimikatz mitigations applied"

# ═══════════════════════════════════════════════════════════════════════════
# 2. WINDOWS DEFENDER
# ═══════════════════════════════════════════════════════════════════════════
Section "Windows Defender"

try {
    $defPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $rtpPath = "$defPath\Real-Time Protection"
    @($defPath, $rtpPath) | ForEach-Object { if (-not (Test-Path $_)) { New-Item -Path $_ -Force | Out-Null } }

    Set-ItemProperty -Path $defPath -Name "DisableAntiSpyware" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $defPath -Name "DisableAntiVirus" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $rtpPath -Name "DisableRealtimeMonitoring" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $rtpPath -Name "DisableBehaviorMonitoring" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $rtpPath -Name "DisableIOAVProtection" -Value 0 -Type DWord -Force
    OK "Defender real-time + cloud protection enabled"

    # Remove exclusions
    try {
        $prefs = Get-MpPreference -ErrorAction SilentlyContinue
        foreach ($e in $prefs.ExclusionExtension) { Remove-MpPreference -ExclusionExtension $e -ErrorAction SilentlyContinue }
        foreach ($e in $prefs.ExclusionPath)      { Remove-MpPreference -ExclusionPath $e -ErrorAction SilentlyContinue }
        foreach ($e in $prefs.ExclusionProcess)   { Remove-MpPreference -ExclusionProcess $e -ErrorAction SilentlyContinue }
        OK "Defender exclusions cleared"
    } catch { Warn "Could not clear Defender exclusions" }

    # ASR Rules (15 rules)
    $asrRules = @(
        "75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84",
        "3B576869-A4EC-4529-8536-B80A7769E899",
        "D4F940AB-401B-4EfC-AADC-AD5F3C50688A",
        "D3E037E1-3EB8-44C8-A917-57927947596D",
        "5BEB7EFE-FD9A-4556-801D-275E5FFC04CC",
        "BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550",
        "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B",
        "D1E49AAC-8F56-4280-B9BA-993A6D77406C",
        "B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4",
        "C1DB55AB-C21A-4637-BB3F-A12568109D35",
        "01443614-CD74-433A-B99E-2ECDC07BFC25",
        "9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2",
        "26190899-1602-49E8-8B27-EB1D0A1CE869",
        "7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C",
        "E6DB77E5-3DF2-4CF1-B95A-636979351E5B"
    )
    foreach ($rule in $asrRules) {
        Add-MpPreference -AttackSurfaceReductionRules_Ids $rule -AttackSurfaceReductionRules_Actions Enabled -ErrorAction SilentlyContinue
    }
    OK "15 ASR rules enabled"

    # Tamper protection
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue
    OK "Tamper protection set"
} catch {
    Warn "Defender configuration partially failed: $_"
}
Log "Windows Defender configured"

# ═══════════════════════════════════════════════════════════════════════════
# 3. FIREWALL: NUKE AND REBUILD (must come BEFORE LOLBin rules)
# ═══════════════════════════════════════════════════════════════════════════
Section "Firewall Nuke-and-Rebuild"

netsh advfirewall set allprofiles state off 2>$null | Out-Null
Info "Firewall temporarily disabled for rule cleanup"

netsh advfirewall firewall delete rule name=all 2>$null | Out-Null
Info "All existing rules deleted"

$inboundRules = @(
    @{Port=80;   Proto="TCP"; Desc="HTTP"},
    @{Port=443;  Proto="TCP"; Desc="HTTPS"},
    @{Port=53;   Proto="TCP"; Desc="DNS-TCP"},
    @{Port=53;   Proto="UDP"; Desc="DNS-UDP"},
    @{Port=21;   Proto="TCP"; Desc="FTP"},
    @{Port=3389; Proto="TCP"; Desc="RDP"},
    @{Port=5985; Proto="TCP"; Desc="WinRM"},
    @{Port=9997; Proto="TCP"; Desc="Splunk-Fwd"}
)

$isDC = Get-IsDC
$isDomainJoined = Get-IsDomainJoined

if ($isDC -or $isDomainJoined) {
    $inboundRules += @(
        @{Port=445;  Proto="TCP"; Desc="SMB"},
        @{Port=88;   Proto="TCP"; Desc="Kerberos"},
        @{Port=88;   Proto="UDP"; Desc="Kerberos-UDP"},
        @{Port=135;  Proto="TCP"; Desc="RPC-Endpoint"},
        @{Port=389;  Proto="TCP"; Desc="LDAP"},
        @{Port=389;  Proto="UDP"; Desc="LDAP-UDP"},
        @{Port=636;  Proto="TCP"; Desc="LDAPS"}
    )
}
if ($isDC) {
    $inboundRules += @(
        @{Port=464;  Proto="TCP"; Desc="Kerberos-PW"},
        @{Port=464;  Proto="UDP"; Desc="Kerberos-PW-UDP"},
        @{Port=3268; Proto="TCP"; Desc="GC"},
        @{Port=3269; Proto="TCP"; Desc="GC-SSL"},
        @{Port=9389; Proto="TCP"; Desc="AD-WebSvc"}
    )
}

# Auto-detect SQL
if ((Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue).Status -eq "Running") {
    $inboundRules += @{Port=1433; Proto="TCP"; Desc="SQL"}
}

foreach ($r in $inboundRules) {
    $name = "CCDC-Allow-$($r.Proto)-$($r.Port)-$($r.Desc)"
    netsh advfirewall firewall add rule name="$name" dir=in action=allow protocol=$($r.Proto) localport=$($r.Port) 2>$null | Out-Null
}

# ICMP
netsh advfirewall firewall add rule name="CCDC-Allow-ICMPv4" dir=in action=allow protocol=icmpv4 2>$null | Out-Null

netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound 2>$null | Out-Null
netsh advfirewall set allprofiles state on 2>$null | Out-Null

# Firewall logging
netsh advfirewall set allprofiles logging filename "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log" 2>$null | Out-Null
netsh advfirewall set allprofiles logging maxfilesize 32767 2>$null | Out-Null
netsh advfirewall set allprofiles logging droppedconnections enable 2>$null | Out-Null
netsh advfirewall set allprofiles logging allowedconnections enable 2>$null | Out-Null

$portList = ($inboundRules | ForEach-Object { "$($_.Port)/$($_.Proto)" } | Sort-Object -Unique) -join ", "
OK "Firewall rebuilt: default deny inbound, allowed: $portList"
Log "Firewall rebuilt with ports: $portList"

# ═══════════════════════════════════════════════════════════════════════════
# 4. LOLBin OUTBOUND BLOCKING (after nuke so rules survive)
# ═══════════════════════════════════════════════════════════════════════════
Section "LOLBin Outbound Blocking"

$lolbins = @(
    "mshta.exe", "regsvr32.exe", "wscript.exe", "cscript.exe",
    "rundll32.exe", "certutil.exe"
)
foreach ($bin in $lolbins) {
    $binPath = "C:\Windows\System32\$bin"
    $ruleName = "CCDC-Block-Outbound-$($bin -replace '\.exe$','')"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program $binPath `
        -Action Block -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
}
OK "Blocked outbound for $($lolbins.Count) LOLBins"
Log "LOLBin outbound rules created"

# ═══════════════════════════════════════════════════════════════════════════
# 5. SERVICE LOCKDOWN
# ═══════════════════════════════════════════════════════════════════════════
Section "Service Lockdown"

$dangerousServices = @("RemoteRegistry","TlntSvr","SNMP","SSDPSRV","upnphost",
                       "WinHttpAutoProxySvc","WMPNetworkSvc","FTPSVC")
foreach ($svc in $dangerousServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}
OK "Disabled dangerous services"

$features = @("TelnetClient","TelnetServer","TFTP","SMB1Protocol")
foreach ($f in $features) {
    dism /online /disable-feature /featurename:$f /NoRestart 2>$null | Out-Null
}
OK "Disabled legacy features"
Log "Service lockdown complete"

# ═══════════════════════════════════════════════════════════════════════════
# 6. SMB HARDENING
# ═══════════════════════════════════════════════════════════════════════════
Section "SMB Hardening"

try {
    Set-SmbServerConfiguration -RequireSecuritySignature $true -Force -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EncryptData $true -Force -ErrorAction SilentlyContinue
    OK "SMB signing required, encryption enabled"
} catch {
    Warn "SMB hardening partially failed"
}
Log "SMB hardened"

# ═══════════════════════════════════════════════════════════════════════════
# 7. UAC ENFORCEMENT
# ═══════════════════════════════════════════════════════════════════════════
Section "UAC Enforcement"

$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $uacPath -Name "EnableLUA" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWord -Force
Set-ItemProperty -Path $uacPath -Name "ConsentPromptBehaviorUser" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $uacPath -Name "PromptOnSecureDesktop" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $uacPath -Name "EnableInstallerDetection" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $uacPath -Name "FilterAdministratorToken" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $uacPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force
OK "UAC enforced with secure settings"
Log "UAC configured"

# ═══════════════════════════════════════════════════════════════════════════
# 8. IFEO CLEANUP (accessibility backdoors)
# ═══════════════════════════════════════════════════════════════════════════
Section "IFEO Backdoor Cleanup"

$ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$backdoorExes = @("sethc.exe","utilman.exe","osk.exe","narrator.exe","magnify.exe")
foreach ($exe in $backdoorExes) {
    $keyPath = "$ifeoBase\$exe"
    if (Test-Path $keyPath) {
        $debugger = (Get-ItemProperty -Path $keyPath -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
        if ($debugger) {
            Remove-ItemProperty -Path $keyPath -Name "Debugger" -Force -ErrorAction SilentlyContinue
            OK "Removed IFEO debugger: $exe (was: $debugger)"
            Log "Removed IFEO backdoor: $exe -> $debugger"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# 9. ANONYMOUS ACCESS & NULL SESSION LOCKDOWN
# ═══════════════════════════════════════════════════════════════════════════
Section "Anonymous Access Lockdown"

Set-ItemProperty -Path $lsaPath -Name "RestrictAnonymousSAM" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $lsaPath -Name "RestrictAnonymous" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $lsaPath -Name "EveryoneIncludesAnonymous" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $lsaPath -Name "ForceGuest" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

$lanmanPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters"
Set-ItemProperty -Path $lanmanPath -Name "RestrictNullSessAccess" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $lanmanPath -Name "NullSessionPipes" -Value "" -Type MultiString -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $lanmanPath -Name "NullSessionShares" -Value "" -Type MultiString -Force -ErrorAction SilentlyContinue

OK "Anonymous access and null sessions disabled"
Log "Anonymous access locked down"

# ═══════════════════════════════════════════════════════════════════════════
# 10. DISABLE LLMNR / NetBIOS
# ═══════════════════════════════════════════════════════════════════════════
Section "LLMNR & NetBIOS"

$dnsClientPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $dnsClientPath)) { New-Item -Path $dnsClientPath -Force | Out-Null }
Set-ItemProperty -Path $dnsClientPath -Name "EnableMulticast" -Value 0 -Type DWord -Force

Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue | ForEach-Object {
    Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions=[uint32]2} -ErrorAction SilentlyContinue | Out-Null
}
OK "LLMNR and NetBIOS disabled"
Log "LLMNR/NetBIOS disabled"

# ═══════════════════════════════════════════════════════════════════════════
# 11. PASSWORD ROTATION (local users)
# ═══════════════════════════════════════════════════════════════════════════
Section "Local Password Rotation"

$pwFile = "$LogDir\local-passwords-$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%"
function New-RandomPassword {
    $pw = -join (1..20 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $pw
}

$localUsers = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled }
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]

foreach ($u in $localUsers) {
    if ($u.Name -eq $currentUser) {
        Info "Skipping current user: $($u.Name)"
        continue
    }
    $pw = New-RandomPassword
    try {
        $securePw = ConvertTo-SecureString -String $pw -AsPlainText -Force
        Set-LocalUser -Name $u.Name -Password $securePw -ErrorAction Stop
        "$($u.Name):$pw" | Out-File $pwFile -Append -Encoding UTF8
        OK "Rotated password: $($u.Name)"
    } catch {
        Warn "Failed to rotate: $($u.Name)"
    }
}

# Disable Guest
net user Guest /active:no 2>$null | Out-Null
OK "Guest account disabled"
if (Test-Path $pwFile) {
    OK "Passwords saved to $pwFile"
} else {
    Info "No other enabled local accounts to rotate"
}
Log "Local passwords rotated"

# ═══════════════════════════════════════════════════════════════════════════
# 12. AUDITING & POWERSHELL LOGGING
# ═══════════════════════════════════════════════════════════════════════════
Section "Auditing & Logging"

# Command line auditing
$auditPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
if (-not (Test-Path $auditPath)) { New-Item -Path $auditPath -Force | Out-Null }
Set-ItemProperty -Path $auditPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord -Force

# Audit subcategories
$auditCats = @(
    "Security State Change","Security System Extension","System Integrity",
    "Logon","Logoff","Account Lockout","Special Logon","Other Logon/Logoff Events",
    "Group Membership","User / Device Claims",
    "File System","Registry","SAM","Kernel Object","Handle Manipulation",
    "File Share","Other Object Access Events","Removable Storage",
    "Sensitive Privilege Use","Non Sensitive Privilege Use",
    "Process Creation","Process Termination","DPAPI Activity","Plug and Play Events",
    "Audit Policy Change","Authentication Policy Change","Authorization Policy Change",
    "MPSSVC Rule-Level Policy Change",
    "User Account Management","Computer Account Management","Security Group Management",
    "Other Account Management Events",
    "Directory Service Access","Directory Service Changes",
    "Credential Validation","Kerberos Service Ticket Operations","Kerberos Authentication Service"
)
$ok = 0
foreach ($cat in $auditCats) {
    $r = auditpol /set /subcategory:"$cat" /success:enable /failure:enable 2>&1
    if ($LASTEXITCODE -eq 0) { $ok++ }
}
OK "Enabled $ok audit subcategories"

# PowerShell logging
$sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $sbPath)) { New-Item -Path $sbPath -Force | Out-Null }
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockInvocationLogging" -Value 1 -Type DWord -Force

$mlPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
if (-not (Test-Path $mlPath)) { New-Item -Path $mlPath -Force | Out-Null }
Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord -Force
$mlMod = "$mlPath\ModuleNames"
if (-not (Test-Path $mlMod)) { New-Item -Path $mlMod -Force | Out-Null }
Set-ItemProperty -Path $mlMod -Name "*" -Value "*" -Type String -Force

$transPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"
if (-not (Test-Path $transPath)) { New-Item -Path $transPath -Force | Out-Null }
Set-ItemProperty -Path $transPath -Name "EnableTranscripting" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $transPath -Name "EnableInvocationHeader" -Value 1 -Type DWord -Force
$transDir = "C:\ccdc26\logs\powershell"
if (-not (Test-Path $transDir)) { New-Item -ItemType Directory -Path $transDir -Force | Out-Null }
Set-ItemProperty -Path $transPath -Name "OutputDirectory" -Value $transDir -Type String -Force
OK "PowerShell script block + module + transcription logging enabled"
Log "Auditing and PS logging configured"

# ═══════════════════════════════════════════════════════════════════════════
# 13. MISC HARDENING
# ═══════════════════════════════════════════════════════════════════════════
Section "Miscellaneous Hardening"

# AutoRun
$explorerPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $explorerPath)) { New-Item -Path $explorerPath -Force | Out-Null }
Set-ItemProperty -Path $explorerPath -Name "NoAutorun" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $explorerPath -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord -Force
OK "AutoRun disabled"

# DEP
$depPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $depPath)) { New-Item -Path $depPath -Force | Out-Null }
Set-ItemProperty -Path $depPath -Name "NoDataExecutionPrevention" -Value 0 -Type DWord -Force
OK "DEP enforced"

# Remote Desktop NLA
$rdpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $rdpPath -Name "UserAuthentication" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
OK "RDP NLA enforced"

Log "Misc hardening complete"

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  BLITZ COMPLETE in $elapsed seconds" -ForegroundColor Green
if (Test-Path $pwFile) { Write-Host "  Passwords: $pwFile" -ForegroundColor Green }
Write-Host "  Logs:      $LogDir\blitz.log" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next: run 02-ad.ps1 on DCs, 04-splunk.ps1 for monitoring" -ForegroundColor Yellow
Log "Blitz completed in ${elapsed}s"

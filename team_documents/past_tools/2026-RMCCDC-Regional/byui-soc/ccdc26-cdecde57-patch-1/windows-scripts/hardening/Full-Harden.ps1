# CCDC26 Windows Toolkit - Full System Hardening
# Comprehensive Windows hardening script (hybrid of BYU-CCDC + ccdc26 style)
# Run as Administrator

#Requires -RunAsAdministrator

#=============================================================================
# INITIALIZATION
#=============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\lib\common.ps1"
. "$ScriptDir\lib\auditing.ps1"

Require-Administrator
$OSInfo = Get-OSInfo

Header "CCDC26 Windows Full System Hardening"
Write-Host "OS: $($OSInfo.Caption)" -ForegroundColor Gray
Write-Host "Computer: $($OSInfo.ComputerName)" -ForegroundColor Gray
Write-Host "Domain Joined: $($OSInfo.IsDomainJoined)" -ForegroundColor Gray
Write-Host "Is DC: $($OSInfo.IsDomainController)" -ForegroundColor Gray
Write-Host ""

#=============================================================================
# CVE PATCHES AND VULNERABILITY MITIGATIONS
#=============================================================================
function Install-EternalBluePatch {
    Header "Installing EternalBlue Patch (MS17-010)"
    
    $osVersion = $OSInfo.Caption
    
    # Patch URLs by OS version
    $patchURLs = @{
        "Vista"    = "https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2017/02/windows6.0-kb4012598-x64_6a186ba2b2b98b2144b50f88e10f9a2d14e08c4b.msu"
        "7"        = "https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2017/02/windows6.1-kb4012212-x64_2decefaa02e2058dcd965702509a992d8c4e92b3.msu"
        "8"        = "https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2017/02/windows8-rt-kb4012598-x64_f05841d2e94197c2dca4457f1b895e8f632b7f8e.msu"
        "2008"     = "https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2017/02/windows6.0-kb4012598-x64_6a186ba2b2b98b2144b50f88e10f9a2d14e08c4b.msu"
        "2008 R2"  = "https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2017/02/windows6.1-kb4012212-x64_2decefaa02e2058dcd965702509a992d8c4e92b3.msu"
        "2012"     = "https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2017/02/windows8-rt-kb4012214-x64_b14951d29cb4fd880948f5204d54721e64c9942b.msu"
        "2012 R2"  = "https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2017/02/windows8.1-kb4012213-x64_5b24b9ca5a123a844ed793e0f2be974148520349.msu"
    }
    
    # Determine patch URL
    $patchURL = $null
    foreach ($key in $patchURLs.Keys) {
        if ($osVersion -match $key) {
            $patchURL = $patchURLs[$key]
            break
        }
    }
    
    if ($patchURL) {
        $patchPath = "$env:TEMP\eternalblue_patch.msu"
        
        try {
            Info "Downloading patch for $osVersion..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($patchURL, $patchPath)
            
            Info "Installing patch..."
            Start-Process -Wait -FilePath "wusa.exe" -ArgumentList "$patchPath /quiet /norestart"
            
            Remove-Item -Path $patchPath -Force -ErrorAction SilentlyContinue
            Success "EternalBlue patch installed"
            Log-Action "Installed EternalBlue patch (MS17-010)"
        }
        catch {
            Warn "Failed to install EternalBlue patch: $_"
            Warn "Windows 10/Server 2016+ should already be patched via Windows Update"
        }
    }
    else {
        Info "OS version likely already patched or patch not available"
    }
}

function Patch-Mimikatz {
    Header "Applying Mimikatz Mitigations"
    
    # Disable WDigest credential caching
    $wdigestPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
    if (-not (Test-Path $wdigestPath)) {
        New-Item -Path $wdigestPath -Force | Out-Null
    }
    Set-ItemProperty -Path $wdigestPath -Name "UseLogonCredential" -Value 0 -Type DWord -Force
    Success "WDigest credential caching disabled"
    
    # Enable LSASS protection
    $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    Set-ItemProperty -Path $lsaPath -Name "RunAsPPL" -Value 1 -Type DWord -Force
    Success "LSASS protection (PPL) enabled"
    
    # Enable LSASS auditing
    $lsassAuditPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe"
    if (-not (Test-Path $lsassAuditPath)) {
        New-Item -Path $lsassAuditPath -Force | Out-Null
    }
    Set-ItemProperty -Path $lsassAuditPath -Name "AuditLevel" -Value 8 -Type DWord -Force
    Success "LSASS auditing enabled"
    
    # Disable storage of LM hash
    Set-ItemProperty -Path $lsaPath -Name "NoLmHash" -Value 1 -Type DWord -Force
    Success "LM hash storage disabled"
    
    # Set LmCompatibilityLevel to NTLMv2 only
    Set-ItemProperty -Path $lsaPath -Name "LmCompatibilityLevel" -Value 5 -Type DWord -Force
    Success "LM compatibility set to NTLMv2 only"
    
    # Enable remote UAC for local accounts
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-ItemProperty -Path $uacPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force
    Success "Remote UAC enabled for local accounts"
    
    Log-Action "Applied Mimikatz mitigations"
}

function Patch-PrintNightmare {
    param(
        [switch]$DisableSpooler = $false  # Don't disable by default - may break printing injects!
    )
    
    Header "Applying PrintNightmare Mitigations (CVE-2021-34527)"
    
    # CCDC NOTE: Print Spooler may be needed for printing-related injects!
    # Only disable if explicitly requested or confirmed
    if ($DisableSpooler) {
        Stop-AndDisable-Service "Spooler"
        Success "Print Spooler disabled"
    } else {
        Warn "Print Spooler left ENABLED (may be needed for injects)"
        Warn "To disable: Patch-PrintNightmare -DisableSpooler"
        Info "Applying registry mitigations only..."
    }
    
    # Registry mitigations (these protect without disabling printing)
    $printerPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers"
    if (-not (Test-Path $printerPath)) {
        New-Item -Path $printerPath -Force | Out-Null
    }
    Set-ItemProperty -Path $printerPath -Name "RegisterSpoolerRemoteRpcEndPoint" -Value 2 -Type DWord -Force
    
    $pointAndPrintPath = "$printerPath\PointAndPrint"
    if (Test-Path $pointAndPrintPath) {
        Remove-ItemProperty -Path $pointAndPrintPath -Name "NoWarningNoElevationOnInstall" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $pointAndPrintPath -Name "UpdatePromptSettings" -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $pointAndPrintPath)) {
        New-Item -Path $pointAndPrintPath -Force | Out-Null
    }
    Set-ItemProperty -Path $pointAndPrintPath -Name "RestrictDriverInstallationToAdministrators" -Value 1 -Type DWord -Force
    
    Success "PrintNightmare registry mitigations applied"
    Log-Action "Applied PrintNightmare mitigations (CVE-2021-34527) - Spooler: $(if($DisableSpooler){'Disabled'}else{'Enabled'})"
}

function Upgrade-SMB {
    Header "Upgrading SMB Security"
    
    try {
        $smbConfig = Get-SmbServerConfiguration
        
        # Disable SMBv1
        if ($smbConfig.EnableSMB1Protocol) {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
            Success "SMBv1 disabled"
        }
        else {
            Info "SMBv1 already disabled"
        }
        
        # Enable SMBv2/v3
        if (-not $smbConfig.EnableSMB2Protocol) {
            Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
            Success "SMBv2/v3 enabled"
        }
        
        # Enable SMB signing
        Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
        Success "SMB signing required"
        
        # Enable SMB encryption (Server 2012 R2+)
        try {
            Set-SmbServerConfiguration -EncryptData $true -Force
            Success "SMB encryption enabled"
        }
        catch {
            Warn "SMB encryption not supported on this OS version"
        }
    }
    catch {
        # Fallback for older systems
        Info "Using DISM to disable SMBv1..."
        dism /online /disable-feature /featurename:SMB1Protocol /NoRestart 2>$null
    }
    
    Log-Action "Upgraded SMB security settings"
}

#=============================================================================
# WINDOWS DEFENDER
#=============================================================================
function Configure-WindowsDefender {
    Header "Configuring Windows Defender"
    
    # Start Defender service
    Start-AndEnable-Service "WinDefend"
    
    # Registry settings
    $defenderPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $rtpPath = "$defenderPath\Real-Time Protection"
    $scanPath = "$defenderPath\Scan"
    $spynetPath = "$defenderPath\Spynet"
    
    # Ensure paths exist
    @($defenderPath, $rtpPath, $scanPath, $spynetPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -Force | Out-Null
        }
    }
    
    # Enable Defender
    Set-ItemProperty -Path $defenderPath -Name "DisableAntiSpyware" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $defenderPath -Name "DisableAntiVirus" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $defenderPath -Name "ServiceKeepAlive" -Value 1 -Type DWord -Force
    
    # Real-time protection
    Set-ItemProperty -Path $rtpPath -Name "DisableRealtimeMonitoring" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $rtpPath -Name "DisableBehaviorMonitoring" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $rtpPath -Name "DisableIOAVProtection" -Value 0 -Type DWord -Force
    
    # Scan settings
    Set-ItemProperty -Path $scanPath -Name "CheckForSignaturesBeforeRunningScan" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $scanPath -Name "DisableHeuristics" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $scanPath -Name "DisableArchiveScanning" -Value 0 -Type DWord -Force
    
    Success "Windows Defender registry settings configured"
    
    # Attack Surface Reduction rules
    try {
        $asrRules = @{
            "75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84" = "Block Office apps from injecting code"
            "3B576869-A4EC-4529-8536-B80A7769E899" = "Block Office apps from creating executable content"
            "D4F940AB-401B-4EfC-AADC-AD5F3C50688A" = "Block all Office apps from creating child processes"
            "D3E037E1-3EB8-44C8-A917-57927947596D" = "Block JavaScript/VBScript from launching executables"
            "5BEB7EFE-FD9A-4556-801D-275E5FFC04CC" = "Block execution of potentially obfuscated scripts"
            "BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550" = "Block executable content from email/webmail"
            "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B" = "Block Win32 API calls from Office macro"
            "D1E49AAC-8F56-4280-B9BA-993A6D77406C" = "Block process creations from PSExec/WMI"
            "B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4" = "Block untrusted/unsigned processes from USB"
            "C1DB55AB-C21A-4637-BB3F-A12568109D35" = "Advanced ransomware protection"
            "01443614-CD74-433A-B99E-2ECDC07BFC25" = "Block executables unless prevalence/age/trusted list"
            "9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2" = "Block credential stealing from LSASS"
            "26190899-1602-49E8-8B27-EB1D0A1CE869" = "Block Office communication apps from creating child processes"
            "7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C" = "Block Adobe Reader from creating child processes"
            "E6DB77E5-3DF2-4CF1-B95A-636979351E5B" = "Block persistence through WMI event subscription"
        }
        
        foreach ($rule in $asrRules.GetEnumerator()) {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $rule.Key -AttackSurfaceReductionRules_Actions Enabled -ErrorAction SilentlyContinue
        }
        Success "Attack Surface Reduction rules enabled ($($asrRules.Count) rules)"
    }
    catch {
        Warn "ASR rules not supported on this OS version (requires Windows 10 1709+)"
    }
    
    # Remove exclusions
    try {
        ForEach ($ExcludedExt in (Get-MpPreference).ExclusionExtension) {
            Remove-MpPreference -ExclusionExtension $ExcludedExt -ErrorAction SilentlyContinue
        }
        ForEach ($ExcludedPath in (Get-MpPreference).ExclusionPath) {
            Remove-MpPreference -ExclusionPath $ExcludedPath -ErrorAction SilentlyContinue
        }
        ForEach ($ExcludedProc in (Get-MpPreference).ExclusionProcess) {
            Remove-MpPreference -ExclusionProcess $ExcludedProc -ErrorAction SilentlyContinue
        }
        Success "Defender exclusions removed"
    }
    catch {
        Warn "Could not remove Defender exclusions"
    }
    
    # Enable tamper protection
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" -Name "TamperProtection" -Value 5 -Type DWord -Force -ErrorAction Stop
        Success "Tamper protection enabled"
    }
    catch {
        Info "Tamper protection may already be enabled or requires manual configuration"
    }
    
    Log-Action "Configured Windows Defender"
}

#=============================================================================
# BACKDOOR REMOVAL
#=============================================================================
function Remove-AccessibilityBackdoors {
    Header "Removing Accessibility Backdoors"
    
    $backdoorFiles = @(
        "C:\Windows\System32\sethc.exe",      # Sticky keys
        "C:\Windows\System32\Utilman.exe",    # Utility manager
        "C:\Windows\System32\osk.exe",        # On-screen keyboard
        "C:\Windows\System32\Narrator.exe",   # Narrator
        "C:\Windows\System32\Magnify.exe"     # Magnifier
    )
    
    foreach ($file in $backdoorFiles) {
        if (Test-Path $file) {
            try {
                # Take ownership
                takeown.exe /f $file 2>$null | Out-Null
                icacls.exe $file /grant administrators:F 2>$null | Out-Null
                
                # Remove the file
                Remove-Item -Path $file -Force -ErrorAction Stop
                Success "Removed: $file"
                Log-Action "Removed backdoor file: $file"
            }
            catch {
                Warn "Could not remove $file (may require reboot)"
            }
        }
    }
    
    # Also remove Image File Execution Options backdoors
    $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $backdoorKeys = @("sethc.exe", "utilman.exe", "osk.exe", "narrator.exe", "magnify.exe")
    
    foreach ($key in $backdoorKeys) {
        $keyPath = "$ifeoPath\$key"
        if (Test-Path $keyPath) {
            Remove-Item -Path $keyPath -Force -Recurse -ErrorAction SilentlyContinue
            Success "Removed IFEO key: $key"
        }
    }
}

function Audit-ScheduledTasks {
    Header "Auditing Scheduled Tasks"
    
    $tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' }
    
    Write-Host "`nActive scheduled tasks:" -ForegroundColor Yellow
    $suspiciousTasks = @()
    
    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
        $actions = $task.Actions | ForEach-Object { $_.Execute }
        
        # Flag suspicious tasks
        $suspicious = $false
        foreach ($action in $actions) {
            if ($action -match "powershell|cmd|wscript|cscript|mshta|regsvr32|rundll32") {
                $suspicious = $true
                break
            }
        }
        
        if ($suspicious) {
            $suspiciousTasks += $task
            Write-Host "  [!] $($task.TaskPath)$($task.TaskName)" -ForegroundColor Red
            Write-Host "      Action: $($actions -join ', ')" -ForegroundColor Gray
            Log-Finding "Suspicious scheduled task: $($task.TaskPath)$($task.TaskName)"
        }
    }
    
    if ($suspiciousTasks.Count -gt 0) {
        Write-Host ""
        $delete = Prompt-YesNo "Delete suspicious scheduled tasks?"
        if ($delete) {
            foreach ($task in $suspiciousTasks) {
                try {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
                    Success "Deleted task: $($task.TaskName)"
                    Log-Action "Deleted scheduled task: $($task.TaskPath)$($task.TaskName)"
                }
                catch {
                    Warn "Could not delete task: $($task.TaskName)"
                }
            }
        }
    }
    else {
        Success "No obviously suspicious scheduled tasks found"
    }
}

#=============================================================================
# SERVICE LOCKDOWN
#=============================================================================
function Disable-DangerousServices {
    Header "Disabling Dangerous Services"
    
    $dangerousServices = @(
        @{Name="RemoteRegistry"; Desc="Remote Registry"},
        @{Name="Spooler"; Desc="Print Spooler (PrintNightmare)"},
        @{Name="TlntSvr"; Desc="Telnet Server"},
        @{Name="SNMP"; Desc="SNMP Service"},
        @{Name="SSDPSRV"; Desc="SSDP Discovery"},
        @{Name="upnphost"; Desc="UPnP Device Host"},
        @{Name="WinHttpAutoProxySvc"; Desc="WinHTTP Web Proxy Auto-Discovery"},
        @{Name="WMPNetworkSvc"; Desc="Windows Media Player Network Sharing"}
    )
    
    foreach ($svc in $dangerousServices) {
        Stop-AndDisable-Service $svc.Name
    }
    
    # Disable DISM features
    $features = @("TelnetClient", "TelnetServer", "TFTP", "SMB1Protocol")
    foreach ($feature in $features) {
        dism /online /disable-feature /featurename:$feature /NoRestart 2>$null | Out-Null
    }
    Info "Disabled legacy features (Telnet, TFTP, SMB1)"
    
    Log-Action "Disabled dangerous services and features"
}

#=============================================================================
# USER MANAGEMENT
#=============================================================================
function Audit-LocalUsers {
    Header "Auditing Local Users"
    
    Write-Host "`n=== Enabled Users ===" -ForegroundColor Green
    Get-LocalUser | Where-Object { $_.Enabled } | ForEach-Object {
        $groups = Get-LocalGroup | Where-Object { 
            $_.SID -ne $null -and (Get-LocalGroupMember -Group $_ -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$($_.Name)*" })
        } | Select-Object -ExpandProperty Name
        Write-Host "  $($_.Name)" -ForegroundColor White
        Write-Host "    Groups: $(($groups -join ', '))" -ForegroundColor Gray
    }
    
    Write-Host "`n=== Disabled Users ===" -ForegroundColor Red
    Get-LocalUser | Where-Object { -not $_.Enabled } | ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor Gray
    }
    
    Write-Host "`n=== Administrators ===" -ForegroundColor Yellow
    Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor White
    }
}

function Disable-GuestAccount {
    Header "Disabling Guest Account"
    
    try {
        net user Guest /active:no 2>$null | Out-Null
        Success "Guest account disabled"
        Log-Action "Disabled Guest account"
    }
    catch {
        Warn "Could not disable Guest account"
    }
}

#=============================================================================
# UAC CONFIGURATION
#=============================================================================
function Configure-UAC {
    Header "Configuring UAC"
    
    $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    
    # Enable UAC
    Set-ItemProperty -Path $uacPath -Name "EnableLUA" -Value 1 -Type DWord -Force
    
    # Admin approval mode
    Set-ItemProperty -Path $uacPath -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWord -Force
    
    # User behavior (no elevation)
    Set-ItemProperty -Path $uacPath -Name "ConsentPromptBehaviorUser" -Value 0 -Type DWord -Force
    
    # Prompt on secure desktop
    Set-ItemProperty -Path $uacPath -Name "PromptOnSecureDesktop" -Value 1 -Type DWord -Force
    
    # Installer detection
    Set-ItemProperty -Path $uacPath -Name "EnableInstallerDetection" -Value 1 -Type DWord -Force
    
    # Filter admin token
    Set-ItemProperty -Path $uacPath -Name "FilterAdministratorToken" -Value 1 -Type DWord -Force
    
    Success "UAC configured with secure settings"
    Log-Action "Configured UAC settings"
}

#=============================================================================
# FIREWALL CONFIGURATION
#=============================================================================
function Detect-WindowsServices {
    # Auto-detect running services that need firewall rules
    $detectedPorts = @(3389)  # Always allow RDP for remote management
    
    # Check for IIS/Web Server (SCORED)
    if ((Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue).Status -eq "Running") {
        $detectedPorts += 80, 443
        Info "Detected: IIS Web Server (HTTP/HTTPS)"
    }
    
    # Check for DNS Server (SCORED)
    if ((Get-Service -Name "DNS" -ErrorAction SilentlyContinue).Status -eq "Running") {
        $detectedPorts += 53
        Info "Detected: DNS Server"
    }
    
    # Check for FTP (may be scored)
    if ((Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue).Status -eq "Running") {
        $detectedPorts += 21, 20
        Info "Detected: FTP Server"
    }
    
    # Check for Active Directory
    if ($OSInfo.IsDomainController) {
        $detectedPorts += 53, 88, 135, 389, 445, 464, 636, 3268, 3269
        Info "Detected: Domain Controller (AD ports)"
    }
    
    # Check for SQL Server
    if ((Get-Service -Name "MSSQLSERVER" -ErrorAction SilentlyContinue).Status -eq "Running") {
        $detectedPorts += 1433
        Info "Detected: SQL Server"
    }
    
    # Check for Splunk Forwarder
    if ((Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue).Status -eq "Running") {
        Info "Detected: Splunk Forwarder (outbound only, no inbound needed)"
    }
    
    return $detectedPorts | Sort-Object -Unique
}

function Configure-Firewall {
    Header "Configuring Windows Firewall"
    
    # Enable firewall for all profiles
    netsh advfirewall set allprofiles state on
    Success "Firewall enabled for all profiles"
    
    # Default deny inbound
    netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound
    Info "Default policy: block inbound, allow outbound"
    
    # Auto-detect services
    Write-Host "`nAuto-detecting running services..." -ForegroundColor Yellow
    $detectedPorts = Detect-WindowsServices
    
    Write-Host "`nDetected ports to allow: $($detectedPorts -join ', ')" -ForegroundColor Cyan
    Write-Host "Common CCDC ports: 22 (SSH), 53 (DNS), 80 (HTTP), 443 (HTTPS), 3389 (RDP)" -ForegroundColor Gray
    Write-Host "AD ports: 88, 135, 389, 445, 636, 3268, 3269" -ForegroundColor Gray
    
    $portInput = Read-Host "Enter additional ports (comma-separated), 'auto' for detected only, or 'default' for RDP/HTTP/HTTPS/DNS"
    
    if ($portInput -eq 'auto') {
        $ports = $detectedPorts
    }
    elseif ($portInput -eq 'default') {
        $ports = @(53, 80, 443, 3389)
    }
    elseif (-not [string]::IsNullOrEmpty($portInput)) {
        $additionalPorts = $portInput -split ',' | ForEach-Object { [int]$_.Trim() }
        $ports = ($detectedPorts + $additionalPorts) | Sort-Object -Unique
    }
    else {
        $ports = $detectedPorts
    }
    
    foreach ($port in $ports) {
        $desc = Get-PortDescription $port
        Add-FirewallPort -Port $port -Protocol "TCP" -Direction "Inbound" -Name "CCDC - TCP Inbound $desc ($port)"
    }
    
    # Enable firewall logging
    Enable-FirewallLogging
    
    Log-Action "Configured firewall with ports: $($ports -join ', ')"
}

#=============================================================================
# MISCELLANEOUS HARDENING
#=============================================================================
function Disable-AutoRun {
    Header "Disabling AutoRun"
    
    $explorerPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (-not (Test-Path $explorerPath)) {
        New-Item -Path $explorerPath -Force | Out-Null
    }
    
    Set-ItemProperty -Path $explorerPath -Name "NoAutorun" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $explorerPath -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord -Force
    
    Success "AutoRun disabled"
    Log-Action "Disabled AutoRun"
}

function Enable-DEP {
    Header "Ensuring DEP is Enabled"
    
    $explorerPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $explorerPath)) {
        New-Item -Path $explorerPath -Force | Out-Null
    }
    Set-ItemProperty -Path $explorerPath -Name "NoDataExecutionPrevention" -Value 0 -Type DWord -Force
    
    $systemPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $systemPath)) {
        New-Item -Path $systemPath -Force | Out-Null
    }
    Set-ItemProperty -Path $systemPath -Name "DisableHHDEP" -Value 0 -Type DWord -Force
    
    Success "DEP enabled"
    Log-Action "Ensured DEP is enabled"
}

function Disable-LLMNRNetBIOS {
    Header "Disabling LLMNR and NetBIOS"
    
    # Disable LLMNR
    $dnsClientPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $dnsClientPath)) {
        New-Item -Path $dnsClientPath -Force | Out-Null
    }
    Set-ItemProperty -Path $dnsClientPath -Name "EnableMulticast" -Value 0 -Type DWord -Force
    Success "LLMNR disabled"
    
    # Disable NetBIOS over TCP/IP on all adapters
    $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
    foreach ($adapter in $adapters) {
        $adapter.SetTcpipNetbios(2) | Out-Null  # 2 = Disable
    }
    Success "NetBIOS over TCP/IP disabled"
    
    Log-Action "Disabled LLMNR and NetBIOS"
}

#=============================================================================
# QUICK HARDEN (ALL FUNCTIONS)
#=============================================================================
function Invoke-QuickHarden {
    Header "QUICK HARDEN MODE"
    Write-Host "Running all hardening functions with CCDC-safe defaults..." -ForegroundColor Yellow
    Write-Host ""
    
    $startTime = Get-Date
    
    # CVE patches (PrintNightmare does NOT disable spooler - may need for injects)
    Patch-Mimikatz
    Patch-PrintNightmare  # Spooler stays enabled, only registry mitigations applied
    Upgrade-SMB
    Install-EternalBluePatch
    
    # Security configuration
    Configure-WindowsDefender
    Configure-UAC
    Disable-AutoRun
    Enable-DEP
    Disable-LLMNRNetBIOS
    
    # Service hardening
    Disable-DangerousServices
    Disable-GuestAccount
    
    # Backdoor removal
    Remove-AccessibilityBackdoors
    
    # Auditing
    Enable-AllAuditing
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Header "Quick Harden Complete"
    Success "Completed in $([math]::Round($duration, 1)) seconds"
    
    Write-Host ""
    Write-Host "IMPORTANT POST-HARDENING STEPS:" -ForegroundColor Yellow
    Write-Host "1. Configure firewall ports for your services" -ForegroundColor Gray
    Write-Host "2. Change all user passwords" -ForegroundColor Gray
    Write-Host "3. Review scheduled tasks" -ForegroundColor Gray
    Write-Host "4. If DC, run AD-Harden.ps1" -ForegroundColor Gray
    Write-Host "5. Deploy Splunk forwarder" -ForegroundColor Gray
    Write-Host ""
    
    Log-Action "Quick harden completed in $duration seconds"
}

#=============================================================================
# MAIN MENU
#=============================================================================
function Show-Menu {
    Write-Host ""
    Write-Host "Windows Hardening Options:" -ForegroundColor Cyan
    Write-Host "1)  Quick Harden (run all with defaults)"
    Write-Host "2)  CVE Patches (Mimikatz, PrintNightmare, SMB, EternalBlue)"
    Write-Host "3)  Configure Windows Defender"
    Write-Host "4)  Configure UAC"
    Write-Host "5)  Configure Firewall"
    Write-Host "6)  Disable Dangerous Services"
    Write-Host "7)  Remove Accessibility Backdoors"
    Write-Host "8)  Audit Scheduled Tasks"
    Write-Host "9)  Audit Local Users"
    Write-Host "10) Enable Advanced Auditing"
    Write-Host "11) Disable LLMNR/NetBIOS"
    Write-Host ""
    
    $choice = Read-Host "Select option [1-11]"
    
    switch ($choice) {
        "1"  { Invoke-QuickHarden }
        "2"  { Patch-Mimikatz; Patch-PrintNightmare; Upgrade-SMB; Install-EternalBluePatch }
        "3"  { Configure-WindowsDefender }
        "4"  { Configure-UAC }
        "5"  { Configure-Firewall }
        "6"  { Disable-DangerousServices }
        "7"  { Remove-AccessibilityBackdoors }
        "8"  { Audit-ScheduledTasks }
        "9"  { Audit-LocalUsers }
        "10" { Enable-AllAuditing }
        "11" { Disable-LLMNRNetBIOS }
        default { Error "Invalid option" }
    }
}

# Main entry point
if ($args -contains "-q" -or $args -contains "--quick") {
    Invoke-QuickHarden
}
else {
    Show-Menu
}

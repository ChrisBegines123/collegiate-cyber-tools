# CCDC26 Windows Toolkit - Advanced Auditing Configuration
# Enables comprehensive Windows auditing for security monitoring

#=============================================================================
# AUDIT POLICY CONFIGURATION
#=============================================================================
function Enable-AdvancedAuditing {
    <#
    .SYNOPSIS
        Enables comprehensive Windows audit policies.
    
    .DESCRIPTION
        Configures all audit subcategories for both success and failure events.
        This enables maximum visibility into system activity for security monitoring.
    #>
    
    Write-Host "`n=== Enabling Advanced Auditing ===" -ForegroundColor Cyan
    
    # All audit subcategories to enable
    $auditCategories = @(
        # System
        "Security State Change",
        "Security System Extension",
        "System Integrity",
        "IPsec Driver",
        "Other System Events",
        
        # Logon/Logoff
        "Logon",
        "Logoff",
        "Account Lockout",
        "IPsec Main Mode",
        "IPsec Quick Mode",
        "IPsec Extended Mode",
        "Special Logon",
        "Other Logon/Logoff Events",
        "Network Policy Server",
        "User / Device Claims",
        "Group Membership",
        
        # Object Access
        "File System",
        "Registry",
        "Kernel Object",
        "SAM",
        "Certification Services",
        "Application Generated",
        "Handle Manipulation",
        "File Share",
        "Filtering Platform Packet Drop",
        "Filtering Platform Connection",
        "Other Object Access Events",
        "Detailed File Share",
        "Removable Storage",
        "Central Policy Staging",
        
        # Privilege Use
        "Sensitive Privilege Use",
        "Non Sensitive Privilege Use",
        "Other Privilege Use Events",
        
        # Detailed Tracking
        "Process Creation",
        "Process Termination",
        "DPAPI Activity",
        "RPC Events",
        "Plug and Play Events",
        "Token Right Adjusted Events",
        
        # Policy Change
        "Audit Policy Change",
        "Authentication Policy Change",
        "Authorization Policy Change",
        "MPSSVC Rule-Level Policy Change",
        "Filtering Platform Policy Change",
        "Other Policy Change Events",
        
        # Account Management
        "User Account Management",
        "Computer Account Management",
        "Security Group Management",
        "Distribution Group Management",
        "Application Group Management",
        "Other Account Management Events",
        
        # DS Access
        "Directory Service Access",
        "Directory Service Changes",
        "Directory Service Replication",
        "Detailed Directory Service Replication",
        
        # Account Logon
        "Credential Validation",
        "Kerberos Service Ticket Operations",
        "Other Account Logon Events",
        "Kerberos Authentication Service"
    )
    
    $successCount = 0
    $failCount = 0
    
    foreach ($category in $auditCategories) {
        try {
            $result = auditpol /set /subcategory:"$category" /success:enable /failure:enable 2>&1
            if ($LASTEXITCODE -eq 0) {
                $successCount++
            }
            else {
                $failCount++
            }
        }
        catch {
            $failCount++
        }
    }
    
    Write-Host "[OK] Enabled $successCount audit categories" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "[WARN] Failed to enable $failCount categories (may not exist on this OS)" -ForegroundColor Yellow
    }
}

#=============================================================================
# REGISTRY-BASED AUDITING
#=============================================================================
function Enable-RegistryAuditing {
    <#
    .SYNOPSIS
        Enables audit logging via registry settings.
    #>
    
    Write-Host "`n=== Enabling Registry-Based Auditing ===" -ForegroundColor Cyan
    
    $auditSettings = @{
        "AuditLogonEvents" = 3      # Success and Failure
        "AuditAccountLogon" = 3
        "AuditAccountManage" = 3
        "AuditDSAccess" = 3
        "AuditObjectAccess" = 3
        "AuditPolicyChange" = 3
        "AuditPrivilegeUse" = 3
        "AuditProcessTracking" = 3
        "AuditSystemEvents" = 3
    }
    
    $lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    
    foreach ($setting in $auditSettings.GetEnumerator()) {
        try {
            Set-ItemProperty -Path $lsaPath -Name $setting.Key -Value $setting.Value -Type DWord -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Silently continue if setting doesn't exist
        }
    }
    
    Write-Host "[OK] Registry audit settings configured" -ForegroundColor Green
}

#=============================================================================
# COMMAND LINE AUDITING
#=============================================================================
function Enable-CommandLineAuditing {
    <#
    .SYNOPSIS
        Enables command line logging in process creation events.
    
    .DESCRIPTION
        When enabled, Event ID 4688 (process creation) will include
        the full command line used to start the process.
    #>
    
    Write-Host "`n=== Enabling Command Line Auditing ===" -ForegroundColor Cyan
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord -Force
    
    # Also enable via auditpol
    auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable 2>$null
    
    Write-Host "[OK] Command line auditing enabled (Event ID 4688)" -ForegroundColor Green
}

#=============================================================================
# POWERSHELL LOGGING
#=============================================================================
function Enable-PowerShellLogging {
    <#
    .SYNOPSIS
        Enables comprehensive PowerShell logging.
    
    .DESCRIPTION
        Enables Script Block Logging, Module Logging, and Transcription
        for maximum visibility into PowerShell activity.
    #>
    
    Write-Host "`n=== Enabling PowerShell Logging ===" -ForegroundColor Cyan
    
    # Script Block Logging
    $sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (-not (Test-Path $sbPath)) {
        New-Item -Path $sbPath -Force | Out-Null
    }
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockInvocationLogging" -Value 1 -Type DWord -Force
    Write-Host "[OK] Script Block Logging enabled" -ForegroundColor Green
    
    # Module Logging
    $mlPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    if (-not (Test-Path $mlPath)) {
        New-Item -Path $mlPath -Force | Out-Null
    }
    Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord -Force
    
    # Log all modules
    $mlModulesPath = "$mlPath\ModuleNames"
    if (-not (Test-Path $mlModulesPath)) {
        New-Item -Path $mlModulesPath -Force | Out-Null
    }
    Set-ItemProperty -Path $mlModulesPath -Name "*" -Value "*" -Type String -Force
    Write-Host "[OK] Module Logging enabled (all modules)" -ForegroundColor Green
    
    # Transcription (optional - saves to file)
    $transPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"
    if (-not (Test-Path $transPath)) {
        New-Item -Path $transPath -Force | Out-Null
    }
    Set-ItemProperty -Path $transPath -Name "EnableTranscripting" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $transPath -Name "EnableInvocationHeader" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $transPath -Name "OutputDirectory" -Value "C:\CCDC-Toolkit\logs\powershell" -Type String -Force
    
    # Create transcript directory
    $transcriptDir = "C:\CCDC-Toolkit\logs\powershell"
    if (-not (Test-Path $transcriptDir)) {
        New-Item -ItemType Directory -Path $transcriptDir -Force | Out-Null
    }
    
    Write-Host "[OK] Transcription enabled (output: $transcriptDir)" -ForegroundColor Green
}

#=============================================================================
# FIREWALL LOGGING
#=============================================================================
function Enable-FirewallLogging {
    <#
    .SYNOPSIS
        Enables Windows Firewall logging for all profiles.
    #>
    
    Write-Host "`n=== Enabling Firewall Logging ===" -ForegroundColor Cyan
    
    # Enable logging for all profiles
    $profiles = @("Domain", "Public", "Private")
    
    foreach ($profile in $profiles) {
        try {
            Set-NetFirewallProfile -Profile $profile `
                -LogAllowed True `
                -LogBlocked True `
                -LogFileName "%systemroot%\system32\LogFiles\Firewall\pfirewall.log" `
                -LogMaxSizeKilobytes 20000 `
                -ErrorAction SilentlyContinue
        }
        catch {
            # Try netsh fallback
            netsh advfirewall set ${profile}profile logging filename "%systemroot%\system32\LogFiles\Firewall\pfirewall.log" 2>$null
            netsh advfirewall set ${profile}profile logging maxfilesize 20000 2>$null
            netsh advfirewall set ${profile}profile logging droppedconnections enable 2>$null
            netsh advfirewall set ${profile}profile logging allowedconnections enable 2>$null
        }
    }
    
    Write-Host "[OK] Firewall logging enabled for all profiles" -ForegroundColor Green
    Write-Host "    Log location: %systemroot%\system32\LogFiles\Firewall\pfirewall.log" -ForegroundColor Gray
}

#=============================================================================
# SYSMON CONFIGURATION
#=============================================================================
function Get-SysmonStatus {
    <#
    .SYNOPSIS
        Checks if Sysmon is installed and running.
    #>
    
    $sysmon = Get-Service -Name "Sysmon*" -ErrorAction SilentlyContinue
    
    if ($sysmon) {
        return @{
            Installed = $true
            Running = $sysmon.Status -eq 'Running'
            ServiceName = $sysmon.Name
        }
    }
    
    return @{
        Installed = $false
        Running = $false
        ServiceName = $null
    }
}

function Install-Sysmon {
    <#
    .SYNOPSIS
        Downloads and installs Sysmon with a security-focused configuration.
    #>
    
    Write-Host "`n=== Installing Sysmon ===" -ForegroundColor Cyan
    
    $status = Get-SysmonStatus
    if ($status.Installed) {
        Write-Host "[INFO] Sysmon already installed (Service: $($status.ServiceName))" -ForegroundColor Blue
        return
    }
    
    $sysmonDir = "C:\CCDC-Toolkit\sysmon"
    $sysmonUrl = "https://download.sysinternals.com/files/Sysmon.zip"
    $sysmonZip = "$sysmonDir\Sysmon.zip"
    
    try {
        # Create directory
        if (-not (Test-Path $sysmonDir)) {
            New-Item -ItemType Directory -Path $sysmonDir -Force | Out-Null
        }
        
        # Download Sysmon
        Write-Host "[INFO] Downloading Sysmon..." -ForegroundColor Blue
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $sysmonUrl -OutFile $sysmonZip -UseBasicParsing
        
        # Extract
        Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
        
        # Create basic config
        $configPath = "$sysmonDir\sysmonconfig.xml"
        $config = @"
<Sysmon schemaversion="4.90">
    <HashAlgorithms>md5,sha256,IMPHASH</HashAlgorithms>
    <EventFiltering>
        <ProcessCreate onmatch="exclude">
            <Image condition="end with">splunk.exe</Image>
        </ProcessCreate>
        <FileCreateTime onmatch="include" />
        <NetworkConnect onmatch="include" />
        <ProcessTerminate onmatch="include" />
        <DriverLoad onmatch="include" />
        <ImageLoad onmatch="include" />
        <CreateRemoteThread onmatch="include" />
        <RawAccessRead onmatch="include" />
        <ProcessAccess onmatch="include" />
        <FileCreate onmatch="include" />
        <RegistryEvent onmatch="include" />
        <FileCreateStreamHash onmatch="include" />
        <PipeEvent onmatch="include" />
        <WmiEvent onmatch="include" />
        <DnsQuery onmatch="include" />
        <FileDelete onmatch="include" />
        <ClipboardChange onmatch="include" />
        <ProcessTampering onmatch="include" />
        <FileDeleteDetected onmatch="include" />
    </EventFiltering>
</Sysmon>
"@
        $config | Out-File -FilePath $configPath -Encoding UTF8
        
        # Install Sysmon
        $arch = if ([Environment]::Is64BitOperatingSystem) { "64" } else { "" }
        $sysmonExe = "$sysmonDir\Sysmon$arch.exe"
        
        Write-Host "[INFO] Installing Sysmon..." -ForegroundColor Blue
        Start-Process -FilePath $sysmonExe -ArgumentList "-accepteula -i `"$configPath`"" -Wait -NoNewWindow
        
        Write-Host "[OK] Sysmon installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to install Sysmon: $_" -ForegroundColor Red
    }
}

#=============================================================================
# MASTER FUNCTION
#=============================================================================
function Enable-AllAuditing {
    <#
    .SYNOPSIS
        Enables all auditing features.
    #>
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  CCDC26 Advanced Auditing Setup       " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    Enable-AdvancedAuditing
    Enable-RegistryAuditing
    Enable-CommandLineAuditing
    Enable-PowerShellLogging
    Enable-FirewallLogging
    
    # Check/offer Sysmon
    $sysmonStatus = Get-SysmonStatus
    if (-not $sysmonStatus.Installed) {
        Write-Host "`n[INFO] Sysmon is not installed" -ForegroundColor Yellow
        Write-Host "Sysmon provides enhanced process/network/file monitoring." -ForegroundColor Gray
        $install = Read-Host "Install Sysmon? (y/n)"
        if ($install -ieq 'y') {
            Install-Sysmon
        }
    }
    else {
        Write-Host "`n[INFO] Sysmon is already installed and $($sysmonStatus.Running ? 'running' : 'stopped')" -ForegroundColor Blue
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Auditing Configuration Complete      " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Logs will appear in:" -ForegroundColor Yellow
    Write-Host "  - Security Event Log (Event IDs 4624, 4625, 4688, etc.)" -ForegroundColor Gray
    Write-Host "  - PowerShell Operational Log" -ForegroundColor Gray
    Write-Host "  - Firewall Log: %systemroot%\system32\LogFiles\Firewall\pfirewall.log" -ForegroundColor Gray
    Write-Host "  - PowerShell Transcripts: C:\CCDC-Toolkit\logs\powershell\" -ForegroundColor Gray
    if ($sysmonStatus.Installed) {
        Write-Host "  - Sysmon Event Log (Microsoft-Windows-Sysmon/Operational)" -ForegroundColor Gray
    }
}

# If run directly, enable all auditing
if ($MyInvocation.InvocationName -ne '.') {
    Enable-AllAuditing
}

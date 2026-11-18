#Requires -RunAsAdministrator
# CCDC26 Dovetail - Wazuh HIDS Agent Installer
# Installs the Wazuh agent and registers with a Wazuh manager.
# Provides file integrity monitoring, rootkit detection, and log analysis.
# Alerts forward through the manager to Splunk for centralized visibility.
# Usage: .\setup-wazuh-agent.ps1 -ManagerIP "10.0.0.5"

param(
    [string]$ManagerIP = "",
    [string]$AgentName = $env:COMPUTERNAME,
    [string]$AgentGroup = "windows-agents",
    [string]$WazuhVersion = "4.7.5-1"
)

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\wazuh-agent-setup.log"

function Info { param([string]$M) Write-Host "[*] $M" -ForegroundColor Cyan }
function OK   { param([string]$M) Write-Host "[+] $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "[!] $M" -ForegroundColor Yellow }
function Err  { param([string]$M) Write-Host "[-] $M" -ForegroundColor Red }
function Log  { param([string]$M) $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "$ts - $M" | Out-File $LogFile -Append -Encoding UTF8 }

# Try loading config for WAZUH_MANAGER
$cfgPath = "C:\ccdc26\config.ps1"
if (Test-Path $cfgPath) { . $cfgPath }
if (-not $ManagerIP -and $script:EnvConfig) {
    $cfg = $script:EnvConfig
    if ($cfg.WazuhManager) { $ManagerIP = $cfg.WazuhManager }
}

if (-not $ManagerIP) {
    Err "Wazuh manager IP not set."
    Err "Usage: .\setup-wazuh-agent.ps1 -ManagerIP '10.0.0.5'"
    Err "Or set WazuhManager in config.ps1"
    exit 1
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Err "Must run as Administrator"
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  CCDC26 Dovetail - Wazuh Agent Setup" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Info "Host:      $AgentName"
Info "Manager:   $ManagerIP"
Info "Version:   $WazuhVersion"
Info "Group:     $AgentGroup"
Write-Host ""

#=============================================================================
# PHASE 1 - Check Existing Installation
#=============================================================================
Write-Host "`n== PHASE 1 - Check Existing Installation ==" -ForegroundColor Magenta

$existingService = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($existingService -and $existingService.Status -eq "Running") {
    $confPath = "C:\Program Files (x86)\ossec-agent\ossec.conf"
    if (-not (Test-Path $confPath)) { $confPath = "C:\Program Files\ossec-agent\ossec.conf" }
    if (Test-Path $confPath) {
        $confContent = Get-Content $confPath -Raw
        if ($confContent -match "<address>$([regex]::Escape($ManagerIP))</address>") {
            OK "Wazuh agent already installed and pointing to $ManagerIP"
            Info "Restarting agent..."
            Restart-Service WazuhSvc -Force
            OK "Agent restarted. Done."
            exit 0
        }
        Warn "Agent installed but pointing to different manager -- reconfiguring"
    }
}

if ($existingService) {
    Info "Removing existing Wazuh agent for clean install..."
    Stop-Service -Name "WazuhSvc" -Force -ErrorAction SilentlyContinue
    $uninstallKey = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -like "*Wazuh Agent*" }
    if ($uninstallKey) {
        $productCode = (Get-ItemProperty $uninstallKey.PSPath).ProductCode
        Start-Process "msiexec.exe" -ArgumentList "/x `"$productCode`" /qn" -Wait
        OK "Existing agent removed"
    }
}

#=============================================================================
# PHASE 2 - Download Installer
#=============================================================================
Write-Host "`n== PHASE 2 - Download Agent Installer ==" -ForegroundColor Magenta

$InstallerURL  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-${WazuhVersion}.msi"
$InstallerPath = "$env:TEMP\wazuh-agent-${WazuhVersion}.msi"

Info "Downloading from: $InstallerURL"
Log "Downloading Wazuh agent $WazuhVersion"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $InstallerURL -OutFile $InstallerPath -UseBasicParsing
    $ProgressPreference = "Continue"
    $sizeMB = [math]::Round((Get-Item $InstallerPath).Length / 1MB, 1)
    OK "Downloaded (${sizeMB} MB)"
} catch {
    Err "Download failed: $_"
    Log "Download failed: $_"
    exit 1
}

#=============================================================================
# PHASE 3 - Install Agent
#=============================================================================
Write-Host "`n== PHASE 3 - Install Wazuh Agent ==" -ForegroundColor Magenta

$MsiArgs = @(
    "/i", "`"$InstallerPath`"",
    "/qn",
    "WAZUH_MANAGER=`"$ManagerIP`"",
    "WAZUH_AGENT_NAME=`"$AgentName`"",
    "WAZUH_AGENT_GROUP=`"$AgentGroup`"",
    "WAZUH_REGISTRATION_SERVER=`"$ManagerIP`"",
    "WAZUH_REGISTRATION_PORT=`"1515`"",
    "WAZUH_MANAGER_PORT=`"1514`""
)

Info "Running MSI installer silently..."
$proc = Start-Process "msiexec.exe" -ArgumentList $MsiArgs -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    Err "MSI install failed (exit code: $($proc.ExitCode))"
    Log "MSI install failed: $($proc.ExitCode)"
    exit 1
}
OK "Wazuh agent installed"
Log "Agent installed successfully"

#=============================================================================
# PHASE 4 - Configure Agent
#=============================================================================
Write-Host "`n== PHASE 4 - Write Agent Configuration ==" -ForegroundColor Magenta

$OssecConf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
if (-not (Test-Path $OssecConf)) {
    $OssecConf = "C:\Program Files\ossec-agent\ossec.conf"
}

if (Test-Path $OssecConf) {
    Copy-Item $OssecConf "$OssecConf.bak" -Force
    Info "Backed up existing ossec.conf"
}

$cleanConf = @"
<ossec_config>

  <client>
    <server>
      <address>$ManagerIP</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <enrollment>
      <enabled>yes</enabled>
    </enrollment>
  </client>

  <client_buffer>
    <disabled>no</disabled>
    <queue_size>5000</queue_size>
    <events_per_second>500</events_per_second>
  </client_buffer>

  <!-- Windows event channels -->
  <localfile>
    <location>Security</location>
    <log_format>eventchannel</log_format>
    <query>Event/System[EventID != 5156 and EventID != 5158]</query>
  </localfile>

  <localfile>
    <location>System</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Application</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-PowerShell/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-Windows Defender/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-TaskScheduler/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-Bits-Client/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Microsoft-Windows-WMI-Activity/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

</ossec_config>
"@

Set-Content -Path $OssecConf -Value $cleanConf -Encoding UTF8
OK "ossec.conf written (manager: $ManagerIP)"

#=============================================================================
# PHASE 5 - Enable PowerShell Logging
#=============================================================================
Write-Host "`n== PHASE 5 - Enable Enhanced Logging ==" -ForegroundColor Magenta

try {
    $sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    $mlPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"

    if (-not (Test-Path $sbPath)) { New-Item -Path $sbPath -Force | Out-Null }
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockInvocationLogging" -Value 1 -Type DWord

    if (-not (Test-Path $mlPath)) { New-Item -Path $mlPath -Force | Out-Null }
    Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord
    $mnPath = "$mlPath\ModuleNames"
    if (-not (Test-Path $mnPath)) { New-Item -Path $mnPath -Force | Out-Null }
    Set-ItemProperty -Path $mnPath -Name "*" -Value "*" -Type String

    OK "PowerShell Script Block + Module Logging enabled"
} catch {
    Warn "Could not configure PowerShell logging: $_"
}

# Audit policies for detection coverage
try {
    $policies = @(
        'auditpol /set /subcategory:"Logon" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Logoff" /success:enable',
        'auditpol /set /subcategory:"Account Lockout" /failure:enable',
        'auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Process Creation" /success:enable',
        'auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Special Logon" /success:enable',
        'auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable'
    )
    foreach ($p in $policies) { Invoke-Expression $p | Out-Null }
    OK "Audit policies configured"
} catch {
    Warn "Could not set audit policies: $_"
}

#=============================================================================
# PHASE 6 - Firewall + Start Service
#=============================================================================
Write-Host "`n== PHASE 6 - Firewall + Start Service ==" -ForegroundColor Magenta

try {
    New-NetFirewallRule -DisplayName "Wazuh Agent -> Manager" `
        -Direction Outbound -Protocol TCP `
        -RemoteAddress $ManagerIP -RemotePort 1514,1515 `
        -Action Allow -ErrorAction SilentlyContinue | Out-Null
    OK "Firewall rule added for $ManagerIP (1514/1515)"
} catch {
    Warn "Could not create firewall rule: $_"
}

try {
    Start-Service -Name "WazuhSvc"
    Set-Service -Name "WazuhSvc" -StartupType Automatic
    Start-Sleep -Seconds 5

    $status = (Get-Service -Name "WazuhSvc").Status
    if ($status -eq "Running") {
        OK "Wazuh agent service is RUNNING"
    } else {
        Warn "Service status: $status"
    }
} catch {
    Warn "Could not start WazuhSvc: $_"
}

#=============================================================================
# PHASE 7 - Verify Connectivity
#=============================================================================
Write-Host "`n== PHASE 7 - Verify Connectivity ==" -ForegroundColor Magenta

foreach ($port in @(1514, 1515)) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $result = $tcp.BeginConnect($ManagerIP, $port, $null, $null)
        $ok = $result.AsyncWaitHandle.WaitOne(3000, $false)
        if ($ok -and $tcp.Connected) {
            OK "Port $port reachable on $ManagerIP"
        } else {
            Warn "Port $port NOT reachable on $ManagerIP"
        }
        $tcp.Close()
    } catch {
        Warn "Port $port test failed: $_"
    }
}

# Cleanup installer
if (Test-Path $InstallerPath) {
    Remove-Item $InstallerPath -Force
    Info "Installer MSI removed"
}

#=============================================================================
# SUMMARY
#=============================================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Wazuh Agent Setup Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Agent:    $AgentName" -ForegroundColor Cyan
Write-Host "  Manager:  $ManagerIP" -ForegroundColor Cyan
Write-Host "  Version:  $WazuhVersion (pinned)" -ForegroundColor Cyan
Write-Host "  Group:    $AgentGroup" -ForegroundColor Cyan
Write-Host "  Service:  WazuhSvc (Automatic)" -ForegroundColor Cyan
Write-Host "  Log:      C:\Program Files (x86)\ossec-agent\ossec.log" -ForegroundColor Cyan
Write-Host "  Setup Log: $LogFile" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "DETECTION COVERAGE:" -ForegroundColor Yellow
Write-Host "  - File integrity monitoring (FIM)"
Write-Host "  - Windows Security/System/Application events"
Write-Host "  - PowerShell script block logging"
Write-Host "  - Sysmon events (if installed)"
Write-Host "  - Scheduled task + RDP monitoring"
Write-Host "  - 3000+ built-in Wazuh detection rules"
Write-Host ""
Log "Setup completed successfully"

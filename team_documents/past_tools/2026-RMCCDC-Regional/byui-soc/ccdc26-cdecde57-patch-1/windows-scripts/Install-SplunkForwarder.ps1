<#
.SYNOPSIS
    CCDC26 - Splunk Universal Forwarder Setup for Windows
    
.DESCRIPTION
    Installs and configures Splunk Universal Forwarder to send logs to the
    competition Splunk server (Oracle Linux 9.2, Splunk 10.0.2).
    
    Server: 172.20.242.20:9997
    
.EXAMPLE
    .\Install-SplunkForwarder.ps1
    Interactive menu
    
.EXAMPLE
    .\Install-SplunkForwarder.ps1 -Quick
    Quick setup (install + configure + start)
    
.EXAMPLE
    .\Install-SplunkForwarder.ps1 -Status
    Check current status
#>

param(
    [switch]$Quick,
    [switch]$Status,
    [switch]$Install,
    [switch]$Configure,
    [switch]$Start,
    [switch]$Stop
)

#Requires -RunAsAdministrator

# CONFIGURATION - Competition Splunk Server
$SPLUNK_SERVER = "172.20.242.20"
$SPLUNK_PORT = "9997"
$SPLUNK_VERSION = "10.2.0"
$SPLUNK_BUILD = "d749cb17ea65"
$SPLUNK_HOME = "C:\Program Files\SplunkUniversalForwarder"
$SPLUNK_MSI_URL = "https://download.splunk.com/products/universalforwarder/releases/$SPLUNK_VERSION/windows/splunkforwarder-$SPLUNK_VERSION-$SPLUNK_BUILD-windows-x64.msi"

function Write-Info { Write-Host "[*] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[+] $args" -ForegroundColor Green }
function Write-Warning { Write-Host "[!] $args" -ForegroundColor Yellow }
function Write-Error { Write-Host "[-] $args" -ForegroundColor Red }

function Test-SplunkInstalled {
    return (Test-Path "$SPLUNK_HOME\bin\splunk.exe")
}

function Install-SplunkForwarder {
    Write-Info "Installing Splunk Universal Forwarder..."
    
    $msiPath = "$env:TEMP\splunkforwarder.msi"
    
    try {
        Write-Info "Downloading Splunk UF from $SPLUNK_MSI_URL..."
        
        # Use TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($SPLUNK_MSI_URL, $msiPath)
        
        Write-Info "Installing Splunk UF (this may take a few minutes)..."
        
        # Install with configuration
        $installArgs = @(
            "/i", $msiPath,
            "AGREETOLICENSE=yes",
            "RECEIVING_INDEXER=${SPLUNK_SERVER}:${SPLUNK_PORT}",
            "LAUNCHSPLUNK=0",
            "/quiet"
        )
        
        Start-Process msiexec.exe -ArgumentList $installArgs -Wait -NoNewWindow
        
        # Clean up
        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        
        # Verify installation
        if (Test-Path "$SPLUNK_HOME\bin\splunk.exe") {
            Write-Success "Splunk Universal Forwarder installed and verified"
        } else {
            Write-Error "Installation completed but splunk.exe not found at $SPLUNK_HOME\bin\splunk.exe"
            Write-Warning "Installation may have failed - check manually"
            return $false
        }
    }
    catch {
        Write-Error "Failed to install Splunk UF: $_"
        Write-Warning "Try manual installation from: $SPLUNK_MSI_URL"
        return $false
    }
    return $true
}

function Configure-SplunkForwarder {
    Write-Info "Configuring Splunk forwarder to send to ${SPLUNK_SERVER}:${SPLUNK_PORT}..."
    
    $localDir = "$SPLUNK_HOME\etc\system\local"
    if (-not (Test-Path $localDir)) {
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
    }
    
    # Configure outputs.conf
    $outputsConf = @"
[tcpout]
defaultGroup = competition_splunk

[tcpout:competition_splunk]
server = ${SPLUNK_SERVER}:${SPLUNK_PORT}
compressed = true

[tcpout-server://${SPLUNK_SERVER}:${SPLUNK_PORT}]
"@
    
    Set-Content -Path "$localDir\outputs.conf" -Value $outputsConf
    
    # Configure inputs.conf for Windows Event Logs
    $inputsConf = @"
# CCDC26 Splunk Forwarder - Windows Event Log Collection
# Competition Splunk server: 172.20.242.20:9997

[default]
host = $env:COMPUTERNAME

# =============================================================================
# WINDOWS SECURITY EVENTS (Critical)
# =============================================================================
[WinEventLog://Security]
disabled = false
index = windows-security
sourcetype = WinEventLog:Security
evt_resolve_ad_obj = 1
checkpointInterval = 5

# =============================================================================
# WINDOWS SYSTEM EVENTS
# =============================================================================
[WinEventLog://System]
disabled = false
index = windows-system
sourcetype = WinEventLog:System

[WinEventLog://Application]
disabled = false
index = windows-application
sourcetype = WinEventLog:Application

# =============================================================================
# POWERSHELL LOGGING (Critical for detecting attacks)
# =============================================================================
[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = false
index = windows-powershell
sourcetype = WinEventLog:PowerShell

[WinEventLog://PowerShellCore/Operational]
disabled = false
index = windows-powershell
sourcetype = WinEventLog:PowerShell

# =============================================================================
# WINDOWS DEFENDER
# =============================================================================
[WinEventLog://Microsoft-Windows-Windows Defender/Operational]
disabled = false
index = windows-security
sourcetype = WinEventLog:Defender

# =============================================================================
# WINDOWS FIREWALL
# =============================================================================
[WinEventLog://Microsoft-Windows-Windows Firewall With Advanced Security/Firewall]
disabled = false
index = windows-security
sourcetype = WinEventLog:Firewall

# =============================================================================
# TASK SCHEDULER (Persistence detection)
# =============================================================================
[WinEventLog://Microsoft-Windows-TaskScheduler/Operational]
disabled = false
index = windows-security
sourcetype = WinEventLog:TaskScheduler

# =============================================================================
# REMOTE DESKTOP
# =============================================================================
[WinEventLog://Microsoft-Windows-TerminalServices-LocalSessionManager/Operational]
disabled = false
index = windows-security
sourcetype = WinEventLog:RDP

[WinEventLog://Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational]
disabled = false
index = windows-security
sourcetype = WinEventLog:RDP

# =============================================================================
# SYSMON (if installed)
# =============================================================================
[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = false
index = windows-sysmon
sourcetype = WinEventLog:Sysmon
renderXml = true

# =============================================================================
# DNS SERVER (if this is a DC)
# =============================================================================
[WinEventLog://DNS Server]
disabled = false
index = windows-dns
sourcetype = WinEventLog:DNS

# =============================================================================
# ACTIVE DIRECTORY (if this is a DC)
# =============================================================================
[WinEventLog://Directory Service]
disabled = false
index = windows-security
sourcetype = WinEventLog:DirectoryService
"@
    
    Set-Content -Path "$localDir\inputs.conf" -Value $inputsConf
    
    Write-Success "Splunk forwarder configured"
}

function Enable-PowerShellLogging {
    Write-Info "Enabling PowerShell logging for Splunk..."
    
    # Script Block Logging
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
    
    # Module Logging
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "EnableModuleLogging" -Value 1 -Type DWord
    
    # Log all modules
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "*" -Value "*" -Type String
    
    Write-Success "PowerShell logging enabled"
}

function Enable-CommandLineAuditing {
    Write-Info "Enabling command line auditing..."
    
    # Enable command line in process creation events
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    
    # Enable audit process creation
    auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable 2>$null
    
    Write-Success "Command line auditing enabled"
}

function Start-SplunkForwarder {
    Write-Info "Starting Splunk forwarder..."
    
    & "$SPLUNK_HOME\bin\splunk.exe" start --accept-license --answer-yes --no-prompt 2>$null
    
    # Ensure service is set to auto-start
    Set-Service -Name "SplunkForwarder" -StartupType Automatic -ErrorAction SilentlyContinue
    
    Write-Success "Splunk forwarder started"
}

function Stop-SplunkForwarder {
    Write-Info "Stopping Splunk forwarder..."
    & "$SPLUNK_HOME\bin\splunk.exe" stop 2>$null
    Write-Success "Splunk forwarder stopped"
}

function Get-SplunkStatus {
    Write-Host ""
    Write-Host "Splunk Forwarder Status" -ForegroundColor Cyan
    Write-Host "=======================" -ForegroundColor Cyan
    
    if (Test-SplunkInstalled) {
        Write-Success "Splunk UF is installed at $SPLUNK_HOME"
        
        $service = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq "Running") {
                Write-Success "Splunk forwarder service is RUNNING"
            } else {
                Write-Warning "Splunk forwarder service is $($service.Status)"
            }
        }
        
        Write-Info "Target server: ${SPLUNK_SERVER}:${SPLUNK_PORT}"
        
        # Test connectivity
        $connection = Test-NetConnection -ComputerName $SPLUNK_SERVER -Port $SPLUNK_PORT -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Write-Success "Connection to Splunk server: OK"
        } else {
            Write-Warning "Cannot connect to Splunk server on port $SPLUNK_PORT"
        }
    } else {
        Write-Warning "Splunk UF is not installed"
    }
}

function Test-SplunkForwarding {
    Write-Info "Generating test event..."
    
    # Write to Windows Event Log
    $source = "CCDC26_SplunkTest"
    if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
        New-EventLog -LogName Application -Source $source -ErrorAction SilentlyContinue
    }
    
    Write-EventLog -LogName Application -Source $source -EntryType Information -EventId 1000 -Message "CCDC26 Splunk forwarder test event - $(Get-Date)"
    
    Write-Success "Test event written to Application event log"
    Write-Info "Check Splunk server for events from $env:COMPUTERNAME"
}

function Uninstall-SplunkForwarder {
    Write-Warning "Uninstalling Splunk Universal Forwarder..."
    
    Stop-SplunkForwarder
    
    # Uninstall via MSI
    $app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Splunk*Forwarder*" }
    if ($app) {
        $app.Uninstall()
    }
    
    # Clean up directory
    if (Test-Path $SPLUNK_HOME) {
        Remove-Item -Path $SPLUNK_HOME -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Success "Splunk UF uninstalled"
}

function Invoke-QuickSetup {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Splunk Forwarder Quick Setup" -ForegroundColor Cyan
    Write-Host "  Target: ${SPLUNK_SERVER}:${SPLUNK_PORT}" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if (Test-SplunkInstalled) {
        Write-Info "Splunk UF already installed, reconfiguring..."
    } else {
        Install-SplunkForwarder
    }
    
    Configure-SplunkForwarder
    Enable-PowerShellLogging
    Enable-CommandLineAuditing
    Start-SplunkForwarder
    Get-SplunkStatus
    
    Write-Host ""
    Write-Success "Splunk forwarder setup complete!"
    Write-Info "Logs are now being forwarded to ${SPLUNK_SERVER}:${SPLUNK_PORT}"
}

function Show-Menu {
    Write-Host ""
    Write-Host "Splunk Universal Forwarder Setup" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "Target Server: ${SPLUNK_SERVER}:${SPLUNK_PORT}" -ForegroundColor Gray
    Write-Host ""
    Write-Host "1) Quick Setup (install + configure + start)"
    Write-Host "2) Install forwarder only"
    Write-Host "3) Configure forwarder"
    Write-Host "4) Start forwarder"
    Write-Host "5) Stop forwarder"
    Write-Host "6) Check status"
    Write-Host "7) Test forwarding"
    Write-Host "8) Uninstall"
    Write-Host "9) Exit"
    Write-Host ""
    
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" { Invoke-QuickSetup }
        "2" { Install-SplunkForwarder }
        "3" { Configure-SplunkForwarder }
        "4" { Start-SplunkForwarder }
        "5" { Stop-SplunkForwarder }
        "6" { Get-SplunkStatus }
        "7" { Test-SplunkForwarding }
        "8" { Uninstall-SplunkForwarder }
        "9" { exit }
        default { Write-Error "Invalid option" }
    }
}

# Main
if ($Quick) {
    Invoke-QuickSetup
} elseif ($Status) {
    Get-SplunkStatus
} elseif ($Install) {
    Install-SplunkForwarder
} elseif ($Configure) {
    Configure-SplunkForwarder
} elseif ($Start) {
    Start-SplunkForwarder
} elseif ($Stop) {
    Stop-SplunkForwarder
} else {
    Show-Menu
}

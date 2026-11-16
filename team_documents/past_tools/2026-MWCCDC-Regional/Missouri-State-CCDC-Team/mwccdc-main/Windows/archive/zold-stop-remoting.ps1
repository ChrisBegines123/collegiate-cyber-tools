# ==============================================================================
# Script Name : stopRemoting.ps1
# Description : exposed remote access to the internet? not ideal, Mr. Robot 
#               could comprimise us if we did that.
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.0
# ==============================================================================
# Usage       : ./secure-remoting.ps1 -AllowedIP "192.168.1.10"
# Notes       :
#   - Disable all remote management services.
# ==============================================================================

# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\RemotingState_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$TimeStamp] [$Level] $Message"
    $LogMessage | Out-File -FilePath $LogFile -Append
    
    # Also output to console with color coding
    switch ($Level) {
        "INFO" { Write-Host $LogMessage -ForegroundColor Gray }
        "WARNING" { Write-Host $LogMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
    }
}

Write-Log "Starting to disable all remote management services" "INFO"

# Verify running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires Administrator privileges. Please restart with elevated permissions." "ERROR"
    exit 1
}

# 1. Back up current firewall rules
try {
    $backupDir = "C:\Backup\Firewall"
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    $backupFile = "$backupDir\FirewallRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').wfw"
    netsh advfirewall export "$backupFile"
    Write-Log "Firewall rules backed up to $backupFile" "SUCCESS"
}
catch {
    Write-Log "Failed to back up firewall rules: $_" "WARNING"
}

# 2. Stop and disable remote management services
$servicesToDisable = @(
    "RemoteRegistry",
    "WinRM",
    "RemoteAccess",
    "SessionEnv",
    "TermService",
    "UmRdpService",
    "SharedAccess",
    "iphlpsvc"
)

foreach ($service in $servicesToDisable) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log "Stopping service: $service"
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service -StartupType Disabled
            $status = (Get-Service -Name $service).Status
            $startMode = (Get-WmiObject -Class Win32_Service -Filter "Name='$service'").StartMode
            Write-Log "Service $service - Status: $status, Startup: $startMode" "SUCCESS"
        }
        else {
            Write-Log "Service $service not found" "INFO"
        }
    }
    catch {
        Write-Log "Error processing service $service : $_" "ERROR"
    }
}

# 3. Block all incoming remote management ports with firewall
try {
    Write-Log "Adding firewall rules to block remote management ports"
    
    # Create a rule to block all incoming RDP connections
    New-NetFirewallRule -DisplayName "Block RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Block -Enabled True
    
    # Create a rule to block all incoming WinRM connections
    New-NetFirewallRule -DisplayName "Block WinRM" -Direction Inbound -Protocol TCP -LocalPort 5985,5986 -Action Block -Enabled True
    
    # Create a rule to block all incoming SSH connections
    New-NetFirewallRule -DisplayName "Block SSH" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Block -Enabled True
    
    # Create a rule to block all incoming PowerShell Remoting
    New-NetFirewallRule -DisplayName "Block PowerShell Remoting" -Direction Inbound -Protocol TCP -LocalPort 5985,5986 -Action Block -Enabled True
    
    Write-Log "Remote management blocking rules added successfully" "SUCCESS"
}
catch {
    Write-Log "Failed to add blocking rules: $_" "ERROR"
}

# 4. Disable WinRM completely
try {
    Write-Log "Disabling WinRM service and configuration"
    
    # Disable WinRM service
    Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
    Set-Service -Name WinRM -StartupType Disabled
    
    # Verify WinRM is disabled
    $winrmStatus = (Get-Service -Name WinRM).Status
    if ($winrmStatus -eq "Stopped") {
        Write-Log "WinRM service is stopped" "SUCCESS"
    }
    else {
        Write-Log "WinRM service could not be stopped" "ERROR"
    }
}
catch {
    Write-Log "Error disabling WinRM: $_" "ERROR"
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "             REMOTE MANAGEMENT SERVICES DISABLED                  " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "All remote management services have been disabled" -ForegroundColor Green
Write-Host "Firewall rules added to block remote management ports" -ForegroundColor Green
Write-Host "Configuration log saved to: $LogFile" -ForegroundColor White
Write-Host "Firewall backup saved to: $backupFile" -ForegroundColor White
Write-Host "==================================================================" -ForegroundColor Cyan
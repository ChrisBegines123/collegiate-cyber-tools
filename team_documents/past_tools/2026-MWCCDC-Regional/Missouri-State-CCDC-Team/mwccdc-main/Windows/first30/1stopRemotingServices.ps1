# ==============================================================================
# Script Name : 1stopRemotingServices.ps1
# Description : exposed remote access to the internet? Mr. Robot 
#               could comprimise us if we did that.
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 2.0 - This definitely didn't just nuke AD on its last version. no... that would be stupid!
# ==============================================================================
# Usage       : ./1stopRemotingServices.ps1
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

# 1. Back up current configurations
try {
    $backupDir = "C:\Backup\SecurityConfig"
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    # Backup firewall rules
    $firewallBackup = "$backupDir\FirewallRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').wfw"
    netsh advfirewall export "$firewallBackup"
    Write-Log "Firewall rules backed up to $firewallBackup" "SUCCESS"
    
    # Backup service states
    $serviceBackup = "$backupDir\Services_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    Get-Service | Select-Object Name, Status, StartType | Export-Csv -Path $serviceBackup -NoTypeInformation
    Write-Log "Service states backed up to $serviceBackup" "SUCCESS"
}
catch {
    Write-Log "Failed to complete backups: $_" "WARNING"
}

# 2. Disable RDP via Registry and servies
try { 
    Write-Log "Disabling Remote Desktop Protocol (RDP)" "INFO"

    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fDenyTSConnections /t REG_DWORD /d 1 /f

    get-service -Name "TermService" | Stop-Service -Force
    Set-Service -Name "TermService" -StartupType Disabled
}
catch {
    Write-Log "Failed to disable RDP: $_" "ERROR"
}

# 3. Disable PowerShell Remoting
try { 
    Write-Log "Disabling PowerShell Remoting" "INFO"
    Disable-PSRemoting -Force -ErrorAction SilentlyContinue
    Write-Log "PowerShell Remoting disabled successfully" "SUCCESS"
}
catch { 
    Write-Log "Failed to disable PowerShell Remoting: $_" "ERROR"
}


# 4. Array of services to disable 
$servicesToDisable = @(
    # Remote Desktop
    "TermService",
    "SessionEnv", 
    "UmRdpService",
    
    # Remote Management
    "RemoteRegistry",
    "WinRM",
    "RemoteAccess",
    
    # Somebody once told me, the world was gonna roll me.

    # SSH (Windows 10/Server 2019+)
    "sshd",
    "ssh-agent"
)

foreach ($service in $servicesToDisable) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
            $status = (Get-Service -Name $service -ErrorAction SilentlyContinue).Status
            Write-Log "Service $service disabled - Status: $status" "SUCCESS"
        }
    }
    catch {
        Write-Log "Error processing service ${service}: $_" "WARNING"
    }
}

# Disable remote assistance
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowFullControl" -Value 0 -ErrorAction SilentlyContinue
    Write-Log "Remote Assistance disabled" "SUCCESS"
}
catch {
    Write-Log "Failed to disable Remote Assistance: $_" "ERROR"
}

# Disable WMI fireall rules 
try { 
    Write-Log "Disabling WMI firewall rules" "INFO"
    netsh advfirewall firewall set rule group="windows management instrumentation (wmi)" new enable=no
}
catch { 
    write-Log "Failed to disable WMI firewall rules: $_" "ERROR"
}

# Disable common third-party remote tools
$remoteTools = @("TeamViewer*", "AnyDesk*", "LogMeIn*", "Chrome Remote*", "VNC*", "Splashtop*")
foreach ($tool in $remoteTools) {
    Get-Service -Name $tool -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Get-Service -Name $tool -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
    Get-Process -Name $tool.Replace("*","") -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Log "All specified remote management services have been disabled." "SUCCESS"

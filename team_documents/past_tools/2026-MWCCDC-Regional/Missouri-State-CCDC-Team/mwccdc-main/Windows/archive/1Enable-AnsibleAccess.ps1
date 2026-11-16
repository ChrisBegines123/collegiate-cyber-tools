# ==============================================================================
# Script Name : enableAnsibleAccess.ps1
# Description : open a hole to allow for ansible to reach the system.
#               With limits of course, can't create too much of a risk
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.1
# ==============================================================================

param (
    [Parameter(Mandatory=$true)]
    [string]$AllowedIP
)

# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\AnsibleAccess_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

Write-Log "Starting temporary WinRM configuration for Ansible" "INFO"
Write-Log "Allowed IP Address: $AllowedIP" "INFO"

# Verify running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires Administrator privileges. Please restart with elevated permissions." "ERROR"
    exit 1
}

# Verify IP address format
try {
    $ipAddr = [System.Net.IPAddress]::Parse($AllowedIP)
    Write-Log "IP address format verified: $AllowedIP" "INFO"
}
catch {
    Write-Log "Invalid IP address format: $AllowedIP. Please provide a valid IP address." "ERROR"
    exit 1
}

# 1. Create Ansible user if needed
try {
    $ansibleUser = "AnsibleRemote"
    $userExists = Get-LocalUser -Name $ansibleUser -ErrorAction SilentlyContinue
    
    if (-not $userExists) {
        Write-Log "Creating dedicated Ansible user account: $ansibleUser"
        $ansiblePassword = [System.Web.Security.Membership]::GeneratePassword(24, 8)
        $securePassword = ConvertTo-SecureString -String $ansiblePassword -AsPlainText -Force
        
        New-LocalUser -Name $ansibleUser -Password $securePassword -PasswordNeverExpires $true -AccountNeverExpires
        Add-LocalGroupMember -Group "Administrators" -Member $ansibleUser
        
        Write-Log "Ansible user created successfully" "SUCCESS"
        Write-Log "Ansible User: $ansibleUser" "INFO"
        Write-Log "Ansible Password: $ansiblePassword" "INFO"
    }
    else {
        Write-Log "Ansible user already exists" "INFO"
    }
}
catch {
    Write-Log "Error creating Ansible user: $_" "ERROR"
}

# 2. Enable and configure WinRM for Ansible
try {
    Write-Log "Enabling and configuring WinRM for Ansible access"
    
    # Enable WinRM service
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM
    
    # Configure WinRM
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    
    # Configure WinRM settings for security
    winrm set winrm/config/service '@{AllowUnencrypted="false"}'
    winrm set winrm/config/service/auth '@{Basic="false";Kerberos="true";Negotiate="true";Certificate="false";CredSSP="false"}'
    winrm set winrm/config/client/auth '@{Basic="false";Kerberos="true";Negotiate="true";Certificate="false";CredSSP="false"}'
    
    Write-Log "WinRM configured successfully" "SUCCESS"
}
catch {
    Write-Log "Error configuring WinRM: $_" "ERROR"
}

# 3. Configure firewall to allow WinRM only from the specified IP
try {
    Write-Log "Configuring firewall for restricted WinRM access"
    
    # Remove any existing WinRM block rules
    Get-NetFirewallRule -DisplayName "Block WinRM" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Get-NetFirewallRule -DisplayName "Block PowerShell Remoting" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    
    # Add allow rule for specific IP
    $existingRule = Get-NetFirewallRule -DisplayName "Allow WinRM from Ansible Controller" -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName "Allow WinRM from Ansible Controller"
    }
    
    New-NetFirewallRule -DisplayName "Allow WinRM from Ansible Controller" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5985,5986 `
        -RemoteAddress $AllowedIP `
        -Action Allow `
        -Enabled True
    
    Write-Log "Firewall configured to allow WinRM access only from $AllowedIP" "SUCCESS"
}
catch {
    Write-Log "Error configuring firewall: $_" "ERROR"
}

# 4. Set the access expiration time (helps remember to disable it later)
$expirationTime = (Get-Date).AddHours(2)
$expirationTimeStr = $expirationTime.ToString("yyyy-MM-dd HH:mm:ss")
Write-Log "Setting access expiration time to $expirationTimeStr" "INFO"
Set-Content -Path "C:\Logs\ansible_access_expiration.txt" -Value $expirationTimeStr

# 5. Create a scheduled task to disable access automatically (optional)
try {
    Write-Log "Creating scheduled task to disable WinRM automatically after 2 hours"
    
    $actionScript = "C:\Scripts\Disable-AllRemoting.ps1"
    
    # Create Scripts directory if it doesn't exist
    if (-not (Test-Path "C:\Scripts")) {
        New-Item -Path "C:\Scripts" -ItemType Directory -Force | Out-Null
    }
    
    # Copy this script's counterpart there if not already present
    if (-not (Test-Path $actionScript)) {
        $currentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $disableScript = Join-Path -Path $currentDir -ChildPath "Disable-AllRemoting.ps1"
        
        if (Test-Path $disableScript) {
            Copy-Item -Path $disableScript -Destination $actionScript
        }
        else {
            Write-Log "Disable-AllRemoting.ps1 not found in current directory. Auto-expiration won't work." "WARNING"
        }
    }
    
    if (Test-Path $actionScript) {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$actionScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At $expirationTime
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        $existingTask = Get-ScheduledTask -TaskName "Disable-AnsibleAccess" -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName "Disable-AnsibleAccess" -Confirm:$false
        }
        
        Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -TaskName "Disable-AnsibleAccess" -Description "Automatically disable WinRM for Ansible access"
        
        Write-Log "Scheduled task created to disable access at $expirationTimeStr" "SUCCESS"
    }
}
catch {
    Write-Log "Error creating scheduled task: $_" "WARNING"
    Write-Log "You will need to manually disable WinRM when finished" "WARNING"
}

# 6. Verify WinRM is running
$winrmService = Get-Service -Name "WinRM"
if ($winrmService.Status -eq "Running") {
    Write-Log "WinRM service is running" "SUCCESS"
}
else {
    Write-Log "WinRM service is not running. Starting service..." "WARNING"
    Start-Service -Name "WinRM"
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "             ANSIBLE ACCESS TEMPORARILY ENABLED                   " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "WinRM is now enabled and configured for Ansible access" -ForegroundColor Green
Write-Host "Access is restricted to IP address: $AllowedIP" -ForegroundColor Yellow
Write-Host ""
Write-Host "IMPORTANT SECURITY NOTES:" -ForegroundColor Red
Write-Host "1. This access will automatically expire at: $expirationTimeStr" -ForegroundColor White
Write-Host "2. To manually disable access when done, run:" -ForegroundColor White
Write-Host "   .\Disable-AllRemoting.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Ansible connection details:" -ForegroundColor Cyan
Write-Host "Username: $ansibleUser" -ForegroundColor Yellow
if ($ansiblePassword) {
    Write-Host "Password: $ansiblePassword" -ForegroundColor Yellow
} else {
    Write-Host "Password: (Using previously configured password)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Configuration log saved to: $LogFile" -ForegroundColor White
Write-Host "==================================================================" -ForegroundColor Cyan
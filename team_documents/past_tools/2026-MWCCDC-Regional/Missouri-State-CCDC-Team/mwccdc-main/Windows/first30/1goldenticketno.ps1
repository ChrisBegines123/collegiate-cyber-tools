# ==============================================================================
# Script Name : goldenticketNo.ps1
# Description : Red team told us they already had a golden ticket for our AD,
#               I no like that so rotate creds and make it all super secure right
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.0
# ==============================================================================
# Usage       : ./goldenticketNo.ps1
# Notes       :
#   - This wil reset the password of the KRBTGT account password twice to 
#     Invalidate ALL existing tickets, nasty red teamers :P
#     This uses the same log code as my other windows scripts and stores it in C:/logs
# ==============================================================================

# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\GoldenTicketMitigation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

function New-ComplexPassword {
    param([int]$Length = 24)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    $password = -join (1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $password
}


Write-Log "Starting Golden Ticket mitigation process"

# Verify running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script requires Administrator privileges. Please restart with elevated permissions." "ERROR"
    exit 1
}

# 1. Import AD module
try {
    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log "Active Directory module imported successfully"
    }
} catch {
    Write-Log "Failed to import Active Directory module: $_" "ERROR"
    exit 1
}

# 2. First KRBTGT password reset
try {
    Write-Log "Performing first KRBTGT password reset..." "INFO"
    
    # Get domain information
    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    Write-Log "Domain: $domainName"
    
    # Backup current KRBTGT account details before resetting
    $krbtgtAccount = Get-ADUser -Identity "krbtgt" -Properties * -Server $domain.PDCEmulator
    $krbtgtSID = $krbtgtAccount.SID.Value
    $krbtgtGUID = $krbtgtAccount.ObjectGUID
    
    Write-Log "KRBTGT Account SID: $krbtgtSID"
    Write-Log "KRBTGT Account GUID: $krbtgtGUID"
    
    # Generate a new complex password
    $newPassword = New-ComplexPassword -Length 24
    $securePassword = ConvertTo-SecureString -AsPlainText $newPassword -Force
    
    # Reset the KRBTGT password
    Set-ADAccountPassword -Identity $krbtgtAccount -Reset -NewPassword $securePassword
    
    Write-Log "First KRBTGT password reset completed successfully" "SUCCESS"
} catch {
    Write-Log "Failed during first KRBTGT password reset: $_" "ERROR"
    exit 1
}

Write-Log "Waiting 20 seconds before another reset. letting things settle" "INFO"
start-sleep -Seconds 20


# 3. Second KRBTGT password reset
try {
    Write-Log "Performing second KRBTGT password reset..."
    
    # Generate a different complex password
    $newPassword2 = New-ComplexPassword -Length 24
    $securePassword2 = ConvertTo-SecureString -AsPlainText $newPassword2 -Force
    
    # Reset the KRBTGT password again
    Set-ADAccountPassword -Identity $krbtgtAccount -Reset -NewPassword $securePassword2
    
    Write-Log "Second KRBTGT password reset completed successfully" "SUCCESS"
} catch {
    Write-Log "Failed during second KRBTGT password reset: $_" "ERROR"
    exit 1
}

Write-Log "Golden Ticket mitigation process completed successfully"
Write-Log "All existing Kerberos tickets are now invalidated"
Write-Log "Users will need to log out and log back in to receive new valid tickets"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "                 GOLDEN TICKET MITIGATION SUMMARY                 " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "KRBTGT password reset: SUCCESSFUL" -ForegroundColor Green
Write-Host "Administrator password reset: SUCCESSFUL" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
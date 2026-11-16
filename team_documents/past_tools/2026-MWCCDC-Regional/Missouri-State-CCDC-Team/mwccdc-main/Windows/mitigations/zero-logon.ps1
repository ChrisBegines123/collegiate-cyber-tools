# ==============================================================================
# Script Name : zero-logon.ps1
# Description : Apply Zerologon vulnerability mitigations.
# Author      : Tyler Olson
# Version     : 1.0
# ==============================================================================

# Adapted from SEMO-Cyber Thanks yall

# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\zero-logon$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

write-Log "Starting Zerologon mitigation process" "INFO"

# Harden Netlogon function
function Harden-Netlogon {
    $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
    $ValueName = "FullSecureChannelProtection"
    $NewValue = 1

    if (-not (Test-Path $RegistryPath)) {
        Write-Log "Registry path does not exist: $RegistryPath" "ERROR"
        return
    }

    Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $NewValue -Force
    Write-Log "Successfully hardened Netlogon (Zerologon fix applied)" "SUCCESS"
}

Harden-Netlogon
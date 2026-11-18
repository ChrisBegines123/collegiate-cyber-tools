# ==============================================================================
# Script Name : disableLegacyProtocols.ps1
# Description : Disables the legacy protocols that are used in AD for more
#               Secure configuration versions 
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.0
# ==============================================================================
#   - Bad bad SMB 1. Mitigates Eternal Blue and other SMBv1 attacks.
# ==============================================================================

$LogDir = "C:\Logs"
$LogFile = "$LogDir\ADHardening_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

try {
    # Disable SMBv1
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
    
    # Set secure SMB settings
    Set-SmbServerConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force
    
    # Disable LLMNR
    $registryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient"
    if (!(Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }
    New-ItemProperty -Path $registryPath -Name "EnableMulticast" -Value 0 -PropertyType DWORD -Force | Out-Null
    
    # Disable NetBIOS over TCP/IP (via registry for all interfaces)
    $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE
    $adapters | ForEach-Object {
        $_.SetTcpipNetbios(2) | Out-Null
    }
    
    # Restrict NTLM
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    Set-ItemProperty -Path $registryPath -Name "LmCompatibilityLevel" -Value 5 -Type DWORD
    
    # Enable SMB Encryption
    Set-SmbServerConfiguration -EncryptData $true -Force
    
    Write-Log "Legacy protocols disabled successfully" "SUCCESS"
}
catch {
    Write-Log "Error disabling legacy protocols: $_" "ERROR"
}
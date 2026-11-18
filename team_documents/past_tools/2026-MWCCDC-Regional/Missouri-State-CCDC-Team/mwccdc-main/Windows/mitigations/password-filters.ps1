# ==============================================================================
# Script Name : .\password-filters.ps1
# Description : Monitors for password filters
# Author      : Tyler Olson
# Version     : 1.0
# ==============================================================================
# Usage       : .\password-filters.ps1 
# ==============================================================================
# So this originated from CCDC. I know this clues red team to it. oh well
# https://www.youtube.com/watch?v=DhP2Hw-6DgY&t=529s


# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\mitigation$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

Write-Log "Starting password filter mitigation process" "INFO"

# Look at the regstry key responsible for password filters
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
try {
    $passwordFilters = Get-ItemProperty -Path $regPath -Name "Notification Packages"
    if ($passwordFilters.NotificationPackages) {
        Write-Log "Current password filters: $($passwordFilters.NotificationPackages -join ', ')" "INFO"

        # Take a sha 256 hash of each dll located in the hive
        foreach ($filter in $passwordFilters.NotificationPackages) {
            $dllPath = "C:\Windows\System32\$filter.dll"
            if (Test-Path $dllPath) {
                $hash = Get-FileHash -Path $dllPath -Algorithm SHA256
                Write-Log "Hash for ${filter}: $($hash.Hash)" "INFO"
            } else {
                Write-Log "DLL not found: $dllPath" "WARNING"
        }
}
        
        Write-Log "Printed out all file filters w? hashes." "SUCCESS"
    }
    else {
        Write-Log "No password filters found." "INFO"
    }
}
catch {
    Write-Log "Failed for some reason. likely due to perms: $_" "ERROR"
}



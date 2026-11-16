# ==============================================================================
# Script Name : .\tools.ps1
# Description : Various utility functions for system administration.
# Author      : Tyler Olson
# Version     : 1.0
# ==============================================================================
# Usage       : .\tools.ps1 
# ==============================================================================

# Variables for this script
$sysinternals_downloadUrl = "https://download.sysinternals.com/files/SysinternalsSuite.zip"
$sysinternalsPath = "C:\Tools\Sysinternals"

# Log file setup
$LogDir = "C:\Logs"
$LogFile = "$LogDir\tools$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

function Test-Environment {
    Write-Log "Validating Environment" "Info"

    # Check if running as Administrator
    #$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    #if (-not $isAdmin) {
    #    Write-Log "This script must be run as Administrator." "ERROR"
    #    return $false
    #}

    # Check if sysinternals already in path
    if ($env:PATH -like "*C:\Tools\Sysinternals*") {
        Write-Log "Sysinternals Suite is already installed and in PATH." "SUCCESS"
        return $false
    }

    # Check if sysinternals already peresent
    if (Test-Path $sysinternalsPath) {
        Write-Log "Sysinternals Suite is already installed at $sysinternalsPath." "SUCCESS"
        return $false
    }

    # Return true if all checks passed
    return $true
}

# Validate the environment before proceeding
if (-not (Test-Environment)) {
    Write-Log "Environment validation failed. Exiting script." "ERROR"
    exit 1
}

# Create required directories
if (-not (Test-Path $sysinternalsPath)) {
    New-Item -Path $sysinternalsPath -ItemType Directory -Force | Out-Null
    Write-Log "Created directory: $sysinternalsPath" "SUCCESS"
}

# Install the sysinternals suite to C:\Tools\Sysinternals
$ProgressPreference = 'SilentlyContinue' # Hide progress bar to speed up download
Invoke-WebRequest -Uri $sysinternals_downloadUrl -OutFile "$env:TEMP\SysinternalsSuite.zip"
Expand-Archive -Path "$env:TEMP\SysinternalsSuite.zip" -DestinationPath "$sysinternalsPath" -Force
Write-Log "Sysinternals Suite downloaded and extracted to C:\Tools\Sysinternals" "SUCCESS"

# add a new environment variable to thhe path with the sysinternals path
$CurrentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

# only add if not already there
if ($CurrentPath -notlike "*$sysinternalsPath*") {
    $NewPath = "$CurrentPath;$sysinternalsPath"
    [System.Environment]::SetEnvironmentVariable("Path", $NewPath, [System.EnvironmentVariableTarget]::Machine)
    Write-Log "Added Sysinternals Suite to system PATH." "SUCCESS"
}
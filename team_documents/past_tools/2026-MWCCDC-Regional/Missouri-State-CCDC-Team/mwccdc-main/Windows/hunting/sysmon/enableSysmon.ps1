<#
.SYNOPSIS
    Sometimes I'm a little too lazy to pull down the config and start sysmon myself, might as well automate it quickly!

.DESCRIPTION
    Runs a little script to get sysmon running for sp33d

.EXAMPLE
    PS> .\enableSysmon.ps1

.NOTES
    You should run this AFTER installing all the sysinternal tools
#>

param(
    [Parameter()]
    [string]$SysmonPath = "C:\Tools\Sysinternals",
    
    [Parameter()]
    [string]$LogDir = "C:\Logs\Sysmon",

    [Parameter()]
    [string]$configPath = ".\sysmonconfig-export-block.xml",

    [Parameter()]
    [string]$ConfigUrl = "https://raw.githubusercontent.com/NextronSystems/sysmon-config/refs/heads/master/sysmonconfig-export-block.xml"
)

$LogFile = "$LogDir\SYSMON_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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
    Write-Log "Validating environment and prerequisites" "INFO"
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "Script must be run as Administrator" "ERROR"
        return $false
    }
    
    # Check if Sysmon exists
    $sysmonExe = Join-Path $SysmonPath "sysmon.exe"
    if (-not (Test-Path $sysmonExe)) {
        Write-Log "Sysmon.exe not found at $sysmonExe" "ERROR"
        Write-Log "Please install Sysinternals tools first or specify the correct path" "ERROR"
        return $false
    }
    
    Write-Log "Sysmon found at $sysmonExe" "SUCCESS"
    
    Write-Log "Environment validation completed successfully" "SUCCESS"
    return $true
}

# Download Sysmon configuration
function Get-SysmonConfig {
    Write-Log "Downloading Sysmon configuration from $ConfigUrl" "INFO"
    
    if (-not (Test-Path $configPath)) {
        try {
            Invoke-WebRequest -Uri $ConfigUrl -OutFile $configPath -ErrorAction Stop
            
            if (Test-Path $configPath) {
                Write-Log "Configuration downloaded successfully to $configPath" "SUCCESS"
                return $configPath
            }
            else {
                Write-Log "Configuration file was not created" "ERROR"
                return $null
            }
        }
        catch {
            Write-Log "Failed to download Sysmon configuration: $_" "ERROR"
            return $null
        }
    }
    else {
        Write-Log "Configuration file already downloaded to $configPath, proceeding" "SUCCESS"
        return $configPath
    }
}

# Install or update Sysmon
function Install-Sysmon {
    param (
        [string]$ConfigFile
    )
    
    Write-Log "Installing/updating Sysmon with configuration" "INFO"
    
    $sysmonExe = Join-Path $SysmonPath "sysmon.exe"
    
    # Check if Sysmon is already installed
    $sysmonService = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
    
    if ($sysmonService) {
        Write-Log "Sysmon is already installed. Updating configuration..." "INFO"
        $action = "-c"
    }
    else {
        Write-Log "Installing Sysmon for the first time..." "INFO"
        $action = "-i"
    }
    
    try {
        # Run Sysmon with the config
        $arguments = "-accepteula $action `"$ConfigFile`""
        $process = Start-Process -FilePath $sysmonExe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Sysmon configured successfully" "SUCCESS"
            
            # Verify service is running
            $sysmonService = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
            if ($sysmonService -and $sysmonService.Status -eq "Running") {
                Write-Log "Sysmon service is running" "SUCCESS"
                return $true
            }
            else {
                Write-Log "Sysmon service is not running" "WARNING"
                return $false
            }
        }
        else {
            Write-Log "Sysmon installation/configuration failed with exit code: $($process.ExitCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Error running Sysmon: $_" "ERROR"
        return $false
    }
}

# Main execution
function Start-SysmonSetup {
    $startTime = Get-Date
    
    Write-Log "Starting Sysmon setup process" "INFO"
    
    # Validate environment
    if (-not (Test-Environment)) {
        Write-Log "Environment validation failed. Aborting setup." "ERROR"
        return $false
    }
    
    # Download configuration
    $configFile = Get-SysmonConfig
    if (-not $configFile) {
        Write-Log "Failed to download configuration. Aborting setup." "ERROR"
        return $false
    }
    
    # Install/configure Sysmon
    $success = Install-Sysmon -ConfigFile $configFile
    
    # Calculate execution time
    $endTime = Get-Date
    $executionTime = ($endTime - $startTime).ToString()
    
    if ($success) {
        Write-Log "Sysmon setup completed successfully" "SUCCESS"
    }
    else {
        Write-Log "Sysmon setup completed with errors" "WARNING"
    }
    
    Write-Log "Total execution time: $executionTime" "INFO"
    
    return $success
}

# Start the setup process
$result = Start-SysmonSetup

# Display summary
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "                    SYSMON SETUP COMPLETE                         " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

if ($result) {
    Write-Host "Status: " -ForegroundColor White -NoNewline
    Write-Host "SUCCESS" -ForegroundColor Green
    Write-Host ""
    Write-Host "Sysmon is now running with the Nextron configuration" -ForegroundColor White
    Write-Host "Configuration: $configPath" -ForegroundColor White
}
else {
    Write-Host "Status: " -ForegroundColor White -NoNewline
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please check the log file for details" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
# ==============================================================================
# Script Name : safe-remoting.ps1
# Description : CCDC-safe remote access hardening:
#               - Backs up firewall + service states
#               - Restricts RDP/WinRM/SSH inbound to allowed management IPs/subnets
#               - Optionally disables high-risk services (OFF by default)
# Author      : CCDC Safe Variant (final)
# Version     : 1.1
# Usage       : .\safe-remoting.ps1 -AllowedSources @("10.0.0.0/8","192.168.1.50") -DisableServices:$false
# Notes       : Run as Administrator
# ==============================================================================

param(
    [Parameter()]
    [string[]]$AllowedSources = @("10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"),

    [Parameter()]
    [switch]$DisableServices = $false
)

# ---------------------------
# Log setup
# ---------------------------
$LogDir  = "C:\Logs"
$LogFile = Join-Path $LogDir ("RemotingLockdown_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","SUCCESS")][string]$Level="INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    switch ($Level) {
        "INFO"    { Write-Host $line -ForegroundColor Gray }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
    }
}

Write-Log "Starting SAFE remoting lockdown (firewall restriction first; no service nuking by default)" "INFO"

# Admin check
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Administrator privileges required." "ERROR"
    exit 1
}

# Detect if current session is RDP (warn only)
$sessionName = $env:SESSIONNAME
if ($sessionName -like "RDP-Tcp*") {
    Write-Log "Detected current session is RDP ($sessionName). This script will NOT disable RDP service; firewall rules will be tightened." "WARNING"
} else {
    Write-Log "Current session: $sessionName" "INFO"
}

# ---------------------------
# Backups
# ---------------------------
try {
    $backupDir = "C:\Backup\SecurityConfig"
    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }

    $fwBackup = Join-Path $backupDir ("FirewallRules_{0}.wfw" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    netsh advfirewall export "$fwBackup" | Out-Null
    Write-Log "Firewall rules backed up to $fwBackup" "SUCCESS"

    $svcBackup = Join-Path $backupDir ("Services_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Get-Service | Select-Object Name, Status, StartType | Export-Csv -Path $svcBackup -NoTypeInformation
    Write-Log "Service states backed up to $svcBackup" "SUCCESS"
}
catch {
    Write-Log "Backup step failed (continuing): $($_.Exception.Message)" "WARNING"
}

# ---------------------------
# Capability check: NetSecurity cmdlets
# ---------------------------
$HasNetSecurity = $false
try {
    if (Get-Command -Name New-NetFirewallRule -ErrorAction Stop) { $HasNetSecurity = $true }
} catch { $HasNetSecurity = $false }

if ($HasNetSecurity) {
    Write-Log "NetSecurity cmdlets detected (New-NetFirewallRule). Using PowerShell firewall rules." "INFO"
} else {
    Write-Log "NetSecurity cmdlets NOT found. Falling back to netsh advfirewall rules." "WARNING"
}

# ---------------------------
# Helper: Create/replace firewall rule
# ---------------------------
function Set-RestrictiveRule {
    param(
        [Parameter(Mandatory=$true)][string]$RuleName,
        [Parameter(Mandatory=$true)][string]$DisplayGroup,
        [Parameter(Mandatory=$true)][string]$Protocol,
        [Parameter(Mandatory=$true)][int]$LocalPort
    )

    $remote = ($AllowedSources -join ",")
    $allowName = $RuleName
    $blockName = "$RuleName (Block Others)"

    try {
        if ($script:HasNetSecurity) {
            # Remove existing rules (idempotent)
            Get-NetFirewallRule -DisplayName $allowName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Get-NetFirewallRule -DisplayName $blockName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

            # Allow from AllowedSources
            New-NetFirewallRule `
                -DisplayName $allowName `
                -Group $DisplayGroup `
                -Direction Inbound `
                -Action Allow `
                -Enabled True `
                -Profile Any `
                -Protocol $Protocol `
                -LocalPort $LocalPort `
                -RemoteAddress $AllowedSources | Out-Null

            Write-Log "ALLOW rule set: $allowName | Port $LocalPort/$Protocol | RemoteAddress: $($AllowedSources -join ',')" "SUCCESS"

            # Block everyone else
            New-NetFirewallRule `
                -DisplayName $blockName `
                -Group $DisplayGroup `
                -Direction Inbound `
                -Action Block `
                -Enabled True `
                -Profile Any `
                -Protocol $Protocol `
                -LocalPort $LocalPort `
                -RemoteAddress Any | Out-Null

            Write-Log "BLOCK rule set: $blockName | Port $LocalPort/$Protocol | RemoteAddress: Any" "SUCCESS"
        }
        else {
            # netsh fallback (delete by name if exists)
            netsh advfirewall firewall delete rule name="$allowName"  | Out-Null
            netsh advfirewall firewall delete rule name="$blockName"  | Out-Null

            # Allow rule
            netsh advfirewall firewall add rule `
                name="$allowName" `
                dir=in action=allow `
                protocol=$Protocol localport=$LocalPort `
                remoteip="$remote" `
                profile=any enable=yes | Out-Null

            # Block rule
            netsh advfirewall firewall add rule `
                name="$blockName" `
                dir=in action=block `
                protocol=$Protocol localport=$LocalPort `
                remoteip=any `
                profile=any enable=yes | Out-Null

            Write-Log "ALLOW/BLOCK rules set via netsh: $allowName / $blockName | Port $LocalPort/$Protocol | Allowed: $remote" "SUCCESS"
        }
    }
    catch {
        # FIXED: ${RuleName} avoids $RuleName: parsing error
        Write-Log "Failed to set firewall rules for ${RuleName}: $($_.Exception.Message)" "ERROR"
    }
}

# ---------------------------
# Tighten common remoting ports (firewall-level)
# ---------------------------
Set-RestrictiveRule -RuleName "CCDC - Restrict RDP"        -DisplayGroup "CCDC Remoting" -Protocol TCP -LocalPort 3389
Set-RestrictiveRule -RuleName "CCDC - Restrict WinRM HTTP" -DisplayGroup "CCDC Remoting" -Protocol TCP -LocalPort 5985
Set-RestrictiveRule -RuleName "CCDC - Restrict WinRM HTTPS" -DisplayGroup "CCDC Remoting" -Protocol TCP -LocalPort 5986
Set-RestrictiveRule -RuleName "CCDC - Restrict SSH"        -DisplayGroup "CCDC Remoting" -Protocol TCP -LocalPort 22

Write-Log "Note: WMI uses dynamic RPC ports; not disabling WMI rules here to avoid breaking monitoring/management." "INFO"

# ---------------------------
# Optional: disable high-risk services (OFF by default)
# ---------------------------
if ($DisableServices) {
    Write-Log "DisableServices=ON: stopping/disabling selected remote services (use with caution)" "WARNING"

    $servicesToDisable = @(
        "RemoteRegistry",
        "WinRM",
        "sshd",
        "RemoteAccess"
    )

    foreach ($svcName in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Service disabled: $svcName" "SUCCESS"
            } else {
                Write-Log "Service not found (skipped): $svcName" "INFO"
            }
        } catch {
            # FIXED: ${svcName} avoids $svcName: parsing error
            Write-Log "Failed to disable service ${svcName}: $($_.Exception.Message)" "WARNING"
        }
    }

    # PowerShell Remoting (will affect WinRM)
    try {
        Disable-PSRemoting -Force -ErrorAction SilentlyContinue
        Write-Log "PowerShell Remoting disabled" "SUCCESS"
    } catch {
        Write-Log "Failed to disable PowerShell Remoting: $($_.Exception.Message)" "WARNING"
    }
} else {
    Write-Log "DisableServices=OFF: services not disabled; only firewall restriction applied." "INFO"
}

Write-Log "SAFE remoting lockdown complete." "SUCCESS"
Write-Log "Log file: $LogFile" "INFO"

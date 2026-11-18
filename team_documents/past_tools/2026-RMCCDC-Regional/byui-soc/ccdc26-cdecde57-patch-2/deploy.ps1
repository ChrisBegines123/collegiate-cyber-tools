#=============================================================================
# CCDC26 All-in-One Deployment Script for Windows
#=============================================================================
# Master entry point for the CCDC26 toolkit on Windows systems
# Detects environment and provides appropriate options
#
# Usage:
#   .\deploy.ps1              # Interactive menu
#   .\deploy.ps1 -Quick       # Quick local harden
#   .\deploy.ps1 -Help        # Show help
#=============================================================================

param(
    [switch]$Quick,
    [switch]$Help
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Continue"

#=============================================================================
# ENVIRONMENT DETECTION
#=============================================================================
function Get-Environment {
    $script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $cs = Get-WmiObject -Class Win32_ComputerSystem
    
    $script:OSName = $os.Caption
    $script:IsDomainController = (Get-WmiObject -Query "SELECT * FROM Win32_OperatingSystem WHERE ProductType='2'") -ne $null
    $script:IsDomainJoined = $cs.PartOfDomain
    $script:ComputerName = $env:COMPUTERNAME
    
    # Check for IIS
    $script:HasIIS = (Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue) -ne $null
    
    # Check for Splunk Forwarder
    $script:HasSplunk = Test-Path "C:\Program Files\SplunkUniversalForwarder"
}

#=============================================================================
# BANNER
#=============================================================================
function Show-Banner {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "           CCDC26 Windows Toolkit           " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "OS:          " -NoNewline; Write-Host $OSName -ForegroundColor Green
    Write-Host "Computer:    " -NoNewline; Write-Host $ComputerName -ForegroundColor Green
    Write-Host "Admin:       " -NoNewline; Write-Host $(if ($IsAdmin) { "Yes" } else { "No" }) -ForegroundColor $(if ($IsAdmin) { "Green" } else { "Red" })
    Write-Host "Domain:      " -NoNewline; Write-Host $(if ($IsDomainJoined) { "Yes" } else { "No" }) -ForegroundColor Green
    Write-Host "DC:          " -NoNewline; Write-Host $(if ($IsDomainController) { "Yes" } else { "No" }) -ForegroundColor $(if ($IsDomainController) { "Yellow" } else { "Green" })
    Write-Host "IIS:         " -NoNewline; Write-Host $(if ($HasIIS) { "Installed" } else { "Not installed" }) -ForegroundColor Green
    Write-Host "Splunk:      " -NoNewline; Write-Host $(if ($HasSplunk) { "Installed" } else { "Not installed" }) -ForegroundColor Green
    Write-Host ""
}

#=============================================================================
# REQUIRE ADMIN
#=============================================================================
function Require-Admin {
    if (-not $IsAdmin) {
        Write-Host "[ERROR] This script must be run as Administrator" -ForegroundColor Red
        Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        exit 1
    }
}

#=============================================================================
# HARDENING MENU
#=============================================================================
function Show-HardeningMenu {
    Write-Host ""
    Write-Host "=== Hardening Options ===" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "1) Quick Harden (Full-Harden.ps1 with defaults)"
    Write-Host "2) Interactive Harden (choose options)"
    if ($IsDomainController) {
        Write-Host "3) AD Harden (Domain Controller specific)" -ForegroundColor Yellow
    }
    if ($HasIIS) {
        Write-Host "4) IIS Harden (Web server specific)" -ForegroundColor Yellow
    }
    Write-Host "5) Enable Advanced Auditing"
    Write-Host "6) Configure Firewall"
    Write-Host ""
    Write-Host "0) Back to main menu"
    Write-Host ""
    
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" {
            Require-Admin
            Write-Host "`n=== Running Quick Harden ===" -ForegroundColor Magenta
            & "$ScriptDir\windows-scripts\hardening\Full-Harden.ps1" -q
        }
        "2" {
            Require-Admin
            Write-Host "`n=== Interactive Hardening ===" -ForegroundColor Magenta
            & "$ScriptDir\windows-scripts\hardening\Full-Harden.ps1"
        }
        "3" {
            if ($IsDomainController) {
                Require-Admin
                Write-Host "`n=== AD Hardening ===" -ForegroundColor Magenta
                & "$ScriptDir\windows-scripts\hardening\AD-Harden.ps1"
            }
            else {
                Write-Host "[INFO] This system is not a Domain Controller" -ForegroundColor Yellow
            }
        }
        "4" {
            if ($HasIIS) {
                Require-Admin
                Write-Host "`n=== IIS Hardening ===" -ForegroundColor Magenta
                if (Test-Path "$ScriptDir\windows-scripts\hardening\IIS-Harden.ps1") {
                    & "$ScriptDir\windows-scripts\hardening\IIS-Harden.ps1"
                }
                else {
                    Write-Host "[INFO] IIS hardening script not yet implemented" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "[INFO] IIS is not installed on this system" -ForegroundColor Yellow
            }
        }
        "5" {
            Require-Admin
            Write-Host "`n=== Enabling Advanced Auditing ===" -ForegroundColor Magenta
            & "$ScriptDir\windows-scripts\hardening\lib\auditing.ps1"
        }
        "6" {
            Require-Admin
            Write-Host "`n=== Firewall Configuration ===" -ForegroundColor Magenta
            Write-Host "Common CCDC ports: 22 (SSH), 53 (DNS), 80 (HTTP), 443 (HTTPS), 3389 (RDP)" -ForegroundColor Gray
            Write-Host "AD ports: 88, 135, 389, 445, 636, 3268, 3269" -ForegroundColor Gray
            Write-Host ""
            $ports = Read-Host "Enter ports to allow (comma-separated)"
            
            if ($ports -eq "default") {
                $portList = @(80, 443, 3389)
            }
            elseif (-not [string]::IsNullOrEmpty($ports)) {
                $portList = $ports -split ',' | ForEach-Object { [int]$_.Trim() }
            }
            
            # Enable firewall
            netsh advfirewall set allprofiles state on
            
            foreach ($port in $portList) {
                netsh advfirewall firewall add rule name="CCDC - TCP Inbound $port" dir=in action=allow protocol=TCP localport=$port
                Write-Host "[OK] Added rule for port $port" -ForegroundColor Green
            }
        }
        "0" {
            return
        }
        default {
            Write-Host "[ERROR] Invalid option" -ForegroundColor Red
        }
    }
}

#=============================================================================
# TOOLS MENU
#=============================================================================
function Show-ToolsMenu {
    Write-Host ""
    Write-Host "=== Tools ===" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "1) Deploy Splunk Forwarder"
    Write-Host "2) Password Generator (Zulu)"
    Write-Host "3) User Audit"
    Write-Host "4) Service Audit"
    Write-Host "5) Scheduled Task Audit"
    Write-Host ""
    Write-Host "0) Back to main menu"
    Write-Host ""
    
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" {
            Require-Admin
            Write-Host "`n=== Deploying Splunk Forwarder ===" -ForegroundColor Magenta
            Write-Host "Forwarding to competition Splunk server: 172.20.242.20:9997" -ForegroundColor Cyan
            
            & "$ScriptDir\windows-scripts\Install-SplunkForwarder.ps1" -Quick
        }
        "2" {
            Write-Host "`n=== Password Generator ===" -ForegroundColor Magenta
            & "$ScriptDir\windows-scripts\hardening\lib\passwords.ps1"
        }
        "3" {
            Write-Host "`n=== User Audit ===" -ForegroundColor Magenta
            
            Write-Host "`nEnabled Users:" -ForegroundColor Green
            Get-LocalUser | Where-Object { $_.Enabled } | Format-Table Name, LastLogon, PasswordLastSet
            
            Write-Host "Disabled Users:" -ForegroundColor Red
            Get-LocalUser | Where-Object { -not $_.Enabled } | Format-Table Name
            
            Write-Host "Administrators:" -ForegroundColor Yellow
            Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Format-Table Name, ObjectClass
        }
        "4" {
            Write-Host "`n=== Service Audit ===" -ForegroundColor Magenta
            Write-Host "Running services:" -ForegroundColor Yellow
            Get-Service | Where-Object { $_.Status -eq 'Running' } | Sort-Object DisplayName | Format-Table Name, DisplayName, StartType
        }
        "5" {
            Write-Host "`n=== Scheduled Task Audit ===" -ForegroundColor Magenta
            Write-Host "Active scheduled tasks:" -ForegroundColor Yellow
            Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } | Format-Table TaskName, TaskPath, State
        }
        "0" {
            return
        }
        default {
            Write-Host "[ERROR] Invalid option" -ForegroundColor Red
        }
    }
}

#=============================================================================
# QUICK HARDEN
#=============================================================================
function Invoke-QuickHarden {
    Require-Admin
    
    Write-Host ""
    Write-Host "=== QUICK HARDEN MODE ===" -ForegroundColor Magenta
    Write-Host ""
    
    $startTime = Get-Date
    
    # Run full hardening with quick flag
    & "$ScriptDir\windows-scripts\hardening\Full-Harden.ps1" -q
    
    # If DC, also run AD hardening
    if ($IsDomainController) {
        Write-Host ""
        Write-Host "Detected Domain Controller - Running AD Hardening..." -ForegroundColor Yellow
        & "$ScriptDir\windows-scripts\hardening\AD-Harden.ps1" -q
    }
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Host ""
    Write-Host "=== Quick Harden Complete ===" -ForegroundColor Green
    Write-Host "Duration: $([math]::Round($duration, 1)) seconds" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure firewall ports" -ForegroundColor Gray
    Write-Host "  2. Change all user passwords" -ForegroundColor Gray
    Write-Host "  3. Deploy Splunk forwarder" -ForegroundColor Gray
    Write-Host ""
}

#=============================================================================
# MAIN MENU
#=============================================================================
function Show-MainMenu {
    while ($true) {
        Clear-Host
        Show-Banner
        
        Write-Host "Main Menu:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1) Hardening Options"
        Write-Host "2) Tools & Utilities"
        Write-Host "3) View README"
        Write-Host ""
        Write-Host "q) Quit"
        Write-Host ""
        
        $choice = Read-Host "Select option"
        
        switch ($choice) {
            "1" { Show-HardeningMenu }
            "2" { Show-ToolsMenu }
            "3" {
                if (Test-Path "$ScriptDir\README.md") {
                    Get-Content "$ScriptDir\README.md" | Out-Host -Paging
                }
                else {
                    Write-Host "README not found" -ForegroundColor Yellow
                }
            }
            "q" { 
                Write-Host "Goodbye!" -ForegroundColor Cyan
                exit 0 
            }
            "Q" { 
                Write-Host "Goodbye!" -ForegroundColor Cyan
                exit 0 
            }
            default {
                Write-Host "[ERROR] Invalid option" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        Read-Host "Press Enter to continue..."
    }
}

#=============================================================================
# HELP
#=============================================================================
function Show-Help {
    Write-Host ""
    Write-Host "CCDC26 Toolkit - Windows Deployment Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\deploy.ps1 [option]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  (none)     Interactive menu"
    Write-Host "  -Quick     Run quick hardening (Full-Harden + AD-Harden if DC)"
    Write-Host "  -Help      Show this help"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\deploy.ps1           # Interactive menu"
    Write-Host "  .\deploy.ps1 -Quick    # Quick harden this system"
    Write-Host ""
}

#=============================================================================
# MAIN
#=============================================================================

# Initialize environment
Get-Environment

# Handle command line options
if ($Help) {
    Show-Help
    exit 0
}

if ($Quick) {
    Invoke-QuickHarden
    exit 0
}

# Default: interactive menu
Show-MainMenu

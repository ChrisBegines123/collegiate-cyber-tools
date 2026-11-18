#Requires -RunAsAdministrator
<#
.SYNOPSIS
    CCDC26 - Splunk Server Setup for Windows
    
.DESCRIPTION
    Configures a Windows Splunk server to receive forwarder data.
    Creates required indexes and enables the receiving port.
    
    Run this on the Splunk SERVER, not the forwarders.
    
.EXAMPLE
    .\Setup-SplunkServer.ps1
    Interactive menu
    
.EXAMPLE
    .\Setup-SplunkServer.ps1 -Quick -AdminUser admin -AdminPassword "changeme"
    Quick setup with credentials
    
.EXAMPLE
    .\Setup-SplunkServer.ps1 -CreateIndexes -AdminUser admin -AdminPassword "changeme"
    Create indexes only
#>

param(
    [switch]$Quick,
    [switch]$CreateIndexes,
    [switch]$EnableReceiver,
    [switch]$ConfigureFirewall,
    [switch]$Status,
    [string]$AdminUser = "admin",
    [string]$AdminPassword,
    [string]$SplunkHome = "C:\Program Files\Splunk"
)

# Configuration
$SPLUNK_PORT = 9997
$SPLUNK_EXE = Join-Path $SplunkHome "bin\splunk.exe"

# Indexes that match inputs.conf on forwarders
# Linux indexes
$LINUX_INDEXES = @(
    "linux-security"   # auth.log, secure, audit.log, fail2ban
    "linux-os"         # syslog, messages, kern.log, cron
    "linux-web"        # apache, httpd, nginx logs
    "linux-database"   # mysql, mariadb, postgresql logs
    "linux-mail"       # mail.log, maillog
    "linux-dns"        # named, bind logs
    "linux-ftp"        # vsftpd, proftpd logs
)

# Windows indexes (granular)
$WINDOWS_INDEXES = @(
    "windows-security"     # Security EventLog
    "windows-system"       # System EventLog
    "windows-application"  # Application EventLog
    "windows-powershell"   # PowerShell logs
    "windows-sysmon"       # Sysmon operational logs
    "windows-dns"          # DNS Server EventLog
)

# Combined for iteration
$INDEXES = $LINUX_INDEXES + $WINDOWS_INDEXES

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor White
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Get-Credentials {
    if ([string]::IsNullOrEmpty($script:AdminPassword)) {
        $cred = Get-Credential -UserName $AdminUser -Message "Enter Splunk admin credentials"
        $script:AdminUser = $cred.UserName
        $script:AdminPassword = $cred.GetNetworkCredential().Password
    }
    
    if ([string]::IsNullOrEmpty($script:AdminPassword)) {
        Write-Error2 "Password cannot be empty"
        exit 1
    }
}

function Test-SplunkInstalled {
    if (-not (Test-Path $SPLUNK_EXE)) {
        Write-Error2 "Splunk not found at $SplunkHome"
        Write-Error2 "Use -SplunkHome to specify the installation path"
        exit 1
    }
    
    # Check if running
    $status = & $SPLUNK_EXE status 2>&1
    if ($status -notmatch "splunkd is running") {
        Write-Warn "Splunk is not running. Starting..."
        & $SPLUNK_EXE start --accept-license --answer-yes --no-prompt
        Start-Sleep -Seconds 5
    }
    
    Write-Success "Splunk is running"
}

function New-SplunkIndexes {
    Write-Header "Creating Indexes"
    
    $authArg = "-auth ${script:AdminUser}:${script:AdminPassword}"
    
    foreach ($idx in $INDEXES) {
        Write-Info "Creating index: $idx"
        
        # Check if exists
        $existing = & $SPLUNK_EXE list index $authArg.Split(' ') 2>&1
        if ($existing -match "^$idx$") {
            Write-Info "  Index '$idx' already exists, skipping"
        } else {
            $result = & $SPLUNK_EXE add index $idx $authArg.Split(' ') 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  Created index: $idx"
            } else {
                Write-Warn "  Failed to create index: $idx (may already exist)"
            }
        }
    }
    
    Write-Host ""
    Write-Info "Index summary:"
    $existing = & $SPLUNK_EXE list index $authArg.Split(' ') 2>&1
    foreach ($idx in $INDEXES) {
        if ($existing -match $idx) {
            Write-Host "  - $idx" -ForegroundColor Green
        }
    }
}

function Enable-SplunkReceiver {
    Write-Header "Enabling Receiver Port"
    
    $authArg = "-auth ${script:AdminUser}:${script:AdminPassword}"
    
    Write-Info "Enabling TCP input on port $SPLUNK_PORT..."
    
    # Check if already enabled
    $tcpList = & $SPLUNK_EXE list tcp $authArg.Split(' ') 2>&1
    if ($tcpList -match ":$SPLUNK_PORT") {
        Write-Info "Receiver port $SPLUNK_PORT already enabled"
    } else {
        $result = & $SPLUNK_EXE enable listen $SPLUNK_PORT $authArg.Split(' ') 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Receiver enabled on port $SPLUNK_PORT"
        } else {
            Write-Error2 "Failed to enable receiver port"
            Write-Host $result
        }
    }
    
    # Verify port is listening
    $listening = Get-NetTCPConnection -LocalPort $SPLUNK_PORT -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Write-Success "Port $SPLUNK_PORT is listening"
    } else {
        Write-Warn "Port $SPLUNK_PORT may not be listening yet - Splunk restart may be needed"
    }
}

function Set-SplunkFirewall {
    Write-Header "Firewall Configuration"
    
    Write-Info "Adding Windows Firewall rules..."
    
    # Receiver port
    $rule = Get-NetFirewallRule -DisplayName "Splunk Receiver ($SPLUNK_PORT)" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "Splunk Receiver ($SPLUNK_PORT)" `
            -Direction Inbound -Protocol TCP -LocalPort $SPLUNK_PORT `
            -Action Allow -Profile Any | Out-Null
        Write-Success "Added firewall rule for port $SPLUNK_PORT (receiver)"
    } else {
        Write-Info "Firewall rule for port $SPLUNK_PORT already exists"
    }
    
    # Web UI
    $rule = Get-NetFirewallRule -DisplayName "Splunk Web UI (8000)" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "Splunk Web UI (8000)" `
            -Direction Inbound -Protocol TCP -LocalPort 8000 `
            -Action Allow -Profile Any | Out-Null
        Write-Success "Added firewall rule for port 8000 (Web UI)"
    } else {
        Write-Info "Firewall rule for port 8000 already exists"
    }
    
    # Management port
    $rule = Get-NetFirewallRule -DisplayName "Splunk Management (8089)" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "Splunk Management (8089)" `
            -Direction Inbound -Protocol TCP -LocalPort 8089 `
            -Action Allow -Profile Any | Out-Null
        Write-Success "Added firewall rule for port 8089 (Management)"
    } else {
        Write-Info "Firewall rule for port 8089 already exists"
    }
}

function Get-SplunkStatus {
    Write-Header "Splunk Server Status"
    
    $authArg = "-auth ${script:AdminUser}:${script:AdminPassword}"
    
    Write-Host ""
    Write-Host "Splunk Home: $SplunkHome"
    Write-Host ""
    
    # Service status
    $status = & $SPLUNK_EXE status 2>&1
    if ($status -match "splunkd is running") {
        Write-Success "Splunk service: Running"
    } else {
        Write-Error2 "Splunk service: NOT running"
    }
    
    # Receiver port
    $listening = Get-NetTCPConnection -LocalPort $SPLUNK_PORT -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Write-Success "Receiver port ${SPLUNK_PORT}: Listening"
    } else {
        Write-Warn "Receiver port ${SPLUNK_PORT}: NOT listening"
    }
    
    # Web UI
    $listening = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Write-Success "Web UI port 8000: Listening"
    } else {
        Write-Warn "Web UI port 8000: NOT listening"
    }
    
    Write-Host ""
    Write-Info "Configured indexes:"
    $existing = & $SPLUNK_EXE list index $authArg.Split(' ') 2>&1
    foreach ($idx in $INDEXES) {
        if ($existing -match "^$idx$") {
            Write-Host "  - $idx" -ForegroundColor Green
        }
    }
}

function Start-QuickSetup {
    Write-Header "Quick Setup - Splunk Server"
    
    Get-Credentials
    Test-SplunkInstalled
    New-SplunkIndexes
    Enable-SplunkReceiver
    Set-SplunkFirewall
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Success "Splunk server setup complete!"
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Receiver port: $SPLUNK_PORT"
    
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^127\." } | Select-Object -First 1).IPAddress
    Write-Host "Web UI: https://${ip}:8000"
    Write-Host ""
    Write-Host "Indexes created:"
    foreach ($idx in $INDEXES) {
        Write-Host "  - $idx"
    }
    Write-Host ""
    Write-Host "Forwarders can now send data to this server."
    Write-Host "==========================================" -ForegroundColor Green
}

function Show-Menu {
    Write-Host ""
    Write-Host "Splunk Server Setup" -ForegroundColor Cyan
    Write-Host "==================="
    Write-Host "SPLUNK_HOME: $SplunkHome"
    Write-Host ""
    Write-Host "1) Quick Setup (indexes + receiver + firewall)"
    Write-Host "2) Create indexes only"
    Write-Host "3) Enable receiver port only"
    Write-Host "4) Configure firewall only"
    Write-Host "5) Show status"
    Write-Host "6) Restart Splunk"
    Write-Host "7) Exit"
    Write-Host ""
    
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" { Start-QuickSetup }
        "2" { 
            Get-Credentials
            Test-SplunkInstalled
            New-SplunkIndexes 
        }
        "3" { 
            Get-Credentials
            Test-SplunkInstalled
            Enable-SplunkReceiver 
        }
        "4" { Set-SplunkFirewall }
        "5" { 
            Get-Credentials
            Get-SplunkStatus 
        }
        "6" {
            Write-Info "Restarting Splunk..."
            & $SPLUNK_EXE restart
        }
        "7" { exit 0 }
        default { Write-Error2 "Invalid option" }
    }
}

# Main
if ($Quick) {
    Start-QuickSetup
} elseif ($CreateIndexes) {
    Get-Credentials
    Test-SplunkInstalled
    New-SplunkIndexes
} elseif ($EnableReceiver) {
    Get-Credentials
    Test-SplunkInstalled
    Enable-SplunkReceiver
} elseif ($ConfigureFirewall) {
    Set-SplunkFirewall
} elseif ($Status) {
    Get-Credentials
    Get-SplunkStatus
} else {
    Show-Menu
}

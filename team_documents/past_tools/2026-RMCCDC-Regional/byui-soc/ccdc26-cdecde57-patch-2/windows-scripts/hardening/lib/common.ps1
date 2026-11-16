# CCDC26 Windows Toolkit - Common Utilities
# Source this file in other scripts: . "$PSScriptRoot\lib\common.ps1"

#=============================================================================
# COLORS AND OUTPUT
#=============================================================================
function Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Warn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Error {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Magenta
    Write-Host ""
}

function Finding {
    param([string]$Message)
    Write-Host "[FINDING] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

#=============================================================================
# OS DETECTION
#=============================================================================
function Get-OSInfo {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $cs = Get-WmiObject -Class Win32_ComputerSystem
    
    return @{
        Caption = $os.Caption
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        Architecture = $os.OSArchitecture
        IsServer = $os.Caption -match "Server"
        IsDomainController = (Get-WmiObject -Query "SELECT * FROM Win32_OperatingSystem WHERE ProductType='2'") -ne $null
        IsDomainJoined = $cs.PartOfDomain
        DomainName = $cs.Domain
        ComputerName = $env:COMPUTERNAME
    }
}

function Get-WindowsVersion {
    $build = [System.Environment]::OSVersion.Version.Build
    switch -Regex ($build) {
        "^7601"  { return "7" }
        "^9200"  { return "8" }
        "^9600"  { return "8.1" }
        "^10240" { return "10-1507" }
        "^10586" { return "10-1511" }
        "^14393" { return "10-1607" }  # Server 2016
        "^15063" { return "10-1703" }
        "^16299" { return "10-1709" }
        "^17134" { return "10-1803" }
        "^17763" { return "10-1809" }  # Server 2019
        "^18362" { return "10-1903" }
        "^18363" { return "10-1909" }
        "^19041" { return "10-2004" }
        "^19042" { return "10-20H2" }
        "^19043" { return "10-21H1" }
        "^19044" { return "10-21H2" }
        "^19045" { return "10-22H2" }
        "^20348" { return "2022" }     # Server 2022
        "^22000" { return "11-21H2" }
        "^22621" { return "11-22H2" }
        "^22631" { return "11-23H2" }
        default  { return "Unknown-$build" }
    }
}

#=============================================================================
# ADMIN CHECK
#=============================================================================
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-Administrator)) {
        Error "This script must be run as Administrator"
        exit 1
    }
}

#=============================================================================
# BACKUP FUNCTIONS
#=============================================================================
$script:BackupDir = "C:\CCDC-Toolkit\backups"
$script:LogDir = "C:\CCDC-Toolkit\logs"

function Initialize-Directories {
    if (-not (Test-Path $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    if (-not (Test-Path $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
}

function Backup-Item {
    param(
        [string]$Path,
        [string]$Description = ""
    )
    
    Initialize-Directories
    
    if (Test-Path $Path) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $filename = Split-Path $Path -Leaf
        $backupPath = Join-Path $script:BackupDir "${filename}.${timestamp}.bak"
        
        try {
            Copy-Item -Path $Path -Destination $backupPath -Force -Recurse
            Info "Backed up $Path to $backupPath"
            return $backupPath
        }
        catch {
            Warn "Failed to backup $Path : $_"
            return $null
        }
    }
    else {
        Warn "Path does not exist, cannot backup: $Path"
        return $null
    }
}

function Backup-RegistryKey {
    param(
        [string]$KeyPath,
        [string]$Description = ""
    )
    
    Initialize-Directories
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeName = $KeyPath -replace '[\\:]', '_'
    $backupPath = Join-Path $script:BackupDir "reg_${safeName}_${timestamp}.reg"
    
    try {
        reg export $KeyPath $backupPath /y 2>$null
        if ($LASTEXITCODE -eq 0) {
            Info "Backed up registry key $KeyPath"
            return $backupPath
        }
    }
    catch {
        Warn "Failed to backup registry key $KeyPath"
    }
    return $null
}

#=============================================================================
# LOGGING
#=============================================================================
function Log-Action {
    param([string]$Message)
    
    Initialize-Directories
    $logFile = Join-Path $script:LogDir "actions.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Log-Finding {
    param([string]$Message)
    
    Initialize-Directories
    $logFile = Join-Path $script:LogDir "findings.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Finding $Message
}

#=============================================================================
# USER MANAGEMENT
#=============================================================================
function Get-HumanUsers {
    # Get local users that are likely human accounts (not system accounts)
    Get-LocalUser | Where-Object {
        $_.Enabled -eq $true -and
        $_.Name -notin @('DefaultAccount', 'WDAGUtilityAccount', 'defaultuser0')
    }
}

function Get-AdminUsers {
    # Get users in the Administrators group
    try {
        $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        return $admins
    }
    catch {
        return @()
    }
}

function Get-ADHumanUsers {
    # Get AD users (for domain controllers)
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory
        Get-ADUser -Filter {Enabled -eq $true} -Properties *
    }
    else {
        Warn "ActiveDirectory module not available"
        return @()
    }
}

#=============================================================================
# SERVICE MANAGEMENT
#=============================================================================
function Stop-AndDisable-Service {
    param([string]$ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue
            Success "Disabled service: $ServiceName"
            Log-Action "Disabled service: $ServiceName"
            return $true
        }
        else {
            Info "Service not found: $ServiceName"
            return $false
        }
    }
    catch {
        Warn "Failed to disable service $ServiceName : $_"
        return $false
    }
}

function Start-AndEnable-Service {
    param([string]$ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
            Success "Enabled and started service: $ServiceName"
            Log-Action "Enabled service: $ServiceName"
            return $true
        }
        else {
            Warn "Service not found: $ServiceName"
            return $false
        }
    }
    catch {
        Warn "Failed to enable service $ServiceName : $_"
        return $false
    }
}

#=============================================================================
# FIREWALL HELPERS
#=============================================================================
function Add-FirewallPort {
    param(
        [int]$Port,
        [string]$Protocol = "TCP",
        [string]$Direction = "Inbound",
        [string]$Name = ""
    )
    
    if ([string]::IsNullOrEmpty($Name)) {
        $Name = "CCDC - $Protocol $Direction $Port"
    }
    
    $dir = if ($Direction -eq "Inbound") { "In" } else { "Out" }
    
    try {
        # Remove existing rule if present
        Remove-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
        
        # Add new rule
        New-NetFirewallRule -DisplayName $Name `
            -Direction $dir `
            -Protocol $Protocol `
            -LocalPort $Port `
            -Action Allow `
            -Enabled True | Out-Null
        
        Success "Added firewall rule: $Name"
        return $true
    }
    catch {
        Warn "Failed to add firewall rule for port $Port : $_"
        return $false
    }
}

#=============================================================================
# REGISTRY HELPERS
#=============================================================================
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord"
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        return $true
    }
    catch {
        Warn "Failed to set registry value $Path\$Name : $_"
        return $false
    }
}

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    }
    catch {
        return $null
    }
}

#=============================================================================
# PROMPTS
#=============================================================================
function Prompt-YesNo {
    param(
        [string]$Message,
        [bool]$Default = $false
    )
    
    $defaultText = if ($Default) { "[Y/n]" } else { "[y/N]" }
    
    do {
        $response = Read-Host "$Message $defaultText"
        if ([string]::IsNullOrEmpty($response)) {
            return $Default
        }
        if ($response -ieq 'y' -or $response -ieq 'yes') {
            return $true
        }
        if ($response -ieq 'n' -or $response -ieq 'no') {
            return $false
        }
        Write-Host "Please enter 'y' or 'n'" -ForegroundColor Yellow
    } while ($true)
}

function Prompt-Selection {
    param(
        [string]$Message,
        [string[]]$Options,
        [int]$Default = 0
    )
    
    Write-Host $Message -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Length; $i++) {
        $marker = if ($i -eq $Default) { "*" } else { " " }
        Write-Host "  $marker$($i + 1)) $($Options[$i])"
    }
    
    do {
        $response = Read-Host "Select [1-$($Options.Length)]"
        if ([string]::IsNullOrEmpty($response)) {
            return $Default
        }
        $selection = [int]$response - 1
        if ($selection -ge 0 -and $selection -lt $Options.Length) {
            return $selection
        }
        Write-Host "Invalid selection" -ForegroundColor Yellow
    } while ($true)
}

#=============================================================================
# COMMON PORTS
#=============================================================================
$script:CommonPorts = @{
    22   = "SSH"
    53   = "DNS"
    80   = "HTTP"
    443  = "HTTPS"
    3389 = "RDP"
    445  = "SMB"
    139  = "NetBIOS"
    88   = "Kerberos"
    389  = "LDAP"
    636  = "LDAPS"
    3268 = "Global Catalog"
    3269 = "Global Catalog SSL"
    135  = "RPC Endpoint Mapper"
    464  = "Kerberos Password Change"
    25   = "SMTP"
    110  = "POP3"
    143  = "IMAP"
    587  = "SMTP Submission"
    993  = "IMAPS"
    995  = "POP3S"
    1433 = "MSSQL"
    3306 = "MySQL"
    5432 = "PostgreSQL"
    27017 = "MongoDB"
}

function Get-PortDescription {
    param([int]$Port)
    if ($script:CommonPorts.ContainsKey($Port)) {
        return $script:CommonPorts[$Port]
    }
    return "Unknown"
}

#=============================================================================
# INITIALIZE
#=============================================================================
# Auto-initialize directories when module is loaded
Initialize-Directories

# Export module info
$script:ToolkitVersion = "1.0.0"
$script:ToolkitName = "CCDC26 Windows Toolkit"

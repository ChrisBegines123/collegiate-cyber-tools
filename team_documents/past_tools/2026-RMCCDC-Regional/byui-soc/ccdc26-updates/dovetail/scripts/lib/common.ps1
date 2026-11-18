# CCDC26 Dovetail - Shared Functions
# Source from hunt/IR scripts: . "$PSScriptRoot\lib\common.ps1"

$script:ToolkitRoot = "C:\ccdc26"
$script:LogDir = Join-Path $script:ToolkitRoot "logs"
$script:BackupDir = Join-Path $script:ToolkitRoot "backups"
$script:QuarantineDir = Join-Path $script:ToolkitRoot "quarantine"

function Initialize-Directories {
    @($script:LogDir, $script:BackupDir, $script:QuarantineDir) | ForEach-Object {
        if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    }
}

# ── Color output ──
function Info    { param([string]$Message) Write-Host "[INFO] " -ForegroundColor Blue -NoNewline; Write-Host $Message }
function Success { param([string]$Message) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Warn    { param([string]$Message) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Error   { param([string]$Message) Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $Message }
function Header  { param([string]$Message) Write-Host ""; Write-Host "=== $Message ===" -ForegroundColor Magenta; Write-Host "" }
function Finding { param([string]$Message) Write-Host "[FINDING] " -ForegroundColor Red -NoNewline; Write-Host $Message }

# ── Admin check ──
function Test-Administrator {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-Administrator)) { Error "This script must be run as Administrator"; exit 1 }
}

# ── OS detection ──
function Get-OSInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    return @{
        Caption = $os.Caption; Version = $os.Version; BuildNumber = $os.BuildNumber
        IsServer = $os.Caption -match "Server"
        IsDomainController = $cs.DomainRole -ge 4
        IsDomainJoined = $cs.PartOfDomain; DomainName = $cs.Domain
        ComputerName = $env:COMPUTERNAME
    }
}

# ── Registry backup ──
function Backup-RegistryKey {
    param([string]$KeyPath, [string]$Description = "")
    Initialize-Directories
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $safe = $KeyPath -replace '[\\:]', '_'
    $out = Join-Path $script:BackupDir "reg_${safe}_${ts}.reg"
    reg export $KeyPath $out /y 2>$null | Out-Null
}

# ── Logging ──
function Log-Action {
    param([string]$Message)
    Initialize-Directories
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File (Join-Path $script:LogDir "actions.log") -Append -Encoding UTF8
}

function Log-Finding {
    param([string]$Message)
    Initialize-Directories
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File (Join-Path $script:LogDir "findings.log") -Append -Encoding UTF8
    Finding $Message
}

# ── Prompts ──
function Prompt-YesNo {
    param([string]$Message, [bool]$Default = $false)
    $d = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $r = Read-Host "$Message $d"
    if ([string]::IsNullOrEmpty($r)) { return $Default }
    return ($r -ieq 'y' -or $r -ieq 'yes')
}

# ── Port description ──
function Get-PortDescription {
    param([int]$Port)
    $map = @{22="SSH";53="DNS";80="HTTP";443="HTTPS";3389="RDP";445="SMB";88="Kerberos";
             389="LDAP";636="LDAPS";135="RPC";1433="MSSQL";5985="WinRM";9997="Splunk"}
    if ($map.ContainsKey($Port)) { return $map[$Port] }
    return "Unknown"
}

Initialize-Directories

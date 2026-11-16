#Requires -RunAsAdministrator
# CCDC26 - Kill Attacker Sessions (adapted from Kill-AttackerSession.ps1)
# Enumerates sessions, kills unknowns, disables accounts, blocks IPs.

param(
    [string]$Username,
    [int]$SessionId = -1,
    [string]$SourceIP,
    [switch]$KillUnknown,
    [switch]$DisableAccount,
    [switch]$BlockIP,
    [switch]$Force,
    [string[]]$KnownUsers
)

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$libPath = Join-Path $PSScriptRoot "lib\common.ps1"
if (Test-Path $libPath) { . $libPath }
else {
    function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
    function Success { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
    function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
    function Error   { param([string]$M) Write-Host "[ERR]  $M" -ForegroundColor Red }
    function Header  { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Magenta; Write-Host "" }
    function Require-Administrator {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Error "Run as Admin"; exit 1 }
    }
    function Prompt-YesNo { param([string]$Message,[bool]$Default=$false)
        $r = Read-Host "$Message [y/N]"; return ($r -ieq 'y')
    }
    function Log-Action { param([string]$M) "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) - $M" | Out-File "$LogDir\actions.log" -Append -Encoding UTF8 }
}
Require-Administrator

$KillLog = "$LogDir\session-kills.log"
function Write-KillLog { param([string]$M)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $M" | Out-File $KillLog -Append -Encoding UTF8
    Log-Action $M
}

function Get-KnownList {
    if ($KnownUsers -and $KnownUsers.Count -gt 0) { return $KnownUsers }
    return @("Administrator","ccdcadmin1","ccdcadmin2","ccdcuser1")
}

function Get-Sessions {
    $sessions = @()
    $qwinsta = qwinsta 2>$null
    if (-not $qwinsta) { $qwinsta = query session 2>$null }
    if (-not $qwinsta) { Warn "Cannot enumerate sessions"; return $sessions }
    foreach ($line in ($qwinsta | Select-Object -Skip 1)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $isCurrent = $line.StartsWith(">")
        $clean = $line -replace '^\s*>\s*',''
        $parts = $clean -split '\s+' | Where-Object { $_ -ne '' }
        if ($parts.Count -lt 3) { continue }
        $sessionName = $parts[0]; $username = $null; $id = $null; $state = ""
        if ($parts[1] -match '^\d+$') { $id = [int]$parts[1]; $state = if ($parts.Count -ge 3) { $parts[2] } else { "" } }
        elseif ($parts.Count -ge 4 -and $parts[2] -match '^\d+$') { $username = $parts[1]; $id = [int]$parts[2]; $state = if ($parts.Count -ge 4) { $parts[3] } else { "" } }
        else { continue }
        if (-not $username) { continue }
        if ([string]::IsNullOrWhiteSpace($username) -or $username -eq "65536") { continue }
        $type = if ($sessionName -match "rdp-tcp") { "RDP" } else { "Console" }
        $sessions += [PSCustomObject]@{Username=$username;SessionId=$id;SessionName=$sessionName;State=$state;Type=$type;IsCurrent=$isCurrent;SourceIP=""}
    }
    # Enrich with source IP
    foreach ($s in $sessions) {
        try {
            $ev = Get-WinEvent -FilterHashtable @{LogName='Security';Id=4624} -MaxEvents 100 -ErrorAction SilentlyContinue |
                Where-Object { $_.Properties[5].Value -eq $s.Username -and $_.Properties[8].Value -in @('10','3') } | Select-Object -First 1
            if ($ev) { $ip = $ev.Properties[18].Value; if ($ip -and $ip -ne "-" -and $ip -ne "::1") { $s.SourceIP = $ip } }
        } catch {}
    }
    return $sessions
}

function Show-Sessions { param([array]$S)
    $known = Get-KnownList
    Header "Active Sessions"
    $fmt = "{0,-18} {1,-5} {2,-12} {3,-8} {4,-16} {5}"
    Write-Host ($fmt -f "USERNAME","ID","SESSION","TYPE","SOURCE IP","STATUS") -ForegroundColor Cyan
    Write-Host ("-" * 80) -ForegroundColor DarkGray
    foreach ($s in $S) {
        $status = if ($s.IsCurrent) { "[YOU]" } elseif ($known -contains $s.Username) { "[TEAM]" } else { "[UNKNOWN]" }
        $color = if ($s.IsCurrent) { "Green" } elseif ($known -contains $s.Username) { "White" } else { "Red" }
        Write-Host ($fmt -f $s.Username,$s.SessionId,$s.SessionName,$s.Type,$s.SourceIP,$status) -ForegroundColor $color
    }
}

function Kill-Session { param([int]$Id, [string]$User)
    logoff $Id 2>&1 | Out-Null
    Success "Logged off session $Id ($User)"
    Write-KillLog "Killed session: ID=$Id User=$User"
}

function Disable-Acct { param([string]$User)
    try { Disable-LocalUser -Name $User -ErrorAction Stop; Success "Disabled local: $User"; Write-KillLog "Disabled: $User"; return } catch {}
    try { Import-Module ActiveDirectory -ErrorAction SilentlyContinue; Set-ADUser -Identity $User -Enabled $false -ErrorAction Stop; Success "Disabled AD: $User"; return } catch {}
    net user $User /active:no 2>$null; Success "Disabled (net user): $User"
    Write-KillLog "Disabled: $User"
}

function Block-FwIP { param([string]$IP)
    if ([string]::IsNullOrWhiteSpace($IP) -or $IP -eq "-") { return }
    $name = "CCDC-Block-$IP"
    Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $name -Direction Inbound -RemoteAddress $IP -Action Block -Enabled True | Out-Null
    New-NetFirewallRule -DisplayName "${name}-Out" -Direction Outbound -RemoteAddress $IP -Action Block -Enabled True | Out-Null
    Success "Blocked IP: $IP"
    Write-KillLog "Blocked IP: $IP"
}

function Confirm-Act { param([string]$M) if ($Force) { return $true }; return (Prompt-YesNo $M) }

# ── Main ──
$sessions = Get-Sessions
$actionTaken = $false

if ($Username) {
    $targets = $sessions | Where-Object { $_.Username -eq $Username -and -not $_.IsCurrent }
    if ($targets.Count -eq 0) { Warn "No sessions for: $Username" }
    elseif (Confirm-Act "Kill $($targets.Count) session(s) for $Username?") {
        foreach ($t in $targets) { Kill-Session $t.SessionId $t.Username }
        if ($DisableAccount) { Disable-Acct $Username }
        if ($BlockIP) { $targets | Where-Object { $_.SourceIP } | Select-Object -ExpandProperty SourceIP -Unique | ForEach-Object { Block-FwIP $_ } }
    }
    $actionTaken = $true
}

if ($SessionId -ge 0) {
    $t = $sessions | Where-Object { $_.SessionId -eq $SessionId } | Select-Object -First 1
    if (-not $t) { Warn "Session $SessionId not found" }
    elseif ($t.IsCurrent) { Error "Cannot kill your own session" }
    elseif (Confirm-Act "Kill session $SessionId ($($t.Username))?") {
        Kill-Session $t.SessionId $t.Username
        if ($DisableAccount) { Disable-Acct $t.Username }
        if ($BlockIP -and $t.SourceIP) { Block-FwIP $t.SourceIP }
    }
    $actionTaken = $true
}

if ($SourceIP) {
    $targets = $sessions | Where-Object { $_.SourceIP -eq $SourceIP -and -not $_.IsCurrent }
    if ($targets.Count -gt 0 -and (Confirm-Act "Kill $($targets.Count) session(s) from $SourceIP?")) {
        foreach ($t in $targets) { Kill-Session $t.SessionId $t.Username; if ($DisableAccount) { Disable-Acct $t.Username } }
    }
    if ($BlockIP) { Block-FwIP $SourceIP }
    $actionTaken = $true
}

if ($KillUnknown) {
    $known = Get-KnownList
    $targets = $sessions | Where-Object { ($known -notcontains $_.Username) -and -not $_.IsCurrent }
    if ($targets.Count -eq 0) { Success "No unknown sessions" }
    elseif (Confirm-Act "Kill $($targets.Count) unknown session(s)?") {
        foreach ($t in $targets) {
            Kill-Session $t.SessionId $t.Username
            if ($DisableAccount) { Disable-Acct $t.Username }
            if ($BlockIP -and $t.SourceIP) { Block-FwIP $t.SourceIP }
        }
    }
    $actionTaken = $true
}

if (-not $actionTaken) {
    Show-Sessions $sessions
    $known = Get-KnownList
    $unknowns = @($sessions | Where-Object { ($known -notcontains $_.Username) -and -not $_.IsCurrent })
    if ($unknowns.Count -gt 0) {
        Write-Host "`nQuick actions:" -ForegroundColor Cyan
        Write-Host "  .\ir-kill.ps1 -KillUnknown -Force" -ForegroundColor Gray
        Write-Host "  .\ir-kill.ps1 -Username <name> -DisableAccount -BlockIP" -ForegroundColor Gray
    }
}

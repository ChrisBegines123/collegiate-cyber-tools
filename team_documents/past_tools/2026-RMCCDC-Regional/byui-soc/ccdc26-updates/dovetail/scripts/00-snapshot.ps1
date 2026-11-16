#Requires -RunAsAdministrator
# CCDC26 - Forensic Baseline Snapshot
# SELF-CONTAINED. Run BEFORE any hardening to capture initial state.

$ErrorActionPreference = "Continue"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$snapDir = "C:\ccdc26\snapshots\$timestamp"
New-Item -ItemType Directory -Path $snapDir -Force | Out-Null

function Write-Status { param([string]$M) Write-Host "[SNAP] $M" -ForegroundColor Cyan }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CCDC26 Forensic Baseline Snapshot" -ForegroundColor Cyan
Write-Host "  Output: $snapDir" -ForegroundColor Cyan
Write-Host "  Time:   $(Get-Date)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── System Info ──
Write-Status "System information..."
@{
    ComputerName = $env:COMPUTERNAME
    OS = (Get-CimInstance Win32_OperatingSystem).Caption
    Domain = (Get-CimInstance Win32_ComputerSystem).Domain
    DomainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    IPAddresses = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" }).IPAddress -join ", "
    SnapshotTime = Get-Date -Format "o"
} | ConvertTo-Json | Out-File "$snapDir\system-info.json" -Encoding UTF8

# ── Local Users & Groups ──
Write-Status "Local users and groups..."
Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet, Description |
    Export-Csv "$snapDir\local-users.csv" -NoTypeInformation

Get-LocalGroup -ErrorAction SilentlyContinue | ForEach-Object {
    $group = $_.Name
    $members = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
        Select-Object @{N='Group';E={$group}}, Name, ObjectClass, PrincipalSource
    $members
} | Export-Csv "$snapDir\local-group-members.csv" -NoTypeInformation

# ── AD Users & Groups (if DC) ──
$isDC = $false
try { $isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4 } catch {}

if ($isDC) {
    Write-Status "AD users and groups (Domain Controller detected)..."
    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        Get-ADUser -Filter * -Properties Name, SamAccountName, Enabled, PasswordLastSet,
            LastLogonDate, MemberOf, Created, Description, AdminCount |
            Select-Object Name, SamAccountName, Enabled, PasswordLastSet, LastLogonDate,
                Created, Description, AdminCount,
                @{N='Groups';E={($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace '^CN=','' }) -join '; '}} |
            Export-Csv "$snapDir\ad-users.csv" -NoTypeInformation

        $privGroups = @("Domain Admins","Enterprise Admins","Schema Admins","Administrators",
                        "Account Operators","Server Operators","Backup Operators","DnsAdmins")
        $privMembers = foreach ($g in $privGroups) {
            try {
                Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue | ForEach-Object {
                    [PSCustomObject]@{ Group = $g; Name = $_.Name; SAM = $_.SamAccountName; Class = $_.objectClass }
                }
            } catch {}
        }
        $privMembers | Export-Csv "$snapDir\ad-privileged-groups.csv" -NoTypeInformation

        Get-ADComputer -Filter * -Properties OperatingSystem, IPv4Address, Created |
            Select-Object Name, OperatingSystem, IPv4Address, Created, Enabled |
            Export-Csv "$snapDir\ad-computers.csv" -NoTypeInformation
    } catch {
        Write-Host "[WARN] AD enumeration failed: $_" -ForegroundColor Yellow
    }

    # DNS Zones
    Write-Status "DNS zones..."
    try {
        Get-DnsServerZone -ErrorAction SilentlyContinue |
            Select-Object ZoneName, ZoneType, IsAutoCreated, IsDsIntegrated |
            Export-Csv "$snapDir\dns-zones.csv" -NoTypeInformation

        Get-DnsServerZone -ErrorAction SilentlyContinue | Where-Object { -not $_.IsAutoCreated } | ForEach-Object {
            try {
                $zone = $_.ZoneName
                Get-DnsServerResourceRecord -ZoneName $zone -ErrorAction SilentlyContinue |
                    Select-Object @{N='Zone';E={$zone}}, HostName, RecordType, @{N='Data';E={$_.RecordData | Out-String}}
            } catch {}
        } | Export-Csv "$snapDir\dns-records.csv" -NoTypeInformation
    } catch {
        Write-Host "[WARN] DNS enumeration failed" -ForegroundColor Yellow
    }
}

# ── Scheduled Tasks ──
Write-Status "Scheduled tasks..."
Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
    $actions = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " | "
    [PSCustomObject]@{
        TaskPath = $_.TaskPath; TaskName = $_.TaskName; State = $_.State
        Author = $_.Author; Actions = $actions
        RunAs = $_.Principal.UserId
    }
} | Export-Csv "$snapDir\scheduled-tasks.csv" -NoTypeInformation

# ── Services ──
Write-Status "Services..."
Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode,
    PathName, StartName, Description |
    Export-Csv "$snapDir\services.csv" -NoTypeInformation

# ── Firewall Rules ──
Write-Status "Firewall rules..."
Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Select-Object DisplayName, Direction, Action, Enabled, Profile |
    Export-Csv "$snapDir\firewall-rules.csv" -NoTypeInformation

Get-NetFirewallProfile -ErrorAction SilentlyContinue |
    Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LogFileName |
    Export-Csv "$snapDir\firewall-profiles.csv" -NoTypeInformation

# ── Running Processes ──
Write-Status "Running processes..."
Get-CimInstance Win32_Process | ForEach-Object {
    $owner = try {
        $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($o.ReturnValue -eq 0) { "$($o.Domain)\$($o.User)" } else { "" }
    } catch { "" }
    [PSCustomObject]@{
        PID = $_.ProcessId; PPID = $_.ParentProcessId
        Name = $_.Name; Path = $_.ExecutablePath
        CommandLine = $_.CommandLine; Owner = $owner
        Created = $_.CreationDate
    }
} | Export-Csv "$snapDir\processes.csv" -NoTypeInformation

# ── Network Connections ──
Write-Status "Network connections..."
Get-NetTCPConnection -ErrorAction SilentlyContinue | ForEach-Object {
    $procName = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    [PSCustomObject]@{
        LocalAddress = $_.LocalAddress; LocalPort = $_.LocalPort
        RemoteAddress = $_.RemoteAddress; RemotePort = $_.RemotePort
        State = $_.State; PID = $_.OwningProcess; Process = $procName
    }
} | Export-Csv "$snapDir\network-tcp.csv" -NoTypeInformation

Get-NetUDPEndpoint -ErrorAction SilentlyContinue | ForEach-Object {
    $procName = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    [PSCustomObject]@{
        LocalAddress = $_.LocalAddress; LocalPort = $_.LocalPort
        PID = $_.OwningProcess; Process = $procName
    }
} | Export-Csv "$snapDir\network-udp.csv" -NoTypeInformation

# ── Installed Software ──
Write-Status "Installed software..."
$sw = @()
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    $sw += Get-ItemProperty $rp -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
}
$sw | Sort-Object DisplayName -Unique | Export-Csv "$snapDir\installed-software.csv" -NoTypeInformation

# ── Windows Updates ──
Write-Status "Windows updates..."
Get-HotFix -ErrorAction SilentlyContinue |
    Select-Object HotFixID, Description, InstalledBy, InstalledOn |
    Export-Csv "$snapDir\hotfixes.csv" -NoTypeInformation

# ── Registry Run Keys ──
Write-Status "Registry autoruns..."
$runKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
)
$autoruns = foreach ($key in $runKeys) {
    if (Test-Path $key) {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        $props.PSObject.Properties | Where-Object {
            $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')
        } | ForEach-Object {
            [PSCustomObject]@{ Key = $key; Name = $_.Name; Value = $_.Value }
        }
    }
}
$autoruns | Export-Csv "$snapDir\registry-autoruns.csv" -NoTypeInformation

# ── Shares ──
Write-Status "Network shares..."
Get-SmbShare -ErrorAction SilentlyContinue |
    Select-Object Name, Path, Description, CurrentUsers |
    Export-Csv "$snapDir\shares.csv" -NoTypeInformation

# ── Summary ──
$fileCount = (Get-ChildItem $snapDir -File).Count
$totalSize = [math]::Round((Get-ChildItem $snapDir -File | Measure-Object Length -Sum).Sum / 1KB, 1)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Snapshot Complete" -ForegroundColor Green
Write-Host "  Files:    $fileCount" -ForegroundColor Green
Write-Host "  Size:     ${totalSize} KB" -ForegroundColor Green
Write-Host "  Location: $snapDir" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

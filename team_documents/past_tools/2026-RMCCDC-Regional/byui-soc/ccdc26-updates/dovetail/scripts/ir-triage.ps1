#Requires -RunAsAdministrator
# CCDC26 - Incident Response Triage (adapted from Invoke-Triage.ps1)
# Fast situational awareness. Can source lib/common.ps1 or run standalone.

param(
    [switch]$Quick,
    [switch]$Full,
    [ValidateSet('Overview','Sessions','Processes','Network','Services','Tasks','Timeline','FileSystem')]
    [string]$Section,
    [switch]$CollectEvidence,
    [string]$OutputFile
)

$ErrorActionPreference = 'Continue'

$LogDir = "C:\ccdc26\logs"
$ToolkitRoot = "C:\ccdc26"
@($LogDir) | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null } }

$libPath = Join-Path $PSScriptRoot "lib\common.ps1"
if (Test-Path $libPath) { . $libPath }
else {
    function Info    { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
    function Success { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
    function Warn    { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }
    function Error   { param([string]$M) Write-Host "[ERR]  $M" -ForegroundColor Red }
    function Header  { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Magenta; Write-Host "" }
    function Finding { param([string]$M) Write-Host "[FINDING] $M" -ForegroundColor Red }
    function Require-Administrator {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Error "Run as Admin"; exit 1 }
    }
    function Get-PortDescription { param([int]$Port)
        $map = @{22="SSH";53="DNS";80="HTTP";443="HTTPS";3389="RDP";445="SMB";88="Kerberos";389="LDAP";636="LDAPS";135="RPC";1433="MSSQL";5985="WinRM"}
        if ($map.ContainsKey($Port)) { return $map[$Port] }; return "Unknown"
    }
}
Require-Administrator

$script:Findings = [System.Collections.ArrayList]::new()
$script:TriageStart = Get-Date
$script:Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:EvidenceDir = "$ToolkitRoot\evidence\triage-$script:Timestamp"
$script:SuspiciousIPs = [System.Collections.Generic.HashSet[string]]::new()
$script:SuspiciousProcs = [System.Collections.ArrayList]::new()

if ($OutputFile) { Start-Transcript -Path $OutputFile -Force | Out-Null }
if ($CollectEvidence) { New-Item -ItemType Directory -Path $script:EvidenceDir -Force | Out-Null }

function Add-TFinding { param([string]$Sev, [string]$Cat, [string]$Msg, [string]$Detail="")
    $null = $script:Findings.Add([PSCustomObject]@{Severity=$Sev;Category=$Cat;Message=$Msg;Detail=$Detail})
    $c = switch($Sev) {'CRITICAL'{'Red'}'HIGH'{'Red'}'MEDIUM'{'Yellow'}'LOW'{'Gray'}}
    Write-Host "  [$Sev] $Msg" -ForegroundColor $c
    if ($Detail -and -not $Quick) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

function Save-Ev { param([string]$F, [string]$C) if ($CollectEvidence) { $C | Out-File (Join-Path $script:EvidenceDir $F) -Encoding UTF8 } }

# ── Sections ──
function Get-SystemOverview {
    Header "System Overview"
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "  Host: $($cs.Name) | OS: $($os.Caption) | Domain: $($cs.Domain) | DC: $($cs.DomainRole -ge 4)" -ForegroundColor White
    try {
        $def = Get-MpComputerStatus -ErrorAction Stop
        if (-not $def.RealTimeProtectionEnabled) { Add-TFinding "CRITICAL" "Defender" "Real-time protection DISABLED" }
        $prefs = Get-MpPreference -ErrorAction SilentlyContinue
        $exTotal = @($prefs.ExclusionPath).Count + @($prefs.ExclusionProcess).Count + @($prefs.ExclusionExtension).Count
        if ($exTotal -gt 0) { Add-TFinding "HIGH" "Defender" "$exTotal exclusion(s) set" }
    } catch {}
}

function Get-ActiveSessions {
    Header "Active Sessions"
    try {
        $raw = query user 2>&1; foreach ($l in $raw) { Write-Host "    $l" -ForegroundColor $(if($l -match 'rdp'){'Yellow'}else{'Gray'}) }
    } catch {}
    try {
        $fails = Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 50 -ErrorAction Stop
        $groups = $fails | ForEach-Object { $x=[xml]$_.ToXml(); $x.Event.EventData.Data | Where-Object {$_.Name -eq 'IpAddress'} | Select-Object -ExpandProperty '#text' } |
            Where-Object { $_ -and $_ -ne '-' } | Group-Object | Where-Object { $_.Count -ge 5 }
        foreach ($g in $groups) {
            Add-TFinding "HIGH" "BruteForce" "$($g.Count) failed logons from $($g.Name)"
            $null = $script:SuspiciousIPs.Add($g.Name)
        }
    } catch {}
}

function Get-SuspiciousProcesses {
    Header "Process Analysis"
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    Info "Analyzing $($procs.Count) processes..."
    $suspDirs = @($env:TEMP,$env:APPDATA,'C:\Users\Public','C:\ProgramData','C:\Windows\Temp')
    $suspNames = @('nc','ncat','mimikatz','psexec','meterpreter','beacon','cobalt','rubeus','chisel','plink')
    foreach ($p in $procs) {
        $flags = @(); $path = $p.ExecutablePath; $name = $p.Name; $cmd = $p.CommandLine
        if ($path) { foreach ($d in $suspDirs) { if ($d -and $path.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) { $flags += "Suspicious path"; break } } }
        if ($path -and -not (Test-Path $path -ErrorAction SilentlyContinue)) { $flags += "Binary missing" }
        $stem = [IO.Path]::GetFileNameWithoutExtension($name)
        if ($stem -and $suspNames -contains $stem.ToLower()) { $flags += "Known tool: $name" }
        if ($cmd -and $cmd -match '\s-[eE]([nN][cC])?\s') { $flags += "Encoded command" }
        if ($flags.Count -gt 0) {
            $sev = if ($flags -match 'tool|missing|Encoded') { "CRITICAL" } else { "MEDIUM" }
            Add-TFinding $sev "Processes" "PID $($p.ProcessId): $name ($($flags -join '; '))" $cmd
            $null = $script:SuspiciousProcs.Add(@{Name=$name;PID=$p.ProcessId;Path=$path;Flags=$flags})
        }
    }
}

function Get-NetworkStatus {
    Header "Network Analysis"
    $tcp = Get-NetTCPConnection -ErrorAction SilentlyContinue
    $procC = @{}; Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $procC[$_.Id] = $_.ProcessName }
    $suspPorts = @(4444,5555,6666,7777,8888,9999,1234,31337)
    $shells = @("cmd","powershell","pwsh","rundll32","regsvr32","mshta")
    $tcp | Where-Object { $_.State -eq 'Established' } | ForEach-Object {
        $pn = $procC[$_.OwningProcess]; $flags = @()
        if ($_.RemotePort -in $suspPorts -or $_.LocalPort -in $suspPorts) { $flags += "suspicious port" }
        if ($pn -and $shells -contains $pn.ToLower()) { $flags += "shell network" }
        if ($flags.Count -gt 0) {
            Add-TFinding "CRITICAL" "Network" "$pn -> $($_.RemoteAddress):$($_.RemotePort)" ($flags -join '; ')
            $null = $script:SuspiciousIPs.Add($_.RemoteAddress)
        }
    }
}

function Get-ServiceStatus {
    Header "Service Analysis"
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
        $bp = $_.PathName; if (-not $bp) { return }
        if ($bp -notmatch '^"?C:\\(Windows|Program Files)' -and $bp -notmatch 'svchost' -and $_.State -ne 'Stopped') {
            Add-TFinding "HIGH" "Services" "Service: $($_.Name)" "Path: $bp RunAs: $($_.StartName)"
        }
    }
}

function Get-TaskStatus {
    Header "Scheduled Tasks"
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notmatch '\\Microsoft\\' -and $_.State -ne 'Disabled' } | ForEach-Object {
        $acts = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " | "
        if ($acts -match 'powershell|cmd|wscript|certutil|mshta') {
            Add-TFinding "HIGH" "Tasks" "$($_.TaskPath)$($_.TaskName)" $acts
        }
    }
}

function Get-RecentTimeline {
    Header "Recent Timeline"
    try { Get-WinEvent -FilterHashtable @{LogName='System';Id=7045} -MaxEvents 10 -ErrorAction Stop | ForEach-Object {
        $x=[xml]$_.ToXml(); $d=@{}; foreach($i in $x.Event.EventData.Data){if($i.Name){$d[$i.Name]=$i.'#text'}}
        Add-TFinding "HIGH" "Persistence" "Service installed: $($d['ServiceName'])" "$($d['ImagePath'])"
    } } catch {}
}

function Get-FileSystemAnomalies {
    Header "File System"
    foreach ($dir in @('C:\Users\Public','C:\PerfLogs','C:\Windows\Temp')) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(exe|dll|ps1|bat|cmd|vbs|js|hta)$' } | ForEach-Object {
                Add-TFinding "HIGH" "FileSystem" "Executable: $($_.FullName)" "Size: $($_.Length) Modified: $($_.LastWriteTime)"
            }
    }
}

function Show-Summary {
    Header "THREAT SUMMARY"
    $c = @($script:Findings | Where-Object {$_.Severity -eq 'CRITICAL'}).Count
    $h = @($script:Findings | Where-Object {$_.Severity -eq 'HIGH'}).Count
    Write-Host "  CRITICAL: $c  HIGH: $h  TOTAL: $($script:Findings.Count)" -ForegroundColor $(if($c){'Red'}else{'Green'})
    if ($script:SuspiciousIPs.Count -gt 0) {
        Write-Host "  Suspicious IPs: $($script:SuspiciousIPs -join ', ')" -ForegroundColor Yellow
    }
    if ($script:SuspiciousProcs.Count -gt 0) {
        $pids = ($script:SuspiciousProcs | ForEach-Object { $_['PID'] }) -join ','
        Write-Host "  Kill command: Stop-Process -Id $pids -Force" -ForegroundColor Yellow
    }
    $elapsed = ((Get-Date) - $script:TriageStart).TotalSeconds
    Success "Triage completed in $([math]::Round($elapsed, 1))s"
}

# ── Main ──
Write-Host "`n   CCDC26 Incident Response Triage" -ForegroundColor Cyan
Write-Host "   Mode: $(if($Quick){'QUICK'}elseif($Full){'FULL'}else{'STANDARD'})`n" -ForegroundColor Cyan

$sections = [ordered]@{
    Overview={Get-SystemOverview}; Sessions={Get-ActiveSessions}; Processes={Get-SuspiciousProcesses}
    Network={Get-NetworkStatus}; Services={Get-ServiceStatus}; Tasks={Get-TaskStatus}
    Timeline={Get-RecentTimeline}; FileSystem={Get-FileSystemAnomalies}
}

if ($Section) { if ($sections.Contains($Section)) { & $sections[$Section] } else { Error "Unknown: $Section" } }
else { foreach ($s in $sections.GetEnumerator()) { try { & $s.Value } catch { Warn "$($s.Key) failed: $_" } } }

Show-Summary
if ($OutputFile) { Stop-Transcript | Out-Null; Success "Report: $OutputFile" }

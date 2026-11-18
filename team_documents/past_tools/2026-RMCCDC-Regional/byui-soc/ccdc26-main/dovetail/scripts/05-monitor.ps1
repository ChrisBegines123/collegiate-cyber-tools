#Requires -RunAsAdministrator
# CCDC26 - Real-Time Monitor (SELF-CONTAINED)
# Process, network, and session monitoring via background jobs.

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Info { param([string]$M) Write-Host "[INFO] $M" -ForegroundColor Blue }
function OK   { param([string]$M) Write-Host "[OK]   $M" -ForegroundColor Green }
function Warn { param([string]$M) Write-Host "[WARN] $M" -ForegroundColor Yellow }

$JobPrefix = "CCDC-Monitor"

# ═══════════════════════════════════════════════════════════════════════════
# PROCESS MONITOR
# ═══════════════════════════════════════════════════════════════════════════
$ProcessMonitorScript = {
    $logFile = "C:\ccdc26\logs\process-monitor.log"
    $pollInterval = 10
    $suspiciousPaths = @($env:TEMP, $env:APPDATA, "C:\Users\Public", "C:\ProgramData", "C:\PerfLogs", "C:\Windows\Temp")
    $suspiciousNames = @("nc","ncat","socat","mimikatz","psexec","meterpreter","beacon","cobalt","xmrig","chisel","plink")

    function Write-Alert { param([string]$Sev, [string]$Msg)
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] [$Sev] [PROCESS] $Msg" | Out-File $logFile -Append -Encoding UTF8
        if ($Sev -eq "CRITICAL") { [Console]::Beep(1000, 200) }
    }

    Write-Alert "INFO" "Process monitor started"
    $baseline = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $baseline[$_.Id] = $true }

    while ($true) {
        Start-Sleep -Seconds $pollInterval
        try {
            $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
            foreach ($p in $procs) {
                if ($baseline.ContainsKey($p.ProcessId)) { continue }
                $baseline[$p.ProcessId] = $true
                $name = $p.Name; $path = $p.ExecutablePath; $cmd = $p.CommandLine; $ppid = $p.ParentProcessId
                $pName = (Get-CimInstance Win32_Process -Filter "ProcessId = $ppid" -ErrorAction SilentlyContinue).Name
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)

                if ($path) {
                    foreach ($sp in $suspiciousPaths) {
                        if ($sp -and $path.StartsWith($sp, [System.StringComparison]::OrdinalIgnoreCase)) {
                            Write-Alert "CRITICAL" "Suspicious path: PID=$($p.ProcessId) $name Path=$path PPID=$ppid($pName)"
                            break
                        }
                    }
                }
                if ($suspiciousNames -contains $baseName.ToLower()) {
                    Write-Alert "CRITICAL" "Known tool: PID=$($p.ProcessId) $name Path=$path Cmd=$cmd"
                }
                if ($pName -eq "w3wp.exe" -and $name -match "^(cmd|powershell|pwsh)\.exe$") {
                    Write-Alert "CRITICAL" "WEBSHELL: w3wp.exe -> $name PID=$($p.ProcessId) Cmd=$cmd"
                }
                if ($cmd -and $cmd -match "-[Ee](?:nc|ncodedCommand)\s+[A-Za-z0-9+/=]{20,}") {
                    Write-Alert "CRITICAL" "Encoded PS: PID=$($p.ProcessId) Cmd=$($cmd.Substring(0, [Math]::Min($cmd.Length, 200)))"
                }
            }
            $live = @{}; $procs | ForEach-Object { $live[$_.ProcessId] = $true }
            $stale = $baseline.Keys | Where-Object { -not $live.ContainsKey($_) }
            foreach ($s in $stale) { $baseline.Remove($s) }
        } catch {}
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# NETWORK MONITOR
# ═══════════════════════════════════════════════════════════════════════════
$NetworkMonitorScript = {
    $logFile = "C:\ccdc26\logs\network-monitor.log"
    $pollInterval = 15
    $suspiciousPorts = @(4444,5555,6666,7777,8888,9999,1234,31337)
    $shellNames = @("cmd","powershell","pwsh","rundll32")

    function Write-Alert { param([string]$Sev, [string]$Msg)
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] [$Sev] [NETWORK] $Msg" | Out-File $logFile -Append -Encoding UTF8
    }

    Write-Alert "INFO" "Network monitor started"
    $baseConns = @{}; $baseListeners = @{}
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | ForEach-Object {
        $baseConns["$($_.LocalAddress):$($_.LocalPort)-$($_.RemoteAddress):$($_.RemotePort)"] = $true
    }
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $baseListeners["$($_.LocalAddress):$($_.LocalPort)"] = $true
    }

    while ($true) {
        Start-Sleep -Seconds $pollInterval
        try {
            $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
            foreach ($c in $conns) {
                $key = "$($c.LocalAddress):$($c.LocalPort)-$($c.RemoteAddress):$($c.RemotePort)"
                if ($baseConns.ContainsKey($key)) { continue }
                $baseConns[$key] = $true
                $proc = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                if ($suspiciousPorts -contains $c.RemotePort -or $suspiciousPorts -contains $c.LocalPort) {
                    Write-Alert "CRITICAL" "Suspicious port: $proc -> $($c.RemoteAddress):$($c.RemotePort)"
                }
                if ($proc -and $shellNames -contains $proc.ToLower()) {
                    Write-Alert "CRITICAL" "Shell network: $proc -> $($c.RemoteAddress):$($c.RemotePort)"
                }
            }
            $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
            foreach ($l in $listeners) {
                $key = "$($l.LocalAddress):$($l.LocalPort)"
                if ($baseListeners.ContainsKey($key)) { continue }
                $baseListeners[$key] = $true
                $proc = (Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                Write-Alert "WARNING" "New listener: $proc on :$($l.LocalPort)"
            }
            $live = @{}; $conns | ForEach-Object { $live["$($_.LocalAddress):$($_.LocalPort)-$($_.RemoteAddress):$($_.RemotePort)"] = $true }
            $stale = $baseConns.Keys | Where-Object { -not $live.ContainsKey($_) }
            foreach ($s in $stale) { $baseConns.Remove($s) }
        } catch {}
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# SESSION MONITOR
# ═══════════════════════════════════════════════════════════════════════════
$SessionMonitorScript = {
    $logFile = "C:\ccdc26\logs\session-monitor.log"
    $pollInterval = 20

    function Write-Alert { param([string]$Sev, [string]$Msg)
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] [$Sev] [SESSION] $Msg" | Out-File $logFile -Append -Encoding UTF8
    }

    Write-Alert "INFO" "Session monitor started"
    $baseline = @{}
    $quser = query user 2>$null
    if ($quser) {
        $quser | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '^\s*>?(\S+)\s+') { $baseline[$Matches[1]] = $_ }
        }
    }

    while ($true) {
        Start-Sleep -Seconds $pollInterval
        try {
            $quser = query user 2>$null
            if (-not $quser) { continue }
            $current = @{}
            foreach ($line in ($quser | Select-Object -Skip 1)) {
                $clean = ($line -replace '^\s*>','').Trim()
                if ([string]::IsNullOrWhiteSpace($clean)) { continue }
                $parts = $clean -split '\s{2,}'
                if ($parts.Count -lt 3) { continue }
                $username = $parts[0].Trim()
                $current[$username] = $line
                if ($baseline.ContainsKey($username)) { continue }
                $baseline[$username] = $line
                $sev = if ($line -match "rdp-tcp") { "CRITICAL" } else { "WARNING" }
                Write-Alert $sev "New session: $username ($clean)"
            }
            $departed = $baseline.Keys | Where-Object { -not $current.ContainsKey($_) }
            foreach ($d in $departed) {
                Write-Alert "INFO" "Session ended: $d"
                $baseline.Remove($d)
            }
        } catch {}
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# JOB MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CCDC26 Real-Time Monitor" -ForegroundColor Cyan
Write-Host "  Logs: $LogDir" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Stop any existing monitors
Get-Job -Name "$JobPrefix*" -ErrorAction SilentlyContinue | Stop-Job -PassThru | Remove-Job -Force

# Start all three
$pJob = Start-Job -Name "$JobPrefix-Process" -ScriptBlock $ProcessMonitorScript
OK "Process monitor started (Job $($pJob.Id))"

$nJob = Start-Job -Name "$JobPrefix-Network" -ScriptBlock $NetworkMonitorScript
OK "Network monitor started (Job $($nJob.Id))"

$sJob = Start-Job -Name "$JobPrefix-Session" -ScriptBlock $SessionMonitorScript
OK "Session monitor started (Job $($sJob.Id))"

Write-Host ""
Info "All monitors running as background jobs"
Info "Check logs: $LogDir\*-monitor.log"
Info "Stop all:   Get-Job -Name 'CCDC-Monitor*' | Stop-Job -PassThru | Remove-Job"

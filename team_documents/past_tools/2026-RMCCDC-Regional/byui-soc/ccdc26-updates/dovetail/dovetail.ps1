<# 
.SYNOPSIS
    Remote PowerShell script dispatcher for CCDC Windows fleet management.
.DESCRIPTION
    Adapted from UCI's Dovetail. Discovers domain-joined Windows machines from AD
    or accepts manual target lists, establishes WinRM sessions, and dispatches
    scripts via Invoke-Command -AsJob with per-host output collection.
.PARAMETER Script
    Path to the script to dispatch to all targets.
.PARAMETER Targets
    Comma-separated IPs/hostnames, or "domain" to auto-discover from AD.
.PARAMETER Hosts
    Path to a newline-separated file of target hostnames/IPs.
.PARAMETER Connect
    Establish WinRM sessions (run before dispatching scripts).
.PARAMETER Repair
    Repair broken/disconnected sessions without re-creating healthy ones.
.PARAMETER Include
    Only dispatch to these hosts (comma-separated).
.PARAMETER Exclude
    Skip these hosts (comma-separated).
.PARAMETER Out
    Output directory for per-host logs (default: .\Logs).
.PARAMETER Timeout
    Port-test timeout in milliseconds (default: 3000).
.PARAMETER NonDomain
    Use explicit credentials instead of Kerberos SSO.
.PARAMETER FunctionCall
    Append a function invocation to the dispatched script.
#>

param(
    [string]$Script,
    [string]$Targets,
    [string]$Hosts,
    [switch]$Connect,
    [switch]$Repair,
    [switch]$NonDomain,
    [string]$FunctionCall,
    [string]$Out = "$(Get-Location)\Logs",
    [string[]]$Include,
    [string[]]$Exclude,
    [int]$Timeout = 3000
)

$ErrorActionPreference = "Continue"

function Test-WinRMPort {
    param([string]$Computer, [int]$Port, [int]$Timeout)
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect($Computer, $Port, $null, $null)
    $wait = $iar.AsyncWaitHandle.WaitOne($Timeout, $false)
    if ($wait) {
        try { $tcp.EndConnect($iar) } catch { $tcp.Close(); return $false }
        $tcp.Close(); return $true
    }
    $tcp.Close(); return $false
}

function Connect-Target {
    param([string]$Computer, [switch]$NonDomain, [int]$Timeout)

    $port = 5985
    if (-not (Test-WinRMPort $Computer 5985 $Timeout)) {
        if (Test-WinRMPort $Computer 5986 $Timeout) {
            $port = 5986
        } else {
            Write-Host "[ERROR] No WinRM ports open: $Computer" -ForegroundColor Red
            return $null
        }
    }

    $sessionOpts = @{ ComputerName = $Computer; ErrorAction = 'SilentlyContinue' }
    if ($NonDomain) {
        $sessionOpts.Credential = $global:Cred
        $sessionOpts.Authentication = "Basic"
    }
    if ($port -eq 5986) {
        $sessionOpts.UseSSL = $true
        $sessionOpts.SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    }

    $session = New-PSSession @sessionOpts
    if ($session) {
        Write-Host "[OK] Connected: $Computer (:$port)" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] WinRM failed: $Computer" -ForegroundColor Red
    }
    return $session
}

function Get-TargetComputers {
    if ($Targets -eq "domain") {
        try {
            $computers = Get-ADComputer -Filter "OperatingSystem -like '*Windows*'" -Properties OperatingSystem |
                Select-Object -ExpandProperty Name
            Write-Host "[INFO] Discovered $($computers.Count) Windows machines from AD" -ForegroundColor Green
            $computers | ForEach-Object { Write-Host "  $_" }
            return $computers
        } catch {
            Write-Host "[ERROR] AD discovery failed: $_" -ForegroundColor Red
            exit 1
        }
    }
    if ($Targets) {
        return $Targets -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    }
    if ($Hosts -and (Test-Path $Hosts)) {
        return Get-Content $Hosts | Where-Object { $_ -ne '' }
    }
    Write-Host "[ERROR] No targets specified. Use -Targets, -Hosts, or 'domain'" -ForegroundColor Red
    exit 1
}

# ── Connection logic ──
if ($Connect) {
    if (-not $Repair) {
        Remove-Variable -Name Sessions -Scope Global -ErrorAction SilentlyContinue
        $global:Sessions = @()
        Get-PSSession | Remove-PSSession -ErrorAction SilentlyContinue
    }

    if ($NonDomain -and -not $global:Cred) {
        $global:Cred = Get-Credential
    }
    if ($NonDomain) {
        Set-Item WSMan:\localhost\Client\AllowUnencrypted -Value $true -Force -ErrorAction SilentlyContinue
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force -ErrorAction SilentlyContinue
    }

    if ($Repair) {
        if (-not $global:Sessions -or $global:Sessions.Count -eq 0) {
            Write-Host "[ERROR] No sessions to repair" -ForegroundColor Red; exit 1
        }
        $broken = $global:Sessions | Where-Object { $_.State -in @("Broken","Disconnected","Closed") }
        Write-Host "[INFO] Repairing $($broken.Count) broken session(s)" -ForegroundColor Yellow
        foreach ($s in $broken) {
            $new = Connect-Target -Computer $s.ComputerName -NonDomain:$NonDomain -Timeout $Timeout
            if ($new) { $global:Sessions += $new }
        }
        $global:Sessions = $global:Sessions | Where-Object { $_.State -eq "Opened" }
    } else {
        $computers = Get-TargetComputers
        foreach ($c in $computers) {
            $session = Connect-Target -Computer $c -NonDomain:$NonDomain -Timeout $Timeout
            if ($session) { $global:Sessions += $session }
        }
    }

    Write-Host "`n[INFO] Active sessions: $($global:Sessions.Count)" -ForegroundColor Cyan
}

# ── Dispatch logic ──
if ($Script -and $global:Sessions.Count -gt 0) {
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }

    $ext = [System.IO.Path]::GetFileNameWithoutExtension($Script).ToLower() + ".$(Get-Random -Maximum 1000)"

    $dispatchScript = $Script
    if ($FunctionCall) {
        $tmpName = ($FunctionCall -split ' ')[0]
        $tmpPath = "C:\Windows\Temp\$tmpName.ps1"
        (Get-Content $Script) + $FunctionCall | Out-File $tmpPath -Encoding UTF8
        $dispatchScript = $tmpPath
    }

    $jobs = @()
    foreach ($session in $global:Sessions) {
        if ($Exclude.Count -gt 0 -and $session.ComputerName -in $Exclude) {
            Write-Host "[SKIP] Excluded: $($session.ComputerName)" -ForegroundColor Yellow; continue
        }
        if ($Include.Count -gt 0 -and $session.ComputerName -notin $Include) {
            Write-Host "[SKIP] Not included: $($session.ComputerName)" -ForegroundColor Yellow; continue
        }
        if ($session.State -ne "Opened") {
            Write-Host "[ERROR] Session broken, skipping: $($session.ComputerName)" -ForegroundColor Red; continue
        }

        $jobs += Invoke-Command -FilePath $dispatchScript -Session $session -AsJob
        Write-Host "[DISPATCH] $($session.ComputerName)" -ForegroundColor Green
    }

    $completed = @()
    while ($completed.Count -lt $jobs.Count) {
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            $loc = $jobs[$i].Location
            if ($loc -in $completed) { continue }

            if ($jobs[$i].State -eq "Completed") {
                $jobs[$i] | Receive-Job | Out-File "$Out\$loc.$ext" -Encoding UTF8
                Write-Host "[DONE] $loc -> $ext" -ForegroundColor Green
                $completed += $loc
            }
            elseif ($jobs[$i].State -in @("Failed","Blocked","Disconnected","Stopped","Suspended")) {
                Write-Host "[FAIL] $loc ($($jobs[$i].State))" -ForegroundColor Red
                $completed += $loc
            }
        }
        if ($completed.Count -lt $jobs.Count) { Start-Sleep -Milliseconds 100 }
    }

    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    Write-Host "`n[INFO] Dispatch complete. Logs in $Out" -ForegroundColor Cyan
}

if (-not $global:Sessions -or $global:Sessions.Count -eq 0) {
    if (-not $Connect) { Write-Host "[ERROR] No sessions. Run with -Connect first." -ForegroundColor Red }
}
if (-not $Script -and -not $Connect) {
    Write-Host "[ERROR] No script specified." -ForegroundColor Red
}

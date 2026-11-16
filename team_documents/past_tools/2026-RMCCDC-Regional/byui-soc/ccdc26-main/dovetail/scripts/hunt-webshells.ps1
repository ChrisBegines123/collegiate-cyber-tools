#Requires -RunAsAdministrator
# CCDC26 - Webshell Scanner
# Adapted from Find-Webshells.ps1 with inlined dependencies.

param(
    [string]$Path,
    [switch]$Baseline,
    [switch]$Compare,
    [switch]$Quarantine,
    [bool]$Recursive = $true,
    [string]$OutputFile
)

$ErrorActionPreference = "Continue"

$LogDir = "C:\ccdc26\logs"
$BaselineDir = "C:\ccdc26\baselines"
$QuarantineDir = "C:\ccdc26\quarantine"
@($LogDir, $BaselineDir, $QuarantineDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

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
    function Log-Action { param([string]$M) "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) - $M" | Out-File "$LogDir\actions.log" -Append -Encoding UTF8 }
}
Require-Administrator

$WebExtensions = @("*.aspx","*.asp","*.ashx","*.asmx","*.config","*.php","*.jsp","*.aspx.cs")
$ScanLog = "$LogDir\webshell-scan.log"

$SuspiciousPatterns = @(
    @{Pattern='eval\s*\('; Weight=8; Label="eval()"},
    @{Pattern='Execute\s*\('; Weight=8; Label="Execute()"},
    @{Pattern='System\.Diagnostics\.Process'; Weight=9; Label="Process spawn"},
    @{Pattern='ProcessStartInfo'; Weight=9; Label="ProcessStartInfo"},
    @{Pattern='cmd\.exe'; Weight=8; Label="cmd.exe"},
    @{Pattern='powershell\.exe'; Weight=8; Label="powershell.exe"},
    @{Pattern='Invoke-Expression'; Weight=9; Label="IEX"},
    @{Pattern='\bIEX\b'; Weight=8; Label="IEX alias"},
    @{Pattern='Request\s*\[\s*"cmd"'; Weight=10; Label="Request[cmd]"},
    @{Pattern='Request\.QueryString'; Weight=6; Label="QueryString"},
    @{Pattern='Request\.Form'; Weight=5; Label="Form"},
    @{Pattern='WebShell'; Weight=10; Label="WebShell keyword"},
    @{Pattern='backdoor'; Weight=10; Label="backdoor keyword"},
    @{Pattern='FromBase64String'; Weight=7; Label="Base64 decode"},
    @{Pattern='WScript\.Shell'; Weight=9; Label="WScript.Shell"},
    @{Pattern='Server\.CreateObject'; Weight=9; Label="Server.CreateObject"},
    @{Pattern='VirtualAlloc'; Weight=9; Label="VirtualAlloc"},
    @{Pattern='DllImport'; Weight=7; Label="DllImport"}
)

function Get-WebRoots {
    $roots = @()
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        Get-Website -ErrorAction SilentlyContinue | ForEach-Object {
            $phys = $_.PhysicalPath -replace '%SystemDrive%', $env:SystemDrive
            if (Test-Path $phys) { $roots += $phys }
        }
    } catch {}
    if ($roots.Count -eq 0) {
        $default = "C:\inetpub\wwwroot"
        if (Test-Path $default) { $roots += $default }
    }
    return $roots | Select-Object -Unique
}

function Get-WebFiles { param([string]$Root)
    $params = @{Path=$Root; Include=$WebExtensions; File=$true; ErrorAction='SilentlyContinue'}
    if ($Recursive) { $params.Recurse = $true }
    return Get-ChildItem @params
}

function Get-FileEntropy { param([string]$Content)
    if ([string]::IsNullOrEmpty($Content)) { return 0.0 }
    $freq = @{}
    foreach ($c in $Content.ToCharArray()) { $k = [int]$c; if ($freq.ContainsKey($k)) { $freq[$k]++ } else { $freq[$k]=1 } }
    $len = $Content.Length; $entropy = 0.0
    foreach ($count in $freq.Values) { $p = $count/$len; if ($p -gt 0) { $entropy -= $p * [Math]::Log($p, 2) } }
    return [Math]::Round($entropy, 2)
}

function Move-ToQuarantine { param([string]$FilePath)
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $dest = Join-Path $QuarantineDir "${ts}_$(Split-Path $FilePath -Leaf)"
    Copy-Item $FilePath $dest -Force
    "" | Set-Content $FilePath -Force
    Warn "QUARANTINED: $FilePath -> $dest"
    Log-Action "Quarantined: $FilePath -> $dest"
}

# ── Main ──
$webRoots = if ($Path) { @($Path) } else { Get-WebRoots }
if (-not $webRoots) {
    $iisInstalled = (Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue).Installed -eq $true
    if (-not $iisInstalled) {
        Info "IIS is not installed on this server. No web roots to scan."
    } else {
        Warn "IIS installed but no web roots found. Use -Path to specify one."
    }
    exit 0
}
Info "Web root(s): $($webRoots -join ', ')"

if ($Baseline) {
    Header "Creating Baseline"
    $inv = @()
    foreach ($root in $webRoots) {
        $files = Get-WebFiles $root
        foreach ($f in $files) {
            try {
                $hash = (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                $inv += [PSCustomObject]@{Path=$f.FullName;SHA256=$hash;Size=$f.Length;LastModified=$f.LastWriteTime.ToString("o");WebRoot=$root}
            } catch {}
        }
    }
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $bFile = "$BaselineDir\webroot-$ts.json"
    $inv | ConvertTo-Json -Depth 5 | Out-File $bFile -Encoding UTF8
    Success "Baseline: $bFile ($($inv.Count) files)"
} elseif ($Compare) {
    Header "Comparing Against Baseline"
    $latest = Get-ChildItem "$BaselineDir\webroot-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Error "No baseline found"; exit 1 }
    Info "Using: $($latest.Name)"
    $bl = Get-Content $latest.FullName -Raw | ConvertFrom-Json
    $lookup = @{}; foreach ($e in $bl) { $lookup[$e.Path] = $e }
    $current = @{}
    foreach ($root in $webRoots) {
        foreach ($f in (Get-WebFiles $root)) {
            $current[$f.FullName] = $true
            $hash = (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            if (-not $lookup.ContainsKey($f.FullName)) {
                Finding "NEW: $($f.FullName) (Size: $($f.Length))"
            } elseif ($lookup[$f.FullName].SHA256 -ne $hash) {
                Finding "MODIFIED: $($f.FullName)"
            }
        }
    }
    $deleted = $lookup.Keys | Where-Object { -not $current.ContainsKey($_) }
    foreach ($d in $deleted) { Warn "DELETED: $d" }
} else {
    Header "Webshell Scan"
    $totalFindings = 0
    foreach ($root in $webRoots) {
        Info "Scanning: $root"
        $files = Get-WebFiles $root
        if (-not $files) { continue }
        Info "$($files.Count) web files"
        foreach ($f in $files) {
            try {
                $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $content) { continue }
                $matches = @(); $weight = 0
                foreach ($sp in $SuspiciousPatterns) {
                    if ($content -match $sp.Pattern) { $matches += $sp.Label; $weight += $sp.Weight }
                }
                $entropy = Get-FileEntropy $content
                if ($entropy -gt 5.5 -and $content.Length -gt 500) { $matches += "High entropy ($entropy)"; $weight += 5 }
                if ($content -match 'Request' -and $content -match '(Execute|eval|Process|cmd\.exe|powershell)') { $matches += "Request+Exec"; $weight += 8 }
                if ($matches.Count -gt 0 -and $weight -ge 6) {
                    $totalFindings++
                    $hash = (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    Finding "$($f.FullName) (Risk: $weight, Patterns: $($matches -join ', '))"
                    Write-Host "    SHA256: $hash" -ForegroundColor DarkGray
                    if ($Quarantine -and $weight -ge 10) { Move-ToQuarantine $f.FullName }
                }
            } catch {}
        }
    }
    if ($totalFindings -gt 0) { Finding "$totalFindings suspicious file(s)" } else { Success "No webshells detected" }
    if ($OutputFile -and $totalFindings -gt 0) { "Scan complete: $totalFindings findings" | Out-File $OutputFile -Encoding UTF8 }
}

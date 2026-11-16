#Requires -RunAsAdministrator
# CCDC26 Dovetail - Windows Log Archival
# Collects all event logs, IIS logs, DNS logs, firewall logs into a timestamped ZIP

$ErrorActionPreference = "Continue"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$TempDir = Join-Path $env:TEMP "ccdc26-logs-$Timestamp"
$ArchiveDir = "C:\ccdc26\logs"
$ArchivePath = Join-Path $ArchiveDir "log-archive-$Timestamp.zip"

function Info  { param([string]$M) Write-Host "[INFO] " -ForegroundColor Blue -NoNewline; Write-Host $M }
function Ok    { param([string]$M) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $M }
function Warn  { param([string]$M) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $M }

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null

# ── Event logs ──
$EventLogDir = Join-Path $TempDir "EventLogs"
New-Item -ItemType Directory -Path $EventLogDir -Force | Out-Null

$EventLogs = @(
    "Security", "System", "Application",
    "Microsoft-Windows-PowerShell/Operational",
    "Microsoft-Windows-Sysmon/Operational",
    "Microsoft-Windows-Windows Defender/Operational"
)

foreach ($log in $EventLogs) {
    $safeName = $log -replace '[/\\]', '_'
    $outFile = Join-Path $EventLogDir "$safeName.evtx"
    Info "Exporting event log: $log"
    try {
        wevtutil epl $log $outFile 2>$null
        if (Test-Path $outFile) { Ok "  Exported $safeName.evtx" }
        else { Warn "  Log not available: $log" }
    } catch {
        Warn "  Failed to export: $log"
    }
}

# ── IIS logs ──
$IISSource = "C:\inetpub\logs"
if (Test-Path $IISSource) {
    Info "Copying IIS logs..."
    $IISDest = Join-Path $TempDir "IIS"
    Copy-Item -Path $IISSource -Destination $IISDest -Recurse -Force -ErrorAction SilentlyContinue
    Ok "  IIS logs copied"
} else {
    Warn "IIS logs not found at $IISSource"
}

# ── DNS logs ──
$DNSSource = "C:\Windows\System32\dns"
if (Test-Path $DNSSource) {
    Info "Copying DNS logs..."
    $DNSDest = Join-Path $TempDir "DNS"
    Copy-Item -Path $DNSSource -Destination $DNSDest -Recurse -Force -ErrorAction SilentlyContinue
    Ok "  DNS logs copied"
} else {
    Warn "DNS logs not found at $DNSSource"
}

# ── Firewall logs ──
$FWSource = Join-Path $env:SystemRoot "system32\LogFiles\Firewall"
if (Test-Path $FWSource) {
    Info "Copying firewall logs..."
    $FWDest = Join-Path $TempDir "Firewall"
    Copy-Item -Path $FWSource -Destination $FWDest -Recurse -Force -ErrorAction SilentlyContinue
    Ok "  Firewall logs copied"
} else {
    Warn "Firewall logs not found at $FWSource"
}

# ── PowerShell transcripts ──
$PSSource = "C:\ccdc26\logs\powershell"
if (Test-Path $PSSource) {
    Info "Copying PowerShell transcripts..."
    $PSDest = Join-Path $TempDir "PowerShell"
    Copy-Item -Path $PSSource -Destination $PSDest -Recurse -Force -ErrorAction SilentlyContinue
    Ok "  PowerShell transcripts copied"
} else {
    Warn "PowerShell transcripts not found at $PSSource"
}

# ── Compress ──
Info "Compressing to $ArchivePath ..."
Compress-Archive -Path "$TempDir\*" -DestinationPath $ArchivePath -Force

if (Test-Path $ArchivePath) {
    $size = (Get-Item $ArchivePath).Length
    $sizeMB = [math]::Round($size / 1MB, 2)
    Ok "Archive created: $ArchivePath ($sizeMB MB)"
} else {
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host "Failed to create archive"
    exit 1
}

# ── Cleanup ──
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Ok "Temp directory cleaned up. Done."

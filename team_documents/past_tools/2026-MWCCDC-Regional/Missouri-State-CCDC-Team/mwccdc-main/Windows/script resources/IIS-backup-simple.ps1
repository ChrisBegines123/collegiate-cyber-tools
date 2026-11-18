# ==============================================================================
# Script Name : IIS-backup-simple.ps1
# Description : CCDC-friendly IIS backup (config + content + registry + native IIS backup)
# Usage       : .\IIS-backup-simple.ps1
#               .\IIS-backup-simple.ps1 -BackupRoot "D:\Backup" -IncludeInetpub -Compress
# Notes       : Run as Administrator
# ==============================================================================

param(
    [string]$BackupRoot = "C:\Backup",
    [switch]$IncludeInetpub,          # include C:\inetpub (can be big)
    [switch]$ExportFullRegistry,      # exports HKLM/HKCU full (very large)
    [switch]$Compress                # zip the backup folder
)

# -------------------------
# Helpers
# -------------------------
function New-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupRoot "IIS_Backup_$ts"
$logDir    = Join-Path $backupDir "Logs"
New-Dir $backupDir
New-Dir $logDir
$logFile = Join-Path $logDir "backup_$ts.log"

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","OK")][string]$Level="INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$stamp] [$Level] $Message"
    $line | Out-File -FilePath $logFile -Append -Encoding utf8
    switch ($Level) {
        "INFO" { Write-Host $line -ForegroundColor Gray }
        "WARN" { Write-Host $line -ForegroundColor Yellow }
        "ERROR"{ Write-Host $line -ForegroundColor Red }
        "OK"   { Write-Host $line -ForegroundColor Green }
    }
}

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "Must run as Administrator." "ERROR"
        throw "Not Admin"
    }
}

function Try-ImportWebAdmin {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        Write-Log "WebAdministration module loaded." "OK"
        return $true
    } catch {
        Write-Log "WebAdministration module not available: $_" "WARN"
        return $false
    }
}

# -------------------------
# Start
# -------------------------
Assert-Admin
Write-Log "Starting IIS backup" "INFO"
Write-Log "Backup directory: $backupDir" "INFO"

# -------------------------
# 1) Copy IIS config directory (inetsrv)
# -------------------------
$srcInetsrv = Join-Path $env:windir "System32\inetsrv"
$dstInetsrv = Join-Path $backupDir "inetsrv"
if (Test-Path $srcInetsrv) {
    Write-Log "Copying $srcInetsrv -> $dstInetsrv" "INFO"
    Copy-Item $srcInetsrv -Destination $dstInetsrv -Recurse -Force -ErrorAction Stop
    Write-Log "Copied inetsrv successfully." "OK"
} else {
    Write-Log "Not found: $srcInetsrv (Is IIS installed?)" "WARN"
}

# -------------------------
# 2) Optional: Copy inetpub (site content/logs)
# -------------------------
if ($IncludeInetpub) {
    $srcInetpub = Join-Path $env:SystemDrive "inetpub"
    $dstInetpub = Join-Path $backupDir "inetpub"
    if (Test-Path $srcInetpub) {
        Write-Log "Copying $srcInetpub -> $dstInetpub (may take time)" "INFO"
        Copy-Item $srcInetpub -Destination $dstInetpub -Recurse -Force -ErrorAction Stop
        Write-Log "Copied inetpub successfully." "OK"
    } else {
        Write-Log "Not found: $srcInetpub" "WARN"
    }
} else {
    Write-Log "Skipping inetpub copy (use -IncludeInetpub to include content)." "INFO"
}

# -------------------------
# 3) Registry export (IIS-specific + optional full)
# -------------------------
$regDir = Join-Path $backupDir "registry"
New-Dir $regDir

Write-Log "Exporting IIS-related registry keys" "INFO"
reg export "HKLM\SOFTWARE\Microsoft\InetStp" (Join-Path $regDir "IIS_InetStp.reg") /y | Out-Null
reg export "HKLM\SYSTEM\CurrentControlSet\Services\W3SVC" (Join-Path $regDir "IIS_W3SVC.reg") /y | Out-Null
Write-Log "Registry export (IIS keys) done." "OK"

if ($ExportFullRegistry) {
    Write-Log "Exporting FULL HKLM/HKCU registry (this is large/slow)" "WARN"
    reg export "HKLM" (Join-Path $regDir "HKLM_FULL.reg") /y | Out-Null
    reg export "HKCU" (Join-Path $regDir "HKCU_FULL.reg") /y | Out-Null
    Write-Log "Full registry export done." "OK"
} else {
    Write-Log "Skipping full registry export (use -ExportFullRegistry if needed)." "INFO"
}

# -------------------------
# 4) Native IIS configuration backup (best for restore)
# -------------------------
$hasWebAdmin = Try-ImportWebAdmin
$iisNativeDir = Join-Path $backupDir "iis_native_backup"
New-Dir $iisNativeDir

if ($hasWebAdmin) {
    try {
        $nativeName = "CCDC_$ts"
        Write-Log "Creating native IIS backup: Backup-WebConfiguration -Name $nativeName" "INFO"
        Backup-WebConfiguration -Name $nativeName | Out-Null

        # Copy native backup folder from inetsrv\backup
        $nativeSrc = Join-Path $env:windir "System32\inetsrv\backup\$nativeName"
        if (Test-Path $nativeSrc) {
            Copy-Item $nativeSrc -Destination (Join-Path $iisNativeDir $nativeName) -Recurse -Force
            Write-Log "Copied native IIS backup from $nativeSrc" "OK"
        } else {
            Write-Log "Native backup folder not found at $nativeSrc (still may have succeeded depending on system)." "WARN"
        }
    } catch {
        Write-Log "Native IIS backup failed: $_" "WARN"
    }
} else {
    Write-Log "Skipping native IIS backup (WebAdministration not available)." "WARN"
}

# -------------------------
# 5) appcmd snapshots (good for quick compare/manual rebuild)
# -------------------------
$appcmd = Join-Path $env:windir "System32\inetsrv\appcmd.exe"
$snapDir = Join-Path $backupDir "appcmd"
New-Dir $snapDir

if (Test-Path $appcmd) {
    Write-Log "Capturing appcmd snapshots" "INFO"
    & $appcmd list site /config  > (Join-Path $snapDir "sites.txt")
    & $appcmd list apppool /config > (Join-Path $snapDir "apppools.txt")
    & $appcmd list app /config > (Join-Path $snapDir "apps.txt")
    & $appcmd list vdir /config > (Join-Path $snapDir "vdirs.txt")
    Write-Log "appcmd snapshots saved." "OK"
} else {
    Write-Log "appcmd not found at $appcmd" "WARN"
}

# -------------------------
# 6) Metadata
# -------------------------
$meta = Join-Path $backupDir "metadata.txt"
@"
Backup Time:   $(Get-Date)
ComputerName:  $env:COMPUTERNAME
User:          $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
OS:            $((Get-CimInstance Win32_OperatingSystem).Caption)
IncludeInetpub:$IncludeInetpub
FullRegistry:  $ExportFullRegistry
"@ | Out-File -FilePath $meta -Encoding utf8

Write-Log "Metadata written to $meta" "OK"

# -------------------------
# 7) Optional compress
# -------------------------
if ($Compress) {
    try {
        $zipPath = Join-Path $BackupRoot "IIS_Backup_$ts.zip"
        Write-Log "Compressing backup to $zipPath" "INFO"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Compress-Archive -Path $backupDir -DestinationPath $zipPath -Force
        Write-Log "Compression complete." "OK"
    } catch {
        Write-Log "Compression failed: $_" "WARN"
    }
} else {
    Write-Log "Skipping compression (use -Compress to zip)." "INFO"
}

Write-Log "Backup complete: $backupDir" "OK"
Write-Host ""
Write-Host "=== BACKUP COMPLETE ===" -ForegroundColor Cyan
Write-Host "Path: $backupDir" -ForegroundColor Green
Write-Host "Log : $logFile" -ForegroundColor Gray

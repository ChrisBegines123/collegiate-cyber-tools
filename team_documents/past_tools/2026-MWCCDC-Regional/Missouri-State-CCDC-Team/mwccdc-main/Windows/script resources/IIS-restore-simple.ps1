# ==============================================================================
# Script Name : IIS-restore-simple.ps1
# Description : CCDC-friendly IIS restore for backups created by IIS-backup-simple.ps1
# Usage       : .\IIS-restore-simple.ps1 -BackupPath "C:\Backup\IIS_Backup_YYYYMMDD_HHMMSS"
#             : .\IIS-restore-simple.ps1 -BackupPath "C:\Backup\IIS_Backup_..." -RestoreInetpub
# Notes       : Run as Administrator. Prefer testing in a maintenance window.
# ==============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,

    [switch]$RestoreInetpub,          # restore C:\inetpub from backup (if present)
    [switch]$RestoreRegistry,         # import IIS-related registry .reg files
    [switch]$Force                    # skip interactive confirmation
)

# -------------------------
# Helpers
# -------------------------
function New-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","OK")][string]$Level="INFO"
    )

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$stamp] [$Level] $Message"
    $line | Out-File -FilePath $script:LogFile -Append -Encoding utf8

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
        throw "Must run as Administrator."
    }
}

function Stop-IIS {
    Write-Log "Stopping IIS services (WAS, W3SVC)" "INFO"
    Stop-Service WAS  -Force -ErrorAction SilentlyContinue
    Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
}

function Start-IIS {
    Write-Log "Starting IIS services (WAS, W3SVC)" "INFO"
    Start-Service WAS  -ErrorAction SilentlyContinue
    Start-Service W3SVC -ErrorAction SilentlyContinue
}

function Try-ImportWebAdmin {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        Write-Log "WebAdministration module loaded." "OK"
        return $true
    } catch {
        Write-Log "WebAdministration not available: $_" "WARN"
        return $false
    }
}

# -------------------------
# Validate
# -------------------------
Assert-Admin

if (-not (Test-Path $BackupPath)) {
    throw "BackupPath not found: $BackupPath"
}

$logDir = Join-Path $BackupPath "Logs"
New-Dir $logDir
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogFile = Join-Path $logDir "restore_$ts.log"

Write-Log "Starting IIS restore" "INFO"
Write-Log "BackupPath: $BackupPath" "INFO"

# Show what we found
$hasInetsrvBackup = Test-Path (Join-Path $BackupPath "inetsrv")
$hasInetpubBackup = Test-Path (Join-Path $BackupPath "inetpub")
$hasRegBackup     = Test-Path (Join-Path $BackupPath "registry")
$hasNativeBackup  = Test-Path (Join-Path $BackupPath "iis_native_backup")

Write-Log "Detected: inetsrv=$hasInetsrvBackup, inetpub=$hasInetpubBackup, registry=$hasRegBackup, native=$hasNativeBackup" "INFO"

# -------------------------
# Confirm
# -------------------------
if (-not $Force) {
    Write-Host ""
    Write-Host "WARNING: This will restore IIS configuration from backup and may overwrite current settings." -ForegroundColor Yellow
    Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
    Write-Host ""
    $ans = Read-Host "Type YES to continue"
    if ($ans -ne "YES") {
        Write-Log "User cancelled restore." "WARN"
        exit 0
    }
}

# -------------------------
# Step 0: Pre-backup current config (safety net)
# -------------------------
try {
    $currentSafetyDir = Join-Path $BackupPath "current_before_restore_$ts"
    New-Dir $currentSafetyDir
    $srcInetsrv = Join-Path $env:windir "System32\inetsrv"
    if (Test-Path $srcInetsrv) {
        Copy-Item $srcInetsrv -Destination (Join-Path $currentSafetyDir "inetsrv_current") -Recurse -Force -ErrorAction Stop
        Write-Log "Safety copy of current inetsrv saved to: $currentSafetyDir" "OK"
    } else {
        Write-Log "Current inetsrv not found at $srcInetsrv (IIS may not be installed)." "WARN"
    }
} catch {
    Write-Log "Failed to create safety copy of current config: $_" "WARN"
}

# -------------------------
# Step 1: Restore IIS config (preferred)
# -------------------------
Stop-IIS

# 1A) Restore full inetsrv folder (recommended, includes config + history + etc.)
if ($hasInetsrvBackup) {
    try {
        $dst = Join-Path $env:windir "System32\inetsrv"
        $src = Join-Path $BackupPath "inetsrv"

        Write-Log "Restoring inetsrv folder: $src -> $dst" "INFO"

        # Copy backup inetsrv on top of destination
        # (This avoids trying to surgically copy only a few files.)
        Copy-Item $src -Destination $dst -Recurse -Force -ErrorAction Stop

        Write-Log "inetsrv restore completed." "OK"
    } catch {
        Write-Log "inetsrv restore failed: $_" "ERROR"
    }
} else {
    Write-Log "No inetsrv backup found; skipping inetsrv restore." "WARN"
}

# 1B) If native backup exists, optionally copy into IIS backup folder (doesn't auto-restore)
#     This is mostly for convenience; true restore would require system-level consistency.
if ($hasNativeBackup) {
    try {
        $nativeRoot = Join-Path $BackupPath "iis_native_backup"
        $nativeNames = Get-ChildItem -Path $nativeRoot -Directory -ErrorAction SilentlyContinue
        if ($nativeNames.Count -gt 0) {
            $destNativeRoot = Join-Path $env:windir "System32\inetsrv\backup"
            New-Dir $destNativeRoot
            foreach ($n in $nativeNames) {
                Copy-Item $n.FullName -Destination (Join-Path $destNativeRoot $n.Name) -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Native backup folders copied into $destNativeRoot (if supported by OS/IIS)." "OK"
            Write-Log "If needed you can restore via: Restore-WebConfiguration -Name <folderName> (when available)." "INFO"
        } else {
            Write-Log "Native backup folder exists but no subfolders found." "WARN"
        }
    } catch {
        Write-Log "Copying native backups failed: $_" "WARN"
    }
} else {
    Write-Log "No native IIS backup folder found; skipping." "INFO"
}

Start-IIS

# Optional: iisreset to make sure services reload config
try {
    Write-Log "Running iisreset /noforce" "INFO"
    iisreset /noforce | Out-Null
    Write-Log "iisreset complete." "OK"
} catch {
    Write-Log "iisreset failed: $_" "WARN"
}

# -------------------------
# Step 2: Optional restore inetpub content
# -------------------------
if ($RestoreInetpub) {
    if ($hasInetpubBackup) {
        try {
            Stop-IIS
            $src = Join-Path $BackupPath "inetpub"
            $dst = Join-Path $env:SystemDrive "inetpub"
            Write-Log "Restoring inetpub: $src -> $dst (may take time)" "INFO"
            Copy-Item $src -Destination $dst -Recurse -Force -ErrorAction Stop
            Write-Log "inetpub restore completed." "OK"
            Start-IIS
            iisreset /noforce | Out-Null
        } catch {
            Write-Log "inetpub restore failed: $_" "ERROR"
            Start-IIS
        }
    } else {
        Write-Log "RestoreInetpub requested but inetpub backup not found; skipping." "WARN"
    }
} else {
    Write-Log "Skipping inetpub restore (use -RestoreInetpub to restore site content)." "INFO"
}

# -------------------------
# Step 3: Optional registry restore (IIS-related)
# -------------------------
if ($RestoreRegistry) {
    if ($hasRegBackup) {
        try {
            $regDir = Join-Path $BackupPath "registry"
            $iisReg = Join-Path $regDir "IIS_InetStp.reg"
            $w3Reg  = Join-Path $regDir "IIS_W3SVC.reg"

            if (Test-Path $iisReg) {
                Write-Log "Importing registry: $iisReg" "INFO"
                reg import $iisReg | Out-Null
                Write-Log "Imported IIS_InetStp.reg" "OK"
            } else { Write-Log "Missing: $iisReg" "WARN" }

            if (Test-Path $w3Reg) {
                Write-Log "Importing registry: $w3Reg" "INFO"
                reg import $w3Reg | Out-Null
                Write-Log "Imported IIS_W3SVC.reg" "OK"
            } else { Write-Log "Missing: $w3Reg" "WARN" }

            # Full registry imports are intentionally NOT automated.
            Write-Log "Registry restore done. (Full HKLM/HKCU import not automated for safety.)" "OK"
        } catch {
            Write-Log "Registry restore failed: $_" "ERROR"
        }
    } else {
        Write-Log "RestoreRegistry requested but registry backup not found; skipping." "WARN"
    }
} else {
    Write-Log "Skipping registry restore (use -RestoreRegistry to import IIS keys)." "INFO"
}

# -------------------------
# Step 4: Post-checks
# -------------------------
$hasWebAdmin = Try-ImportWebAdmin
if ($hasWebAdmin) {
    try {
        Write-Log "Post-check: listing sites and app pools" "INFO"
        $sites = Get-Website | Select-Object Name, State, PhysicalPath
        $apps  = Get-ChildItem IIS:\AppPools | Select-Object Name, State

        $outDir = Join-Path $BackupPath "postcheck_$ts"
        New-Dir $outDir
        $sites | Format-Table -AutoSize | Out-String | Out-File (Join-Path $outDir "sites.txt")
        $apps  | Format-Table -AutoSize | Out-String | Out-File (Join-Path $outDir "apppools.txt")

        Write-Log "Post-check outputs saved to $outDir" "OK"
    } catch {
        Write-Log "Post-check failed: $_" "WARN"
    }
} else {
    Write-Log "Skipping post-checks (WebAdministration not available)." "WARN"
}

Write-Host ""
Write-Host "=== RESTORE COMPLETE ===" -ForegroundColor Cyan
Write-Host "Backup: $BackupPath" -ForegroundColor Green
Write-Host "Log   : $script:LogFile" -ForegroundColor Gray
Write-Host ""
Write-Host "Notes:" -ForegroundColor Yellow
Write-Host "- HTTPS cert rebinding may still be needed if certs/private keys are missing." -ForegroundColor Yellow
Write-Host "- If you restored inetpub, verify site folder permissions (IIS_IUSRS, AppPool identity)." -ForegroundColor Yellow

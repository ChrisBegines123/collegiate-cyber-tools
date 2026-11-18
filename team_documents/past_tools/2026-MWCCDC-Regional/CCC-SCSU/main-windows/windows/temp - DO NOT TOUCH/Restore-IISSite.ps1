#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores an IIS website from a ZIP backup created by Backup-IISSite.ps1.

.PARAMETER BackupPath
    Path to the backup ZIP file. If omitted, uses the most recent
    IISSite_*.zip in the current working directory.

.PARAMETER Force
    Skip confirmation prompt.

.PARAMETER RestorePath
    Override the physical path to restore content to.
    Defaults to the original path stored in the backup.

.EXAMPLE
    .\Restore-IISSite.ps1
    .\Restore-IISSite.ps1 -BackupPath ".\IISSite_Default_Web_Site_20240101_120000.zip"
#>

param(
    [string]$BackupPath  = "",
    [string]$RestorePath = "",
    [switch]$Force
)

# ─── Prerequisites ────────────────────────────────────────────────────────────
Import-Module WebAdministration -ErrorAction Stop

# ─── Resolve backup file ──────────────────────────────────────────────────────
if (-not $BackupPath) {
    $latest = Get-ChildItem -Path (Get-Location).Path -Filter "IISSite_*.zip" |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $BackupPath = $latest.FullName
        Write-Host "[*] Using most recent backup: $BackupPath" -ForegroundColor Cyan
    } else {
        Write-Host "[-] No backup ZIP found. Specify -BackupPath." -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $BackupPath)) {
    Write-Host "[-] Backup file not found: $BackupPath" -ForegroundColor Red
    exit 1
}

# ─── Extract to staging ───────────────────────────────────────────────────────
$stagingDir = Join-Path $env:TEMP ("IISSiteRestore_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
Write-Host "[*] Extracting backup..." -ForegroundColor Cyan
Expand-Archive -Path $BackupPath -DestinationPath $stagingDir -Force

# ─── Load metadata ────────────────────────────────────────────────────────────
$metaFile = Join-Path $stagingDir "metadata.json"
if (-not (Test-Path $metaFile)) {
    Write-Host "[-] metadata.json not found in backup. File may be corrupt." -ForegroundColor Red
    exit 1
}
$meta = Get-Content $metaFile -Raw | ConvertFrom-Json
Write-Host "[+] Backup metadata loaded." -ForegroundColor Green
Write-Host "    Site     : $($meta.SiteName)" -ForegroundColor White
Write-Host "    App Pool : $($meta.AppPool)" -ForegroundColor White
Write-Host "    Exported : $($meta.ExportedAt)" -ForegroundColor White
Write-Host "    Source   : $($meta.Hostname)" -ForegroundColor White

# ─── Confirm ─────────────────────────────────────────────────────────────────
if (-not $Force) {
    $existing = Get-Website -Name $meta.SiteName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "`n[!] Site '$($meta.SiteName)' already exists and will be overwritten." -ForegroundColor Yellow
    }
    $confirm = Read-Host "`n    Type YES to restore '$($meta.SiteName)'"
    if ($confirm -ne "YES") {
        Write-Host "[*] Aborted." -ForegroundColor Cyan
        Remove-Item $stagingDir -Recurse -Force
        exit 0
    }
}

$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"

# ─── Restore app pool ─────────────────────────────────────────────────────────
Write-Host "`n[*] Restoring app pool '$($meta.AppPool)'..." -ForegroundColor Cyan
$poolXml = Join-Path $stagingDir "apppool-config.xml"

$existingPool = Get-WebConfiguration "system.applicationHost/applicationPools/add[@name='$($meta.AppPool)']"
if ($existingPool) {
    Write-Host "    App pool already exists — skipping creation." -ForegroundColor Yellow
} else {
    & $appcmd add apppool /in < $poolXml | Out-Null
    Write-Host "[+] App pool restored." -ForegroundColor Green
}

# ─── Restore content files ────────────────────────────────────────────────────
$targetPath = if ($RestorePath) { $RestorePath } else { [System.Environment]::ExpandEnvironmentVariables($meta.PhysicalPath) }
$contentSrc = Join-Path $stagingDir "content"

if (Test-Path $contentSrc) {
    Write-Host "[*] Restoring content to: $targetPath" -ForegroundColor Cyan
    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }
    Copy-Item -Path "$contentSrc\*" -Destination $targetPath -Recurse -Force
    Write-Host "[+] Content restored." -ForegroundColor Green
} else {
    Write-Host "[!] No content folder in backup — skipping file restore." -ForegroundColor Yellow
}

# ─── Remove existing site if present ─────────────────────────────────────────
$existing = Get-Website -Name $meta.SiteName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[*] Removing existing site '$($meta.SiteName)'..." -ForegroundColor Cyan
    Stop-Website -Name $meta.SiteName -ErrorAction SilentlyContinue
    Remove-Website -Name $meta.SiteName
    Write-Host "[+] Existing site removed." -ForegroundColor Green
}

# ─── Restore site via appcmd ──────────────────────────────────────────────────
Write-Host "[*] Restoring site configuration..." -ForegroundColor Cyan
$configXml = Join-Path $stagingDir "site-config.xml"
& $appcmd add site /in < $configXml | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "[-] appcmd failed to restore site." -ForegroundColor Red
    Remove-Item $stagingDir -Recurse -Force
    exit 1
}
Write-Host "[+] Site configuration restored." -ForegroundColor Green

# ─── Update physical path if overridden ──────────────────────────────────────
if ($RestorePath) {
    Set-ItemProperty "IIS:\Sites\$($meta.SiteName)" -Name physicalPath -Value $RestorePath
    Write-Host "[+] Physical path updated to: $RestorePath" -ForegroundColor Green
}

# ─── Start site ───────────────────────────────────────────────────────────────
Start-Website -Name $meta.SiteName -ErrorAction SilentlyContinue
$state = (Get-Website -Name $meta.SiteName).State
Write-Host "[+] Site state: $state" -ForegroundColor Green

# ─── Cleanup ──────────────────────────────────────────────────────────────────
Remove-Item $stagingDir -Recurse -Force

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  IIS Site Restore Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Site    : $($meta.SiteName)" -ForegroundColor White
Write-Host "  Path    : $targetPath" -ForegroundColor White
Write-Host "  State   : $state" -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor Cyan

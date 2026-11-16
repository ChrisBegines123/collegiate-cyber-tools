#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores an IIS FTP site from a ZIP backup created by Backup-IISFtp.ps1.

.PARAMETER BackupPath
    Path to the backup ZIP. If omitted, uses the most recent IISFtp_*.zip
    in the current working directory.

.PARAMETER RestorePath
    Override the physical root path for the FTP content.
    Defaults to the original path stored in the backup.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Restore-IISFtp.ps1
    .\Restore-IISFtp.ps1 -BackupPath ".\IISFtp_Default_FTP_Site_20240101_120000.zip"
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
    $latest = Get-ChildItem -Path (Get-Location).Path -Filter "IISFtp_*.zip" |
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

# ─── Extract ──────────────────────────────────────────────────────────────────
$stagingDir = Join-Path $env:TEMP ("IISFtpRestore_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
Write-Host "[*] Extracting backup..." -ForegroundColor Cyan
Expand-Archive -Path $BackupPath -DestinationPath $stagingDir -Force

# ─── Load metadata ────────────────────────────────────────────────────────────
$metaFile = Join-Path $stagingDir "metadata.json"
if (-not (Test-Path $metaFile)) {
    Write-Host "[-] metadata.json missing — backup may be corrupt." -ForegroundColor Red
    exit 1
}
$meta = Get-Content $metaFile -Raw | ConvertFrom-Json

Write-Host "[+] Metadata loaded." -ForegroundColor Green
Write-Host "    FTP Site     : $($meta.FtpSiteName)" -ForegroundColor White
Write-Host "    App Pool     : $($meta.AppPool)" -ForegroundColor White
Write-Host "    Exported     : $($meta.ExportedAt)" -ForegroundColor White
Write-Host "    Source host  : $($meta.Hostname)" -ForegroundColor White
Write-Host "    User folders : $($meta.UserDirectories.Count)" -ForegroundColor White

# ─── Confirm ─────────────────────────────────────────────────────────────────
if (-not $Force) {
    $existing = Get-Website -Name $meta.FtpSiteName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "`n[!] FTP site '$($meta.FtpSiteName)' already exists and will be overwritten." -ForegroundColor Yellow
    }
    $confirm = Read-Host "`n    Type YES to restore '$($meta.FtpSiteName)'"
    if ($confirm -ne "YES") {
        Write-Host "[*] Aborted." -ForegroundColor Cyan
        Remove-Item $stagingDir -Recurse -Force
        exit 0
    }
}

$appcmd     = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$targetPath = if ($RestorePath) { $RestorePath } else { [System.Environment]::ExpandEnvironmentVariables($meta.PhysicalPath) }

# ─── Restore app pool ─────────────────────────────────────────────────────────
Write-Host "`n[*] Restoring app pool '$($meta.AppPool)'..." -ForegroundColor Cyan
$poolXml      = Join-Path $stagingDir "ftp-apppool-config.xml"
$existingPool = Get-WebConfiguration "system.applicationHost/applicationPools/add[@name='$($meta.AppPool)']"

if ($existingPool) {
    Write-Host "    App pool already exists — skipping." -ForegroundColor Yellow
} else {
    & $appcmd add apppool /in < $poolXml | Out-Null
    Write-Host "[+] App pool restored." -ForegroundColor Green
}

# ─── Restore FTP content files ────────────────────────────────────────────────
$contentSrc = Join-Path $stagingDir "ftp-content"

if (Test-Path $contentSrc) {
    Write-Host "[*] Restoring FTP content to: $targetPath" -ForegroundColor Cyan

    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    # Restore each user directory individually so we can report on them
    $restoredDirs = 0
    Get-ChildItem -Path $contentSrc | ForEach-Object {
        $dest = Join-Path $targetPath $_.Name
        Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
        $restoredDirs++
        Write-Host "    Restored: $($_.Name)" -ForegroundColor White
    }
    Write-Host "[+] FTP content restored ($restoredDirs item(s))." -ForegroundColor Green
} else {
    Write-Host "[!] No ftp-content folder in backup — skipping file restore." -ForegroundColor Yellow
}

# ─── Remove existing FTP site if present ──────────────────────────────────────
$existing = Get-Website -Name $meta.FtpSiteName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[*] Removing existing FTP site '$($meta.FtpSiteName)'..." -ForegroundColor Cyan
    Stop-Website -Name $meta.FtpSiteName -ErrorAction SilentlyContinue
    Remove-Website -Name $meta.FtpSiteName
    Write-Host "[+] Existing site removed." -ForegroundColor Green
}

# ─── Restore FTP site via appcmd ──────────────────────────────────────────────
Write-Host "[*] Restoring FTP site configuration..." -ForegroundColor Cyan
$siteXml = Join-Path $stagingDir "ftp-site-config.xml"
& $appcmd add site /in < $siteXml | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "[-] appcmd failed to restore FTP site." -ForegroundColor Red
    Remove-Item $stagingDir -Recurse -Force
    exit 1
}
Write-Host "[+] FTP site configuration restored." -ForegroundColor Green

# ─── Override physical path if requested ─────────────────────────────────────
if ($RestorePath) {
    Set-ItemProperty "IIS:\Sites\$($meta.FtpSiteName)" -Name physicalPath -Value $RestorePath
    Write-Host "[+] Physical path updated to: $RestorePath" -ForegroundColor Green
}

# ─── Restore FTP-specific config sections ────────────────────────────────────
Write-Host "[*] Restoring FTP configuration sections..." -ForegroundColor Cyan
$ftpConfigDir = Join-Path $stagingDir "ftp-config"
$sitePSPath   = "IIS:\Sites\$($meta.FtpSiteName)"

# Authorization rules
$authFile = Join-Path $ftpConfigDir "authorization-rules.json"
if (Test-Path $authFile) {
    try {
        $authRules = Get-Content $authFile -Raw | ConvertFrom-Json
        # Clear existing auth rules then re-add
        Clear-WebConfiguration "system.ftpServer/security/authorization" -PSPath $sitePSPath
        foreach ($rule in $authRules) {
            Add-WebConfiguration "system.ftpServer/security/authorization" -PSPath $sitePSPath -Value @{
                accessType  = $rule.accessType
                users       = $rule.users
                roles       = $rule.roles
                permissions = $rule.permissions
            }
        }
        Write-Host "[+] Authorization rules restored." -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not restore authorization rules: $_" -ForegroundColor Yellow
    }
}

# User isolation
$isoFile = Join-Path $ftpConfigDir "user-isolation.json"
if (Test-Path $isoFile) {
    try {
        $isoSetting = (Get-Content $isoFile -Raw | ConvertFrom-Json).mode
        Set-WebConfigurationProperty "system.ftpServer/userIsolation" -PSPath $sitePSPath -Name "mode" -Value $isoSetting
        Write-Host "[+] User isolation mode restored: $isoSetting" -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not restore user isolation setting: $_" -ForegroundColor Yellow
    }
}

# SSL policy
$sslFile = Join-Path $ftpConfigDir "ssl-policy.json"
if (Test-Path $sslFile) {
    try {
        $ssl = Get-Content $sslFile -Raw | ConvertFrom-Json
        Set-WebConfigurationProperty "system.ftpServer/security/ssl" -PSPath $sitePSPath -Name "controlChannelPolicy" -Value $ssl.controlChannelPolicy
        Set-WebConfigurationProperty "system.ftpServer/security/ssl" -PSPath $sitePSPath -Name "dataChannelPolicy"    -Value $ssl.dataChannelPolicy
        Write-Host "[+] SSL policy restored." -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not restore SSL policy: $_" -ForegroundColor Yellow
    }
}

# Messages
$msgFile = Join-Path $ftpConfigDir "messages.json"
if (Test-Path $msgFile) {
    try {
        $msgs = Get-Content $msgFile -Raw | ConvertFrom-Json
        if ($msgs.bannerMessage)    { Set-WebConfigurationProperty "system.ftpServer/messages" -PSPath $sitePSPath -Name "bannerMessage"    -Value $msgs.bannerMessage }
        if ($msgs.greetingMessage)  { Set-WebConfigurationProperty "system.ftpServer/messages" -PSPath $sitePSPath -Name "greetingMessage"  -Value $msgs.greetingMessage }
        if ($msgs.exitMessage)      { Set-WebConfigurationProperty "system.ftpServer/messages" -PSPath $sitePSPath -Name "exitMessage"      -Value $msgs.exitMessage }
        Write-Host "[+] FTP messages restored." -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not restore FTP messages: $_" -ForegroundColor Yellow
    }
}

# ─── Start the FTP site ───────────────────────────────────────────────────────
Start-Website -Name $meta.FtpSiteName -ErrorAction SilentlyContinue
$state = (Get-Website -Name $meta.FtpSiteName).State
Write-Host "[+] FTP site state: $state" -ForegroundColor Green

# ─── Cleanup ──────────────────────────────────────────────────────────────────
Remove-Item $stagingDir -Recurse -Force

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  IIS FTP Restore Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Site         : $($meta.FtpSiteName)" -ForegroundColor White
Write-Host "  Content path : $targetPath" -ForegroundColor White
Write-Host "  State        : $state" -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor Cyan

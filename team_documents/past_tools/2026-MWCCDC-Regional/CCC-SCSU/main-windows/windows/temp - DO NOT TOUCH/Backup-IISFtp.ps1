#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Backs up an IIS FTP site — config, authorization rules, and all user
    files — to a ZIP in the current working directory.

.PARAMETER FtpSiteName
    Name of the IIS FTP site to back up. Defaults to "Default FTP Site".

.PARAMETER OutputDir
    Where to write the backup ZIP. Defaults to the current working directory.

.EXAMPLE
    .\Backup-IISFtp.ps1
    .\Backup-IISFtp.ps1 -FtpSiteName "My FTP Site"
#>

param(
    [string]$FtpSiteName = "Default FTP Site",
    [string]$OutputDir   = (Get-Location).Path
)

# ─── Prerequisites ────────────────────────────────────────────────────────────
Import-Module WebAdministration -ErrorAction Stop

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$safeName   = $FtpSiteName -replace '[^a-zA-Z0-9_\-]', '_'
$stagingDir = Join-Path $env:TEMP "IISFtpBackup_${safeName}_${timestamp}"
$zipPath    = Join-Path $OutputDir "IISFtp_${safeName}_${timestamp}.zip"

New-Item -ItemType Directory -Path $stagingDir | Out-Null

Write-Host "[*] Backing up IIS FTP site: '$FtpSiteName'" -ForegroundColor Cyan

# ─── Verify FTP site exists ───────────────────────────────────────────────────
$site = Get-Website -Name $FtpSiteName -ErrorAction SilentlyContinue
if (-not $site) {
    Write-Host "[-] No IIS site found with name '$FtpSiteName'." -ForegroundColor Red
    Write-Host "    Available sites:" -ForegroundColor Yellow
    Get-Website | ForEach-Object { Write-Host "      - $($_.Name)" -ForegroundColor Yellow }
    exit 1
}

$appcmd     = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$physPath   = [System.Environment]::ExpandEnvironmentVariables((Get-ItemProperty "IIS:\Sites\$FtpSiteName").PhysicalPath)
$appPool    = (Get-ItemProperty "IIS:\Sites\$FtpSiteName").applicationPool

# ─── Export FTP site config via appcmd ───────────────────────────────────────
Write-Host "[*] Exporting FTP site configuration..." -ForegroundColor Cyan
$siteConfigPath = Join-Path $stagingDir "ftp-site-config.xml"
& $appcmd list site $FtpSiteName /config /xml > $siteConfigPath
Write-Host "[+] Site config exported." -ForegroundColor Green

# ─── Export app pool ──────────────────────────────────────────────────────────
$poolConfigPath = Join-Path $stagingDir "ftp-apppool-config.xml"
& $appcmd list apppool $appPool /config /xml > $poolConfigPath
Write-Host "[+] App pool '$appPool' config exported." -ForegroundColor Green

# ─── Export FTP-specific config from applicationHost.config ──────────────────
Write-Host "[*] Exporting FTP-specific configuration sections..." -ForegroundColor Cyan
$ftpConfigDir = Join-Path $stagingDir "ftp-config"
New-Item -ItemType Directory -Path $ftpConfigDir | Out-Null

# Authorization rules
$authRules = Get-WebConfiguration "system.ftpServer/security/authorization" -PSPath "IIS:\Sites\$FtpSiteName"
$authRules | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ftpConfigDir "authorization-rules.json") -Encoding UTF8

# SSL policy
$sslPolicy = Get-WebConfiguration "system.ftpServer/security/ssl" -PSPath "IIS:\Sites\$FtpSiteName"
$sslPolicy | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ftpConfigDir "ssl-policy.json") -Encoding UTF8

# User isolation settings
$userIsolation = Get-WebConfiguration "system.ftpServer/userIsolation" -PSPath "IIS:\Sites\$FtpSiteName"
$userIsolation | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ftpConfigDir "user-isolation.json") -Encoding UTF8

# Directory browsing
$dirBrowse = Get-WebConfiguration "system.ftpServer/directoryBrowse" -PSPath "IIS:\Sites\$FtpSiteName"
$dirBrowse | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ftpConfigDir "directory-browse.json") -Encoding UTF8

# Messages (banner, welcome, exit)
$messages = Get-WebConfiguration "system.ftpServer/messages" -PSPath "IIS:\Sites\$FtpSiteName"
$messages | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ftpConfigDir "messages.json") -Encoding UTF8

Write-Host "[+] FTP config sections exported." -ForegroundColor Green

# ─── Discover and catalogue user directories ──────────────────────────────────
Write-Host "[*] Cataloguing FTP user directories under: $physPath" -ForegroundColor Cyan

$userDirs = @()
if (Test-Path $physPath) {
    $userDirs = Get-ChildItem -Path $physPath -Directory | Select-Object -ExpandProperty Name
}

# ─── Export local FTP users (IIS Manager users) ───────────────────────────────
Write-Host "[*] Exporting IIS Manager / FTP user accounts..." -ForegroundColor Cyan
$iisUsers = @()
try {
    $iisUsers = Get-WebConfiguration "system.webServer/management/authentication/credentials/add" |
        Select-Object name, password, enabled
} catch {
    Write-Host "[!] Could not read IIS Manager users (may not be configured): $_" -ForegroundColor Yellow
}

# ─── Build metadata ───────────────────────────────────────────────────────────
$bindings = Get-WebBinding -Name $FtpSiteName | Select-Object protocol, bindingInformation, sslFlags

$meta = [PSCustomObject]@{
    ExportedAt      = (Get-Date -Format "o")
    Hostname        = $env:COMPUTERNAME
    FtpSiteName     = $FtpSiteName
    AppPool         = $appPool
    PhysicalPath    = (Get-ItemProperty "IIS:\Sites\$FtpSiteName").PhysicalPath
    State           = $site.State
    Bindings        = $bindings
    SiteId          = $site.Id
    UserDirectories = $userDirs
    IISUsers        = $iisUsers
}
$meta | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $stagingDir "metadata.json") -Encoding UTF8
Write-Host "[+] Metadata saved ($($userDirs.Count) user director(ies) found)." -ForegroundColor Green

# ─── Copy all FTP root files (user folders + root content) ───────────────────
if (Test-Path $physPath) {
    Write-Host "[*] Copying FTP root content from: $physPath" -ForegroundColor Cyan
    $contentDest = Join-Path $stagingDir "ftp-content"
    Copy-Item -Path $physPath -Destination $contentDest -Recurse -Force
    Write-Host "[+] FTP content copied ($($userDirs.Count) user folder(s))." -ForegroundColor Green
} else {
    Write-Host "[!] FTP physical path not found — config-only backup." -ForegroundColor Yellow
}

# ─── Compress to ZIP ─────────────────────────────────────────────────────────
Write-Host "[*] Compressing backup to: $zipPath" -ForegroundColor Cyan
Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stagingDir -Recurse -Force

if (Test-Path $zipPath) {
    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
    Write-Host "[+] Backup complete: $zipPath ($sizeMB MB)" -ForegroundColor Green
} else {
    Write-Host "[-] ZIP not found after compression." -ForegroundColor Red
    exit 1
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  IIS FTP Backup Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Site         : $FtpSiteName" -ForegroundColor White
Write-Host "  User folders : $($userDirs.Count)" -ForegroundColor White
Write-Host "  Output       : $zipPath" -ForegroundColor White
Write-Host "  Size         : $sizeMB MB" -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor Cyan

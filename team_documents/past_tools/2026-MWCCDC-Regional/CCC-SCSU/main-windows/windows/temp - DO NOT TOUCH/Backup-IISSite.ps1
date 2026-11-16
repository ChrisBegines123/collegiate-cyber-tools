#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Backs up an IIS website — config and content files — to a ZIP in the
    current working directory.

.PARAMETER SiteName
    Name of the IIS site to back up. Defaults to "Default Web Site".

.PARAMETER OutputDir
    Where to write the backup ZIP. Defaults to the current working directory.

.EXAMPLE
    .\Backup-IISSite.ps1
    .\Backup-IISSite.ps1 -SiteName "MyApp"
#>

param(
    [string]$SiteName  = "Default Web Site",
    [string]$OutputDir = (Get-Location).Path
)

# ─── Prerequisites ────────────────────────────────────────────────────────────
Import-Module WebAdministration -ErrorAction Stop

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$safeName   = $SiteName -replace '[^a-zA-Z0-9_\-]', '_'
$stagingDir = Join-Path $env:TEMP "IISSiteBackup_${safeName}_${timestamp}"
$zipPath    = Join-Path $OutputDir "IISSite_${safeName}_${timestamp}.zip"

New-Item -ItemType Directory -Path $stagingDir | Out-Null

Write-Host "[*] Backing up IIS site: '$SiteName'" -ForegroundColor Cyan

# ─── Verify site exists ───────────────────────────────────────────────────────
$site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if (-not $site) {
    Write-Host "[-] No IIS site found with name '$SiteName'." -ForegroundColor Red
    Write-Host "    Available sites:" -ForegroundColor Yellow
    Get-Website | ForEach-Object { Write-Host "      - $($_.Name)" -ForegroundColor Yellow }
    exit 1
}

# ─── Export site config via appcmd ───────────────────────────────────────────
Write-Host "[*] Exporting site configuration..." -ForegroundColor Cyan

$appcmd     = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$configPath = Join-Path $stagingDir "site-config.xml"

& $appcmd list site $SiteName /config /xml > $configPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "[-] appcmd failed to export site config." -ForegroundColor Red
    exit 1
}
Write-Host "[+] Site config exported." -ForegroundColor Green

# ─── Export app pool config ───────────────────────────────────────────────────
$appPoolName  = (Get-ItemProperty "IIS:\Sites\$SiteName").applicationPool
$poolPath     = Join-Path $stagingDir "apppool-config.xml"
& $appcmd list apppool $appPoolName /config /xml > $poolPath
Write-Host "[+] App pool '$appPoolName' config exported." -ForegroundColor Green

# ─── Export bindings and metadata as JSON ────────────────────────────────────
$bindings = Get-WebBinding -Name $SiteName | Select-Object protocol, bindingInformation, sslFlags
$physPath = (Get-ItemProperty "IIS:\Sites\$SiteName").PhysicalPath

$meta = [PSCustomObject]@{
    ExportedAt      = (Get-Date -Format "o")
    Hostname        = $env:COMPUTERNAME
    SiteName        = $SiteName
    AppPool         = $appPoolName
    PhysicalPath    = $physPath
    State           = $site.State
    Bindings        = $bindings
    SiteId          = $site.Id
}
$meta | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $stagingDir "metadata.json") -Encoding UTF8
Write-Host "[+] Metadata exported." -ForegroundColor Green

# ─── Copy website content files ───────────────────────────────────────────────
$resolvedPath = [System.Environment]::ExpandEnvironmentVariables($physPath)

if (Test-Path $resolvedPath) {
    Write-Host "[*] Copying site content from: $resolvedPath" -ForegroundColor Cyan
    $contentDest = Join-Path $stagingDir "content"
    Copy-Item -Path $resolvedPath -Destination $contentDest -Recurse -Force
    Write-Host "[+] Content copied." -ForegroundColor Green
} else {
    Write-Host "[!] Physical path '$resolvedPath' not found — config only backup." -ForegroundColor Yellow
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
Write-Host "  IIS Site Backup Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Site    : $SiteName" -ForegroundColor White
Write-Host "  Output  : $zipPath" -ForegroundColor White
Write-Host "  Size    : $sizeMB MB" -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor Cyan

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads the CCDC26 toolkit from GitHub and optionally runs hardening.
.DESCRIPTION
    NO USB allowed at competition. This script bootstraps the toolkit onto
    Windows machines via network download.
.EXAMPLE
    # Method 1: From GitHub directly
    irm https://raw.githubusercontent.com/byui-soc/ccdc26/main/dovetail/deploy.ps1 | iex

    # Method 2: From Linux HTTP server (if no internet)
    Invoke-WebRequest http://LINUX_IP:8080/dovetail/deploy.ps1 -OutFile deploy.ps1; .\deploy.ps1

    # Method 3: Auto-run blitz after download
    .\deploy.ps1 -RunBlitz
#>

param(
    [string]$RepoUrl = "https://github.com/byui-soc/ccdc26/archive/refs/heads/main.zip",
    [string]$DestPath = "C:\ccdc26",
    [switch]$RunBlitz
)

$ErrorActionPreference = "Stop"

function Write-Status { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor Cyan }
function Write-Good   { param([string]$Msg) Write-Host "[+] $Msg" -ForegroundColor Green }
function Write-Bad    { param([string]$Msg) Write-Host "[-] $Msg" -ForegroundColor Red }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CCDC26 Toolkit Deployer" -ForegroundColor Cyan
Write-Host "  Target: $DestPath" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$zipPath = "$env:TEMP\ccdc26-toolkit.zip"
$extractPath = "$env:TEMP\ccdc26-extract"

# Clean previous attempts
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

# Download ZIP
Write-Status "Downloading toolkit from $RepoUrl ..."
$downloaded = $false

try {
    Invoke-WebRequest -Uri $RepoUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
    if (Test-Path $zipPath) { $downloaded = $true; Write-Good "Downloaded via Invoke-WebRequest" }
} catch {
    Write-Status "Invoke-WebRequest failed, trying certutil fallback..."
}

if (-not $downloaded) {
    try {
        certutil -urlcache -split -f $RepoUrl $zipPath 2>$null | Out-Null
        if (Test-Path $zipPath) { $downloaded = $true; Write-Good "Downloaded via certutil" }
    } catch {}
}

if (-not $downloaded) {
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($RepoUrl, $zipPath)
        if (Test-Path $zipPath) { $downloaded = $true; Write-Good "Downloaded via WebClient" }
    } catch {}
}

if (-not $downloaded) {
    Write-Bad "All download methods failed. Check network connectivity."
    Write-Host "  Manual: download $RepoUrl and extract to $DestPath" -ForegroundColor Yellow
    exit 1
}

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Status "ZIP size: ${zipSize} MB"

# Extract
Write-Status "Extracting..."
try {
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
} catch {
    Write-Status "Expand-Archive failed, trying Shell.Application..."
    $shell = New-Object -ComObject Shell.Application
    $zip = $shell.Namespace($zipPath)
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    $dest = $shell.Namespace($extractPath)
    $dest.CopyHere($zip.Items(), 0x14)
    Start-Sleep -Seconds 5
}

# Handle GitHub's nested folder (ccdc26-main/)
$nested = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
$sourcePath = if ($nested -and $nested.Name -match '-main$|-master$') { $nested.FullName } else { $extractPath }

# Deploy to destination
New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
Copy-Item -Path "$sourcePath\*" -Destination $DestPath -Recurse -Force

# Cleanup
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

# Verify
$fileCount = (Get-ChildItem -Path $DestPath -Recurse -File).Count
Write-Good "Deployed $fileCount files to $DestPath"

# List key directories
Write-Host ""
Write-Status "Contents:"
Get-ChildItem -Path $DestPath -Directory | ForEach-Object {
    $count = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Host "  $($_.Name)/ ($count files)" -ForegroundColor Gray
}

# Run blitz if requested
if ($RunBlitz) {
    $blitzPath = Join-Path $DestPath "dovetail\scripts\01-blitz.ps1"
    if (Test-Path $blitzPath) {
        Write-Host ""
        Write-Status "Running 01-blitz.ps1 ..."
        & $blitzPath
    } else {
        Write-Bad "01-blitz.ps1 not found at $blitzPath"
    }
}

Write-Host ""
Write-Good "Deployment complete!"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  cd $DestPath\dovetail\scripts" -ForegroundColor Gray
Write-Host "  .\01-blitz.ps1          # Harden this machine" -ForegroundColor Gray
Write-Host "  .\00-snapshot.ps1       # Forensic baseline first" -ForegroundColor Gray
Write-Host ""

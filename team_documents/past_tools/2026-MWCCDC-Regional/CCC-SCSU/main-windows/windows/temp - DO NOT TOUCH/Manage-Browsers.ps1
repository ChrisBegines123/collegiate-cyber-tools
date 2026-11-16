#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls Microsoft Edge and installs Mozilla Firefox on Windows Server.

.DESCRIPTION
    This script:
      1. Removes Microsoft Edge (Chromium) using multiple methods for reliability
      2. Downloads the latest Firefox ESR installer from Mozilla
      3. Silently installs Firefox

.NOTES
    - Must be run as Administrator
    - Requires internet access to download Firefox
    - Tested on Windows Server 2016 / 2019 / 2022
#>

# ─── Configuration ────────────────────────────────────────────────────────────
$FirefoxInstallerUrl = "https://download.mozilla.org/?product=firefox-esr-latest-ssl&os=win64&lang=en-US"
$FirefoxInstallerPath = "$env:TEMP\FirefoxSetup.exe"
$EdgeSetupPaths = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe"
)

# ─── Helper Functions ─────────────────────────────────────────────────────────
function Write-Step {
    param([string]$Message)
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

# ─── Step 1: Uninstall Microsoft Edge ─────────────────────────────────────────
Write-Step "Attempting to uninstall Microsoft Edge..."

$edgeUninstalled = $false

# Method 1: Use Edge's own setup.exe uninstaller
$setupFiles = Resolve-Path $EdgeSetupPaths[0] -ErrorAction SilentlyContinue
if (-not $setupFiles) {
    $setupFiles = Resolve-Path $EdgeSetupPaths[1] -ErrorAction SilentlyContinue
}

if ($setupFiles) {
    foreach ($setup in $setupFiles) {
        Write-Host "    Found Edge setup at: $setup"
        try {
            $edgeVersion = ($setup.Path -split '\\' | Where-Object { $_ -match '^\d+\.' })[0]
            Start-Process -FilePath $setup.Path `
                -ArgumentList "--uninstall", "--system-level", "--verbose-logging", "--force-uninstall" `
                -Wait -NoNewWindow
            Write-Success "Edge uninstalled via setup.exe (version $edgeVersion)"
            $edgeUninstalled = $true
        } catch {
            Write-Warn "setup.exe method failed: $_"
        }
    }
}

# Method 2: Winget (if available)
if (-not $edgeUninstalled) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "    Trying winget..."
        try {
            winget uninstall --id Microsoft.Edge --silent --accept-source-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Edge uninstalled via winget."
                $edgeUninstalled = $true
            }
        } catch {
            Write-Warn "winget method failed: $_"
        }
    }
}

# Method 3: Registry-based uninstall string
if (-not $edgeUninstalled) {
    Write-Host "    Trying registry uninstall string..."
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($regPath in $regPaths) {
        Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $entry = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($entry.DisplayName -like "*Microsoft Edge*" -and $entry.UninstallString) {
                Write-Host "    Found registry entry: $($entry.DisplayName)"
                try {
                    $uninstallCmd = $entry.UninstallString -replace '/I', '/X'
                    Start-Process "cmd.exe" -ArgumentList "/c $uninstallCmd /quiet /norestart" -Wait
                    Write-Success "Edge uninstalled via registry entry."
                    $edgeUninstalled = $true
                } catch {
                    Write-Warn "Registry uninstall failed: $_"
                }
            }
        }
    }
}

if (-not $edgeUninstalled) {
    Write-Warn "Could not automatically uninstall Edge. It may already be absent, or removal may be blocked by policy."
    Write-Warn "Continuing with Firefox installation..."
}

# ─── Step 2: Prevent Edge from reinstalling via Windows Update (optional) ─────
Write-Step "Blocking Edge from reinstalling via Windows Update..."
try {
    $regBlockPath = "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"
    if (-not (Test-Path $regBlockPath)) {
        New-Item -Path $regBlockPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regBlockPath -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord -Force
    Write-Success "Edge auto-reinstall blocked in registry."
} catch {
    Write-Warn "Could not set Edge block key: $_"
}

# ─── Step 3: Download Firefox ESR ─────────────────────────────────────────────
Write-Step "Downloading Firefox ESR (latest)..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
    $webClient.DownloadFile($FirefoxInstallerUrl, $FirefoxInstallerPath)

    if (Test-Path $FirefoxInstallerPath) {
        $fileSize = (Get-Item $FirefoxInstallerPath).Length / 1MB
        Write-Success "Firefox installer downloaded ($([math]::Round($fileSize,1)) MB) -> $FirefoxInstallerPath"
    } else {
        throw "File not found after download."
    }
} catch {
    Write-Fail "Failed to download Firefox: $_"
    exit 1
}

# ─── Step 4: Install Firefox Silently ─────────────────────────────────────────
Write-Step "Installing Firefox silently..."
try {
    $installArgs = "/S"   # Silent install; no UI
    $proc = Start-Process -FilePath $FirefoxInstallerPath `
        -ArgumentList $installArgs `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0) {
        Write-Success "Firefox installed successfully (exit code 0)."
    } else {
        Write-Warn "Firefox installer exited with code $($proc.ExitCode). It may still have installed correctly."
    }
} catch {
    Write-Fail "Firefox installation failed: $_"
    exit 1
}

# ─── Step 5: Verify Firefox Installation ──────────────────────────────────────
Write-Step "Verifying Firefox installation..."
$ffPaths = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
)

$verified = $false
foreach ($path in $ffPaths) {
    if (Test-Path $path) {
        $version = (Get-Item $path).VersionInfo.FileVersion
        Write-Success "Firefox found at: $path (version $version)"
        $verified = $true
        break
    }
}

if (-not $verified) {
    Write-Warn "Firefox executable not found in expected locations. Please verify manually."
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────
Write-Step "Cleaning up temporary files..."
Remove-Item $FirefoxInstallerPath -ErrorAction SilentlyContinue
Write-Success "Temporary installer removed."

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Browser swap complete!" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

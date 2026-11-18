# 1. Force TLS 1.2 so PowerShell can securely reach the module gallery
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Initializing Windows Update sequence..." -ForegroundColor Cyan
Write-Host "---------------------------------------" -ForegroundColor DarkGray

# 2. Check for the PSWindowsUpdate module and install it if missing
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "PSWindowsUpdate module not found. Installing now..." -ForegroundColor Yellow
    
    # Silently install the NuGet provider (required for modules)
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    
    # Silently install the update module
    Install-Module -Name PSWindowsUpdate -Force -AllowClobber | Out-Null
}

# 3. Import the module into the current session
Import-Module PSWindowsUpdate

Write-Host "Searching for available updates (this may take several minutes)..." -ForegroundColor Yellow

try {
    # 4. Download and Install updates, bypassing prompts and blocking reboots
    Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose
    
    Write-Host "`n[SUCCESS] Update installation process finished." -ForegroundColor Green
    Write-Host "A manual restart will be required later to apply the changes." -ForegroundColor Cyan
}
catch {
    Write-Host "`n[ERROR] The update process failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
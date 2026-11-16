$ErrorActionPreference = "Continue"
function Secure-Service {
    param (
        [string]$ServiceName,
        [string]$Description
    )
    Write-Host "Checking $Description ($ServiceName)..." -NoNewline
    
    if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
        try {
            Stop-Service $ServiceName -Force -ErrorAction Stop
            Set-Service $ServiceName -StartupType Disabled -ErrorAction Stop
            Write-Host " [DISABLED]" -ForegroundColor Green
        }
        catch {
            Write-Host " [ERROR]" -ForegroundColor Red
            Write-Error $_.Exception.Message
        }
    }
    else {
        Write-Host " [NOT INSTALLED/FOUND]" -ForegroundColor Gray
    }
}

Secure-Service -ServiceName "WinMgmt" -Description "Windows Managment"
Secure-Service -ServiceName "LanmanServer" -Description "something about SMB"
Secure-Service -ServiceName "LanmanWorkstation" -Description "something about SMB"
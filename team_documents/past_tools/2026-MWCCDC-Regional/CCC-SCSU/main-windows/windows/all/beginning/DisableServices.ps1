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

Secure-Service -ServiceName "SSDPSRV" -Description "UPnP Discovery"
Secure-Service -ServiceName "upnphost" -Description "UPnP Host"
Secure-Service -ServiceName "Spooler" -Description "Print Spooler"
Secure-Service -ServiceName "RemoteRegistry" -Description "Remote Registry"
Secure-Service -ServiceName "XblAuthManager" -Description "Xbox Auth Manager"
Secure-Service -ServiceName "XblGameSave" -Description "Xbox Game Save"
Secure-Service -ServiceName "XboxNetApiSvc" -Description "Xbox Net API"
Secure-Service -ServiceName "DiagTrack" -Description "Telemetry (DiagTrack)"
Secure-Service -ServiceName "bthserv" -Description "Bluetooth Service"
Secure-Service -ServiceName "MapsBroker" -Description "Downloaded Maps Manager"
Secure-Service -ServiceName "lfsvc" -Description "Geolocation Service"
Secure-Service -ServiceName "WerSvc" -Description "Windows Error Reporting"
Secure-Service -ServiceName "RasAuto" -Description "RA Auto Connection Manager"
Secure-Service -ServiceName "TermService" -Description "RD Configuration AND RD Services"
Secure-Service -ServiceName "UmRdpService" -Description "Remote Desktop Services UserMode Port Redirector"
Secure-Service -ServiceName "RpcLocator" -Description "Compatability with LEGACY RPC"
Secure-Service -ServiceName "RemoteAccess" -Description "Routing and Remote Access"
Secure-Service -ServiceName "RasMan" -Description "RA Connection Managerx"
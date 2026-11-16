Write-Host "=== Disabling Nonessential Services ===`n"

# Helper function
function Disable-ServiceSafe {
    param ($ServiceName)

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne "Stopped") {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $ServiceName -StartupType Disabled
        Write-Host "Disabled: $ServiceName"
    } else {
        Write-Host "Service not found: $ServiceName"
    }
}

# -----------------------------
# High-risk / Nonessential
# -----------------------------
Disable-ServiceSafe "Spooler"          # Print Spooler
Disable-ServiceSafe "RemoteRegistry"   # Remote Registry
Disable-ServiceSafe "bthserv"           # Bluetooth Support
Disable-ServiceSafe "SSDPSRV"           # SSDP Discovery
Disable-ServiceSafe "upnphost"          # UPnP Device Host
Disable-ServiceSafe "Fax"               # Fax
Disable-ServiceSafe "SCardSvr"           # Smart Card
Disable-ServiceSafe "TermService"       # Remote Desktop Services

# -----------------------------
# Xbox Services (all variants)
# -----------------------------
$XboxServices = @(
    "XboxGipSvc",
    "XblAuthManager",
    "XblGameSave",
    "XboxNetApiSvc"
)

foreach ($svc in $XboxServices) {
    Disable-ServiceSafe $svc
}
Write-Host "`n=== Completed ==="

$ErrorActionPreference = "Continue"
Write-Host "Disabling NetBIOS on Network Adapters..." -NoNewline
try {
    $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction Stop
    foreach ($adapter in $adapters) {
        $adapter.SetTcpipNetbios(2) | Out-Null
    }
    Write-Host " [OK]" -ForegroundColor Green
}
catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Error $_.Exception.Message
}
Write-Host "===== SYSTEM OS OVERVIEW =====`n"

# Device Name
$DeviceName = $env:COMPUTERNAME
Write-Host "Device Name:"
Write-Host " - $DeviceName`n"

# Network Info (IP + MAC)
$Adapters = Get-NetAdapter |
    Where-Object { $_.Status -eq "Up" }

Write-Host "Network Information:"
foreach ($Adapter in $Adapters) {
    $IP = Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -notlike "169.254*" } |
          Select-Object -ExpandProperty IPAddress -First 1

    Write-Host " - Interface: $($Adapter.Name)"
    Write-Host "   IP Address: $IP"
    Write-Host "   MAC Address: $($Adapter.MacAddress)"
}
Write-Host ""

# OS Installed
$OS = Get-CimInstance Win32_OperatingSystem
$Build = $OS.BuildNumber
$UBR = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").UBR
$DisplayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion

Write-Host "Current OS Level Installed:"
Write-Host " - OS: $($OS.Caption)"
Write-Host " - Version: $DisplayVersion"
Write-Host " - Build: $Build.$UBR`n"

# Simple Update Status (NOT enumerating updates)
$LastUpdate = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1

Write-Host "Current Production OS Level Available:"
if ($LastUpdate) {
    Write-Host " - Last installed update: $($LastUpdate.HotFixID)"
    Write-Host " - Installed on: $($LastUpdate.InstalledOn)"
    Write-Host " - Interpretation: System appears to be receiving updates"
} else {
    Write-Host " - Unable to determine update status"
}
Write-Host ""

# Assessment (High-Level / Non-invasive)
Write-Host "Assessment:"
Write-Host " - OS information and patch history indicate the system is operational."
Write-Host " - No deep vulnerability or configuration inspection was performed."
Write-Host " - Recommendation: Ensure OS remains within vendor support lifecycle and receives regular updates."

Write-Host "`n=============================="

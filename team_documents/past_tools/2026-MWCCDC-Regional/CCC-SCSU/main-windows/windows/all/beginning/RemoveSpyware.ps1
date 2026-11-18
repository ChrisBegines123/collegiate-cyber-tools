$ErrorActionPreference = "Continue"
Write-Host "Searching for VNC/TeamViewer..."
try {
    $software = Get-WmiObject -Class Win32_Product -ErrorAction Stop | Where-Object { $_.Name -match "VNC" -or $_.Name -match "TeamViewer" }
    if ($software) {
        Write-Host "WARNING: FOUND THE FOLLOWING SOFTWARE:" -ForegroundColor Magenta
        $software | Select-Object Name, Version | Format-Table -AutoSize
        Write-Host "ACTION REQUIRED: Please manually uninstall these via Control Panel." -ForegroundColor Yellow
    } else {
        Write-Host "No VNC or TeamViewer found via WMI." -ForegroundColor Green
    }
}
catch {
    Write-Host " [ERROR SEARCHING INSTALLED APPS]" -ForegroundColor Red
    Write-Error $_.Exception.Message
}
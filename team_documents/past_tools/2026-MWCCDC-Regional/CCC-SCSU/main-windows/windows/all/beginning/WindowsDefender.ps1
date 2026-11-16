Write-Host "Re-enabling Windows Defender..." -ForegroundColor Cyan
Write-Host "--------------------------------" -ForegroundColor DarkGray

try {
    # 1. Turn on core protections using native Defender cmdlets
    Write-Host "Enabling Real-time and Behavior Monitoring..."
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBlockAtFirstSight $false -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue

    # 2. Remove Registry restrictions (Group Policy overrides)
    Write-Host "Clearing Registry overrides..."
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (Test-Path $RegPath) {
        Remove-ItemProperty -Path $RegPath -Name "DisableAntiSpyware" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RegPath -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue
    }

    $RealTimeRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
    if (Test-Path $RealTimeRegPath) {
        Remove-ItemProperty -Path $RealTimeRegPath -Name "DisableBehaviorMonitoring" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RealTimeRegPath -Name "DisableOnAccessProtection" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RealTimeRegPath -Name "DisableScanOnRealtimeEnable" -ErrorAction SilentlyContinue
    }

    # 3. Ensure the Defender Service is set to start
    Write-Host "Starting WinDefend service..."
    Set-Service -Name "WinDefend" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "WinDefend" -ErrorAction SilentlyContinue

    Write-Host "`n[SUCCESS] Windows Defender has been re-enabled." -ForegroundColor Green
    Write-Host "A system restart is highly recommended to ensure all services hook correctly." -ForegroundColor Yellow
}
catch {
    Write-Host "`n[ERROR] Failed to modify Defender settings. Make sure you are running this as Administrator." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
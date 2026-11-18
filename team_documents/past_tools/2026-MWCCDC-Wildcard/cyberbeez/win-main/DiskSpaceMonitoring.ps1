# Set thresholds
$warningThreshold50 = 50
$warningThreshold80 = 80
$criticalThreshold90 = 90

# Get disk information
Get-WmiObject -Class Win32_LogicalDisk | ForEach-Object {
    $percentUsed = 0
    if ($_.Size -gt 0) {
        $drive = $_.DeviceID
        $freeSpaceGB = [Math]::Round($_.FreeSpace / 1GB, 2)
        $totalSpaceGB = [Math]::Round($_.Size / 1GB, 2)
        $usedSpaceGB = $totalSpaceGB - $freeSpaceGB
        $percentFree = [Math]::Round(($freeSpaceGB / $totalSpaceGB) * 100, 2)
        $percentUsed = 100 - $percentFree
    }
    # Check thresholds and send alerts
    if ($percentUsed -ge $criticalThreshold90) {
       Write-Output ("Warning! Disk Threshold has reached 90%!! PLEASE TAKE IMMEDIATE ACTION!") | Add-content .\CriticalDiskLog.txt
    } elseif ($percentUsed -ge $warningThreshold80) {
       Write-Output ("Warning! Disk Threshold has reached 80%!! Please really consider taking action") | Add-content .\WarningDiskLog.txt
    } elseif ($percentUsed -ge $warningThreshold50) {
       Write-Output ("Warning! Disk Threshold has reached 50%!! Consider Taking Action") | Add-content .\ConcernedDiskLog.txt
    }
}
pause

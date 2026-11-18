# DiskAlert.ps1 — SUPER SIMPLE (Event Log ONLY)
# Alerts at 50%, 80%, 90% disk USED. Writes to Application log (Source: CCDC-DiskMonitor)
# NOTE: Run once as Administrator to register the event source.

# --- One-time setup (needs Admin the first time) ---
$source = "CCDC-DiskMonitor"
if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
  New-EventLog -LogName Application -Source $source
}

# --- Check disks + alert ---
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
  if (-not $_.Size) { return }

  $usedPct = [int]( (($_.Size - $_.FreeSpace) / $_.Size) * 100 )

  if ($usedPct -ge 90) {
    Write-EventLog -LogName Application -Source $source -EventId 5090 -EntryType Error -Message "Disk $($_.DeviceID) is $usedPct% used (>=90%)."
  }
  elseif ($usedPct -ge 80) {
    Write-EventLog -LogName Application -Source $source -EventId 5080 -EntryType Warning -Message "Disk $($_.DeviceID) is $usedPct% used (>=80%)."
  }
  elseif ($usedPct -ge 50) {
    Write-EventLog -LogName Application -Source $source -EventId 5050 -EntryType Information -Message "Disk $($_.DeviceID) is $usedPct% used (>=50%)."
  }
}

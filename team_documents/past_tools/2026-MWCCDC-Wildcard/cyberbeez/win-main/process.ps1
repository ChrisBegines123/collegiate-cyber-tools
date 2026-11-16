# Get top 10 CPU processes
$cpuProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, @{Name="CPU";Expression={[math]::round($_.CPU, 2)}}, @{Name="Path";Expression={(Get-Process -Id $_.Id | Select-Object -ExpandProperty Path)}} 

# Get top 10 Memory processes
$memProcesses = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, @{Name="Memory(MB)";Expression={[math]::round($_.WorkingSet64 / 1MB, 2)}}, @{Name="Path";Expression={(Get-Process -Id $_.Id | Select-Object -ExpandProperty Path)}} 

# Formatting
$output = "`nTop 10 CPU Consuming Processes`n"
$output += $cpuProcesses | Format-Table -AutoSize | Out-String

$output += "`nTop 10 Memory Consuming Processes`n"
$output += $memProcesses | Format-Table -AutoSize | Out-String

# Get the script dir and set output dir
$scriptDir = (Get-Location).Path
$filePath = "$scriptDir\Process Locations.txt"

# Display CPU processes
Write-Host "`nTop 10 CPU Consuming Processes`n"
$cpuProcesses | Format-Table -AutoSize

# Display Memory processes
Write-Host "`nTop 10 Memory Consuming Processes`n"
$memProcesses | Format-Table -AutoSize

# print top .txt file
$output | Out-File -FilePath $filePath -Encoding UTF8

# Done statement
Write-Host "Process information saved to: $filePath"

pause

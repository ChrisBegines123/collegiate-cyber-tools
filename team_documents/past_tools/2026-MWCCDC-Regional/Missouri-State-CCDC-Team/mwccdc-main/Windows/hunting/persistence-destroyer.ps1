<#
.SYNOPSIS
    Takes and prints the most comon persistence mechanisms found on Windows systems.

.DESCRIPTION
    Used to print out the persistence mechanisms on windows systems.

.EXAMPLE
    PS> .\persistence-destroyer.ps1 

.NOTES
    Author: Tyler Olson
#>

# --- Run Keys ---
Write-Host "`n--- Run Keys ---"
$runKeyPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

foreach ($path in $runKeyPaths) {
    if (Test-Path $path) {
        Write-Host "`n[$path]" -ForegroundColor Cyan
        Get-ItemProperty -Path $path | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                Write-Host "$($_.Name) -> $($_.Value)"
            }
        }
    }
}

# --- Startup Folder ---
Write-Host "`n--- Startup Folder ---"
$startupPaths = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)
foreach ($path in $startupPaths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path | ForEach-Object {
            Write-Host "${path}: $($_.Name)"
        }
    }
}

# --- Services ---
Write-Host "`n--- Services with Auto Start ---"
Get-WmiObject Win32_Service | Where-Object { $_.StartMode -eq "Auto" -and $_.State -ne "Stopped" } | ForEach-Object {
    Write-Host "$($_.Name) -> $($_.PathName)"
}

# --- Scheduled Tasks ---
Write-Host "`n--- Scheduled Tasks ---"
Get-ScheduledTask | ForEach-Object {
    $info = $_ | Get-ScheduledTaskInfo
    Write-Host "$($_.TaskName) -> Last Run: $($info.LastRunTime)"
}


# --- WMI Event Subscriptions ---
Write-Host "`n--- WMI Event Subscriptions ---"
$filters = Get-WmiObject -Namespace "root\subscription" -Class __EventFilter
$consumers = Get-WmiObject -Namespace "root\subscription" -Class CommandLineEventConsumer
$bindings = Get-WmiObject -Namespace "root\subscription" -Class __FilterToConsumerBinding

foreach ($bind in $bindings) {
    $filter = $filters | Where-Object { $_.__RELPATH -eq $bind.Filter }
    $consumer = $consumers | Where-Object { $_.__RELPATH -eq $bind.Consumer }
    if ($filter -and $consumer) {
        Write-Host "WMI Binding: $($filter.Name) -> $($consumer.Name)"
        Write-Host "Command: $($consumer.CommandLineTemplate)"
    }
}

# --- AppInit_DLLs ---
Write-Host "`n--- AppInit_DLLs ---"
$appInitPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Windows"
if (Test-Path $appInitPath) {
    $dlls = Get-ItemProperty -Path $appInitPath -Name AppInit_DLLs -ErrorAction SilentlyContinue
    if ($dlls.AppInit_DLLs) {
        Write-Host "AppInit_DLLs: $($dlls.AppInit_DLLs)"
    } else {
        Write-Host "No AppInit_DLLs configured"
    }
}

Write-Host "It is recomended to use Autoruns and other sysinternals tools to further investigate persistence mechanisms."
Write-Host "`n=== End of Persistence Check ===`n"

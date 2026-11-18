# 1. Define the monitoring script that will run in the new window
$WatcherCode = @'
$Host.UI.RawUI.WindowTitle = "TERMINATOR"
Clear-Host
Write-Host "Listening for new processes..." -ForegroundColor Yellow
Write-Host "Press 'k' to toggle TERMINATOR MODE." -ForegroundColor Cyan
Write-Host "---------------------------------------------------" -ForegroundColor DarkGray

# Define the query to catch process start events
$Query = "SELECT * FROM Win32_ProcessStartTrace"

# Register the event
Register-CimIndicationEvent -Query $Query -SourceIdentifier "ProcessTracker"

$TerminatorMode = $false

# Use a loop with a timeout to allow checking for keystrokes
while ($true) {
    # Check if a key was pressed
    if ([console]::KeyAvailable) {
        $Key = [console]::ReadKey($true)
        if ($Key.KeyChar -eq 'k') {
            $TerminatorMode = -not $TerminatorMode
            if ($TerminatorMode) {
                Write-Host "`n[!] TERMINATOR MODE ARMED: All new processes will be killed." -ForegroundColor Black -BackgroundColor Red
            } else {
                Write-Host "`n[*] TERMINATOR MODE DISARMED." -ForegroundColor Green
            }
        }
    }

    # Wait for the event, but timeout after 1 second to keep the loop moving
    $NewEvent = Wait-Event -SourceIdentifier "ProcessTracker" -Timeout 1
    
    if ($NewEvent) {
        $Process = $NewEvent.SourceEventArgs.NewEvent
        $Time = Get-Date -Format "HH:mm:ss"
        
        if ($TerminatorMode) {
            # Attempt to kill the process immediately
            Stop-Process -Id $Process.ProcessID -Force -ErrorAction SilentlyContinue
            Write-Host "[$Time] TERMINATED: $($Process.ProcessName) (PID: $($Process.ProcessID))" -ForegroundColor Red
        } else {
            # Standard logging
            Write-Host "[$Time] Started: $($Process.ProcessName) (PID: $($Process.ProcessID))" -ForegroundColor Green
        }
        
        # Clean up the processed event from memory
        Remove-Event -EventIdentifier $NewEvent.EventIdentifier
    }
}
'@

# 2. Convert the script block into an Encoded Command
$EncodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($WatcherCode))

# 3. Launch the new PowerShell window
Start-Process powershell -ArgumentList "-NoProfile", "-EncodedCommand", $EncodedCommand
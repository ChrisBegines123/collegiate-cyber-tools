<#
.SYNOPSIS
    Shows scheduled tasks on a Windows system, highlighting non-Microsoft tasks and those that run PowerShell.

.EXAMPLE
    PS> .\scheduledtasks.ps1

.NOTES
    Simple script to show non-Microsoft scheduled tasks and those that run PowerShell.
#>

# Filter for tasks that run PowerShell
$psTasks = $tasks | Where-Object { 
    ($_.Actions -match "powershell.exe") -or ($_.Actions -match "pwsh.exe") 
}

# Print results
Write-Host "=== Non-Microsoft Scheduled Tasks ===" -ForegroundColor Cyan
$tasks | Select-Object TaskName, TaskPath, State, Description | Format-Table -AutoSize

Write-Host "`n=== Scheduled Tasks Running PowerShell ===" -ForegroundColor Yellow
$psTasks | Select-Object TaskName, TaskPath, State, Description | Format-Table -AutoSize
Write-Host "===== INJECT STATUS CHECK =====`n"

# -----------------------------
# 1) Disabled Services
# -----------------------------
Write-Host "1) Disabled Services:"
$DisabledServices = Get-Service | Where-Object { $_.StartType -eq "Disabled" }

if ($DisabledServices) {
    $DisabledServices | Select-Object Name, DisplayName, Status | Format-Table -AutoSize
} else {
    Write-Host "No disabled services detected."
}
Write-Host ""

# -----------------------------
# 2) Configuration / System Errors
# -----------------------------
Write-Host "2) Recent Configuration / System Errors (Last 24 hours):"

$Errors = Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Level   = 2
    StartTime = (Get-Date).AddDays(-1)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, ProviderName, Message -First 5

if ($Errors) {
    $Errors | Format-Table TimeCreated, Id, ProviderName -AutoSize
} else {
    Write-Host "No recent system-level errors found."
}
Write-Host ""

# -----------------------------
# 3) Running Processes (Suspicious Review)
# -----------------------------
Write-Host "3) Running Processes (Top by CPU):"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, CPU | Format-Table -AutoSize

Write-Host ""
Write-Host "No automated process termination performed."
Write-Host ""

# -----------------------------
# Screenshot Reminder
# -----------------------------
Write-Host "4) Screenshot Guidance:"
Write-Host " - Capture this output as evidence."
Write-Host " - Include disabled services, error check, and process list."
Write-Host "`n===== END OF CHECK ====="

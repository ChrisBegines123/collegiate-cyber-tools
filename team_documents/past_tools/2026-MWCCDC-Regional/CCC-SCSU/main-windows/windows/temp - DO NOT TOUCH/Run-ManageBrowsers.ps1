#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Wrapper that temporarily enables RemoteSigned execution policy,
    runs Manage-Browsers.ps1, then restores the original policy.
#>

# ─── Capture current policy ───────────────────────────────────────────────────
$previousPolicy = Get-ExecutionPolicy -Scope LocalMachine
Write-Host "[*] Current execution policy: $previousPolicy" -ForegroundColor Cyan

# ─── Set RemoteSigned ─────────────────────────────────────────────────────────
Write-Host "[*] Setting execution policy to RemoteSigned..." -ForegroundColor Cyan
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

# ─── Run main script, restore policy even if it crashes ──────────────────────
try {
    $scriptPath = Join-Path $PSScriptRoot "Manage-Browsers.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Manage-Browsers.ps1 not found in the same directory as this wrapper."
    }

    & $scriptPath

} finally {
    # Always restore — runs whether the script succeeded or failed
    Write-Host "`n[*] Restoring execution policy to: $previousPolicy" -ForegroundColor Cyan
    Set-ExecutionPolicy -ExecutionPolicy $previousPolicy -Scope LocalMachine -Force
    Write-Host "[+] Execution policy restored." -ForegroundColor Green
}

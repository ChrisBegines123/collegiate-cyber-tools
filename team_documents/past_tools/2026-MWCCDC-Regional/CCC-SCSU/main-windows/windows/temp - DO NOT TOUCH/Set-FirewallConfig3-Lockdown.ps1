#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Firewall Config 3 — Complete Lockdown

.DESCRIPTION
    - Removes all existing rules
    - Creates a single rule that blocks ALL inbound and outbound traffic
    - No exceptions. No ports. No protocols. Nothing in or out.

.NOTES
    WARNING: Applying this config will immediately cut off all network
    communication including RDP. Ensure you have console/out-of-band
    access to the machine before running this.
#>

Write-Host "[!] WARNING: Config 3 is a COMPLETE network lockdown." -ForegroundColor Red
Write-Host "[!] ALL network traffic will be blocked immediately." -ForegroundColor Red
Write-Host "[!] Ensure you have console or out-of-band access before continuing." -ForegroundColor Red

# ─── Confirmation prompt ──────────────────────────────────────────────────────
$confirm = Read-Host "`n    Type LOCKDOWN to confirm and apply"
if ($confirm -ne "LOCKDOWN") {
    Write-Host "[*] Aborted. No changes made." -ForegroundColor Cyan
    exit 0
}

Write-Host "`n[*] Applying Config 3: Complete Lockdown..." -ForegroundColor Cyan

# ─── Clear existing rules ─────────────────────────────────────────────────────
Write-Host "[*] Removing all existing firewall rules..." -ForegroundColor Cyan
Get-NetFirewallRule | Remove-NetFirewallRule
Write-Host "[+] Existing rules cleared." -ForegroundColor Green

# ─── Single rule: Block all inbound ──────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG3-LOCKDOWN-BLOCK-ALL-INBOUND" `
    -DisplayName "Config3 | LOCKDOWN — Block All Inbound" `
    -Description "Blocks all inbound traffic on all ports and protocols. No exceptions." `
    -Direction   Inbound `
    -Action      Block `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Block all inbound." -ForegroundColor Green

# ─── Single rule: Block all outbound ─────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG3-LOCKDOWN-BLOCK-ALL-OUTBOUND" `
    -DisplayName "Config3 | LOCKDOWN — Block All Outbound" `
    -Description "Blocks all outbound traffic on all ports and protocols. No exceptions." `
    -Direction   Outbound `
    -Action      Block `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Block all outbound." -ForegroundColor Green

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n================================================" -ForegroundColor Red
Write-Host "  Config 3 Applied — MACHINE IS NOW ISOLATED" -ForegroundColor Red
Write-Host "================================================" -ForegroundColor Red
Write-Host "  Inbound  : ALL traffic BLOCKED" -ForegroundColor Red
Write-Host "  Outbound : ALL traffic BLOCKED" -ForegroundColor Red
Write-Host "  Active rules: 2 (block-all inbound + block-all outbound)" -ForegroundColor Red
Write-Host "================================================" -ForegroundColor Red
Write-Host "`n  To restore access, run Export-FirewallRules.ps1" -ForegroundColor Yellow
Write-Host "  backup or manually delete these rules via:" -ForegroundColor Yellow
Write-Host "  Get-NetFirewallRule | Remove-NetFirewallRule`n" -ForegroundColor Yellow

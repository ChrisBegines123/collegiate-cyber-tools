#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Firewall Config 2 — Locked Inbound / Controlled Outbound

.DESCRIPTION
    - Blocks ALL inbound traffic on all ports
    - Allows outbound traffic only on ports 53, 80, and 443
    - Blocks all other outbound traffic
#>

Write-Host "[*] Applying Config 2: Locked Inbound / Controlled Outbound..." -ForegroundColor Cyan

# ─── Clear existing rules ─────────────────────────────────────────────────────
Write-Host "[*] Removing all existing firewall rules..." -ForegroundColor Cyan
Get-NetFirewallRule | Remove-NetFirewallRule
Write-Host "[+] Existing rules cleared." -ForegroundColor Green

# ─── Inbound: Block everything ────────────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG2-INBOUND-BLOCK-ALL" `
    -DisplayName "Config2 | Block All Inbound" `
    -Description "Blocks all inbound traffic on all ports and protocols." `
    -Direction   Inbound `
    -Action      Block `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Block all inbound." -ForegroundColor Green

# ─── Outbound: Allow ports 53, 80, 443 (TCP) ──────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG2-OUTBOUND-ALLOW-TCP-53-80-443" `
    -DisplayName "Config2 | Allow Outbound TCP 53, 80, 443" `
    -Description "Allows outbound TCP traffic on ports 53 (DNS), 80 (HTTP), and 443 (HTTPS)." `
    -Direction   Outbound `
    -Action      Allow `
    -Protocol    TCP `
    -RemotePort  53, 80, 443 `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Allow outbound TCP 53, 80, 443." -ForegroundColor Green

# ─── Outbound: Allow port 53 (UDP) ────────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG2-OUTBOUND-ALLOW-UDP-53" `
    -DisplayName "Config2 | Allow Outbound UDP 53" `
    -Description "Allows outbound UDP traffic on port 53 (DNS)." `
    -Direction   Outbound `
    -Action      Allow `
    -Protocol    UDP `
    -RemotePort  53 `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Allow outbound UDP 53." -ForegroundColor Green

# ─── Outbound: Block everything else ─────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG2-OUTBOUND-BLOCK-ALL" `
    -DisplayName "Config2 | Block All Other Outbound" `
    -Description "Blocks all outbound traffic not explicitly allowed." `
    -Direction   Outbound `
    -Action      Block `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Block all other outbound." -ForegroundColor Green

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Config 2 Applied" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Inbound  : ALL ports BLOCKED" -ForegroundColor Red
Write-Host "  Outbound : Ports 53 (TCP/UDP), 80, 443 ALLOWED" -ForegroundColor Green
Write-Host "  Outbound : All other ports BLOCKED" -ForegroundColor Red
Write-Host "================================================`n" -ForegroundColor Cyan

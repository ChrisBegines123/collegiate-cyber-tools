#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Firewall Config 1 — Open Inbound / Restricted Outbound
    
.DESCRIPTION
    - Allows ALL inbound traffic on all ports
    - Blocks outbound traffic on ports 53, 80, and 443
    - Allows all other outbound traffic
#>

Write-Host "[*] Applying Config 1: Open Inbound / Restricted Outbound..." -ForegroundColor Cyan

# ─── Clear existing rules ─────────────────────────────────────────────────────
Write-Host "[*] Removing all existing firewall rules..." -ForegroundColor Cyan
Get-NetFirewallRule | Remove-NetFirewallRule
Write-Host "[+] Existing rules cleared." -ForegroundColor Green

# ─── Inbound: Allow everything ────────────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG1-INBOUND-ALLOW-ALL" `
    -DisplayName "Config1 | Allow All Inbound" `
    -Description "Allows all inbound traffic on all ports and protocols." `
    -Direction   Inbound `
    -Action      Allow `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Allow all inbound." -ForegroundColor Green

# ─── Outbound: Block ports 53, 80, 443 (TCP) ──────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG1-OUTBOUND-BLOCK-TCP-53-80-443" `
    -DisplayName "Config1 | Block Outbound TCP 53, 80, 443" `
    -Description "Blocks outbound TCP traffic on ports 53 (DNS), 80 (HTTP), and 443 (HTTPS)." `
    -Direction   Outbound `
    -Action      Block `
    -Protocol    TCP `
    -RemotePort  53, 80, 443 `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Block outbound TCP 53, 80, 443." -ForegroundColor Green

# ─── Outbound: Block port 53 (UDP) ────────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG1-OUTBOUND-BLOCK-UDP-53" `
    -DisplayName "Config1 | Block Outbound UDP 53" `
    -Description "Blocks outbound UDP traffic on port 53 (DNS)." `
    -Direction   Outbound `
    -Action      Block `
    -Protocol    UDP `
    -RemotePort  53 `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Block outbound UDP 53." -ForegroundColor Green

# ─── Outbound: Allow everything else ─────────────────────────────────────────
New-NetFirewallRule `
    -Name        "CFG1-OUTBOUND-ALLOW-ALL" `
    -DisplayName "Config1 | Allow All Other Outbound" `
    -Description "Allows all outbound traffic not matched by a block rule." `
    -Direction   Outbound `
    -Action      Allow `
    -Profile     Any `
    -Enabled     True | Out-Null

Write-Host "[+] Rule created: Allow all other outbound." -ForegroundColor Green

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Config 1 Applied" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Inbound  : ALL ports ALLOWED" -ForegroundColor Green
Write-Host "  Outbound : Ports 53 (TCP/UDP), 80, 443 BLOCKED" -ForegroundColor Red
Write-Host "  Outbound : All other ports ALLOWED" -ForegroundColor Green
Write-Host "================================================`n" -ForegroundColor Cyan

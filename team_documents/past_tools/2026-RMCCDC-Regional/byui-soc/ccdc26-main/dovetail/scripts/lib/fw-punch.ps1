# CCDC26 Dovetail - Temporary Firewall Punch
# Opens outbound 80/443 for downloads, then closes immediately after.
#
# Usage (dot-source then call):
#   . .\lib\fw-punch.ps1
#   Invoke-WithInternetAccess { Invoke-WebRequest -Uri $url -OutFile $file }
#
# The firewall rule is removed in the finally block, guaranteeing cleanup
# even if the download fails or the script is interrupted.

function Invoke-WithInternetAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $ruleName = "CCDC-Temp-Outbound-Web"

    try {
        Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
        Write-Host "Opening outbound 80/443..."
        New-NetFirewallRule -DisplayName $ruleName -Direction Outbound `
            -Action Allow -Protocol TCP -RemotePort 80,443 `
            -ErrorAction SilentlyContinue | Out-Null

        & $Action
    } finally {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
        Write-Host "Closed outbound 80/443"
    }
}

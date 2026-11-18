#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Exports all current Windows Firewall rules to a JSON file.

.DESCRIPTION
    Captures every inbound and outbound firewall rule (including disabled ones)
    and saves them as structured JSON. The output file can be used with
    Restore-FirewallRules.ps1 to recreate the rules on this or another machine.

.PARAMETER OutputPath
    Path for the exported JSON file.
    Defaults to "FirewallRules_<hostname>_<timestamp>.json" in the script directory.

.EXAMPLE
    .\Export-FirewallRules.ps1
    .\Export-FirewallRules.ps1 -OutputPath "C:\Backups\fw_rules.json"
#>

param(
    [string]$OutputPath = (Join-Path $PSScriptRoot ("FirewallRules_{0}_{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss")))
)

# ─── Collect rules ────────────────────────────────────────────────────────────
Write-Host "[*] Reading firewall rules..." -ForegroundColor Cyan

$rules = Get-NetFirewallRule | ForEach-Object {
    $rule        = $_
    $addrFilter  = $rule | Get-NetFirewallAddressFilter
    $portFilter  = $rule | Get-NetFirewallPortFilter
    $appFilter   = $rule | Get-NetFirewallApplicationFilter
    $svcFilter   = $rule | Get-NetFirewallServiceFilter
    $secFilter   = $rule | Get-NetFirewallSecurityFilter
    $intFilter   = $rule | Get-NetFirewallInterfaceFilter
    $intTypeFilter = $rule | Get-NetFirewallInterfaceTypeFilter

    [PSCustomObject]@{
        # Identity
        Name                  = $rule.Name
        DisplayName           = $rule.DisplayName
        Description           = $rule.Description
        Group                 = $rule.Group
        DisplayGroup          = $rule.DisplayGroup

        # State
        Enabled               = $rule.Enabled.ToString()
        Profile               = $rule.Profile.ToString()
        Direction             = $rule.Direction.ToString()
        Action                = $rule.Action.ToString()
        EdgeTraversalPolicy   = $rule.EdgeTraversalPolicy.ToString()
        LooseSourceMapping    = $rule.LooseSourceMapping
        LocalOnlyMapping      = $rule.LocalOnlyMapping
        Owner                 = $rule.Owner
        PrimaryStatus         = $rule.PrimaryStatus.ToString()

        # Address filter
        LocalAddress          = @($addrFilter.LocalAddress)
        RemoteAddress         = @($addrFilter.RemoteAddress)

        # Port filter
        Protocol              = $portFilter.Protocol
        LocalPort             = @($portFilter.LocalPort)
        RemotePort            = @($portFilter.RemotePort)
        IcmpType              = @($portFilter.IcmpType)
        DynamicTarget         = $portFilter.DynamicTarget.ToString()

        # Application filter
        Program               = $appFilter.Program
        Package               = $appFilter.Package

        # Service filter
        Service               = $svcFilter.Service

        # Security filter
        Authentication        = $secFilter.Authentication.ToString()
        Encryption            = $secFilter.Encryption.ToString()
        LocalUser             = $secFilter.LocalUser
        RemoteUser            = $secFilter.RemoteUser
        RemoteMachine         = $secFilter.RemoteMachine
        OverrideBlockRules    = $secFilter.OverrideBlockRules

        # Interface filters
        InterfaceAlias        = @($intFilter.InterfaceAlias)
        InterfaceType         = $intTypeFilter.InterfaceType.ToString()
    }
}

# ─── Build export object ──────────────────────────────────────────────────────
$export = [PSCustomObject]@{
    ExportedAt   = (Get-Date -Format "o")
    Hostname     = $env:COMPUTERNAME
    RuleCount    = $rules.Count
    Rules        = $rules
}

# ─── Write JSON ───────────────────────────────────────────────────────────────
Write-Host "[*] Exporting $($rules.Count) rules to: $OutputPath" -ForegroundColor Cyan

$export | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

if (Test-Path $OutputPath) {
    $sizekb = [math]::Round((Get-Item $OutputPath).Length / 1KB, 1)
    Write-Host "[+] Export complete. File size: $sizekb KB" -ForegroundColor Green
    Write-Host "[+] Output: $OutputPath" -ForegroundColor Green
} else {
    Write-Host "[-] Export failed — file not found after write." -ForegroundColor Red
    exit 1
}

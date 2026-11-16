#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deletes all current firewall rules and restores them from a JSON export.

.DESCRIPTION
    1. Reads a JSON file produced by Export-FirewallRules.ps1
    2. Prompts for confirmation before deleting existing rules
    3. Removes all current firewall rules
    4. Recreates every rule from the JSON file
    5. Reports success/failure counts

.PARAMETER InputPath
    Path to the JSON file exported by Export-FirewallRules.ps1.
    Defaults to the most recently modified .json file in the script directory.

.PARAMETER Force
    Skip the confirmation prompt and delete/restore immediately.

.EXAMPLE
    .\Restore-FirewallRules.ps1 -InputPath "C:\Backups\fw_rules.json"
    .\Restore-FirewallRules.ps1 -InputPath ".\FirewallRules_SERVER01_20240101_120000.json" -Force
#>

param(
    [string]$InputPath = "",
    [switch]$Force
)

# ─── Resolve input file ───────────────────────────────────────────────────────
if (-not $InputPath) {
    $latest = Get-ChildItem -Path $PSScriptRoot -Filter "FirewallRules_*.json" |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if ($latest) {
        $InputPath = $latest.FullName
        Write-Host "[*] No input file specified. Using most recent export: $InputPath" -ForegroundColor Cyan
    } else {
        Write-Host "[-] No input file specified and no FirewallRules_*.json found in script directory." -ForegroundColor Red
        Write-Host "    Usage: .\Restore-FirewallRules.ps1 -InputPath <path-to-json>" -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path $InputPath)) {
    Write-Host "[-] File not found: $InputPath" -ForegroundColor Red
    exit 1
}

# ─── Load and validate JSON ───────────────────────────────────────────────────
Write-Host "[*] Loading firewall rules from: $InputPath" -ForegroundColor Cyan

try {
    $import = Get-Content -Path $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host "[-] Failed to parse JSON: $_" -ForegroundColor Red
    exit 1
}

if (-not $import.Rules -or $import.Rules.Count -eq 0) {
    Write-Host "[-] No rules found in the import file." -ForegroundColor Red
    exit 1
}

Write-Host "[+] Loaded $($import.Rules.Count) rules (exported from '$($import.Hostname)' at $($import.ExportedAt))" -ForegroundColor Green

# ─── Confirmation prompt ──────────────────────────────────────────────────────
if (-not $Force) {
    $currentCount = (Get-NetFirewallRule).Count
    Write-Host "`n[!] WARNING: This will DELETE all $currentCount current firewall rules," -ForegroundColor Yellow
    Write-Host "    then restore $($import.Rules.Count) rules from the import file." -ForegroundColor Yellow
    $confirm = Read-Host "`n    Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Host "[*] Aborted. No changes made." -ForegroundColor Cyan
        exit 0
    }
}

# ─── Delete all current rules ─────────────────────────────────────────────────
Write-Host "`n[*] Deleting all current firewall rules..." -ForegroundColor Cyan
try {
    Get-NetFirewallRule | Remove-NetFirewallRule -ErrorAction Stop
    Write-Host "[+] All existing rules deleted." -ForegroundColor Green
} catch {
    Write-Host "[-] Failed to delete existing rules: $_" -ForegroundColor Red
    exit 1
}

# ─── Restore rules from JSON ──────────────────────────────────────────────────
Write-Host "[*] Restoring $($import.Rules.Count) rules..." -ForegroundColor Cyan

$successCount = 0
$failCount    = 0
$failedRules  = @()

foreach ($r in $import.Rules) {

    # Build a hashtable of parameters — only include non-empty/non-default values
    $params = @{
        Name      = $r.Name
        Enabled   = $r.Enabled
        Direction = $r.Direction
        Action    = $r.Action
    }

    if ($r.DisplayName)           { $params["DisplayName"]           = $r.DisplayName }
    if ($r.Description)           { $params["Description"]           = $r.Description }
    if ($r.Group)                 { $params["Group"]                 = $r.Group }
    if ($r.Profile)               { $params["Profile"]               = $r.Profile }
    if ($r.EdgeTraversalPolicy)   { $params["EdgeTraversalPolicy"]   = $r.EdgeTraversalPolicy }
    if ($r.Owner)                 { $params["Owner"]                 = $r.Owner }
    if ($r.LooseSourceMapping)    { $params["LooseSourceMapping"]    = $r.LooseSourceMapping }
    if ($r.LocalOnlyMapping)      { $params["LocalOnlyMapping"]      = $r.LocalOnlyMapping }

    # Address filter
    if ($r.LocalAddress  -and $r.LocalAddress  -notcontains "Any") { $params["LocalAddress"]  = $r.LocalAddress }
    if ($r.RemoteAddress -and $r.RemoteAddress -notcontains "Any") { $params["RemoteAddress"] = $r.RemoteAddress }

    # Port / protocol filter
    if ($r.Protocol -and $r.Protocol -ne "Any") { $params["Protocol"] = $r.Protocol }
    if ($r.LocalPort   -and $r.LocalPort   -notcontains "Any") { $params["LocalPort"]   = $r.LocalPort }
    if ($r.RemotePort  -and $r.RemotePort  -notcontains "Any") { $params["RemotePort"]  = $r.RemotePort }
    if ($r.IcmpType    -and $r.IcmpType    -notcontains "Any") { $params["IcmpType"]    = $r.IcmpType }

    # Application / service filter
    if ($r.Program -and $r.Program -ne "Any") { $params["Program"] = $r.Program }
    if ($r.Package)                           { $params["Package"] = $r.Package }
    if ($r.Service -and $r.Service -ne "Any") { $params["Service"] = $r.Service }

    # Interface filter
    if ($r.InterfaceAlias -and $r.InterfaceAlias -notcontains "Any") { $params["InterfaceAlias"] = $r.InterfaceAlias }
    if ($r.InterfaceType  -and $r.InterfaceType  -ne "Any")          { $params["InterfaceType"]  = $r.InterfaceType }

    # Security filter
    if ($r.Authentication -and $r.Authentication -ne "NotRequired") { $params["Authentication"] = $r.Authentication }
    if ($r.Encryption     -and $r.Encryption     -ne "NotRequired") { $params["Encryption"]     = $r.Encryption }
    if ($r.LocalUser)     { $params["LocalUser"]     = $r.LocalUser }
    if ($r.RemoteUser)    { $params["RemoteUser"]    = $r.RemoteUser }
    if ($r.RemoteMachine) { $params["RemoteMachine"] = $r.RemoteMachine }
    if ($r.OverrideBlockRules) { $params["OverrideBlockRules"] = $r.OverrideBlockRules }

    try {
        New-NetFirewallRule @params -ErrorAction Stop | Out-Null
        $successCount++
    } catch {
        $failCount++
        $failedRules += [PSCustomObject]@{ Name = $r.Name; DisplayName = $r.DisplayName; Error = $_.Exception.Message }
        Write-Host "  [!] Failed to restore: '$($r.DisplayName)' — $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Restore Summary" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Restored successfully : $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed                : $failCount" -ForegroundColor Yellow

    # Write failed rules to a log next to the input file
    $logPath = [System.IO.Path]::ChangeExtension($InputPath, ".restore-errors.json")
    $failedRules | ConvertTo-Json -Depth 5 | Set-Content -Path $logPath -Encoding UTF8
    Write-Host "  Error log             : $logPath" -ForegroundColor Yellow
} else {
    Write-Host "  All rules restored cleanly." -ForegroundColor Green
}
Write-Host "================================================`n" -ForegroundColor Cyan

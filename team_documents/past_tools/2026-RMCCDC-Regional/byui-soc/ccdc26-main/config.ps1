# CCDC Environment Configuration - PowerShell
# =============================================
# AUTO-GENERATED from config.env — re-run ./deploy.sh --configure to refresh.
# Primary source of truth is config.env. Changes here (e.g. via Set-EnvironmentConfig) may be overwritten on regeneration.

# BEGIN CONFIG
$script:EnvConfig = @{
    # Splunk Configuration
    SplunkServer    = ""
    SplunkPort      = "9997"
    SplunkWebPort   = "8000"
    SplunkMgmtPort  = "8089"
    SplunkVersion   = ""
    SplunkBuild     = ""

    # Network Subnets
    LinuxSubnet      = ""
    WindowsSubnet    = ""
    ManagementSubnet = ""

    # Wazuh
    WazuhManager    = ""

    # Host IPs
    SplunkHost      = ""
    EcomHost        = ""
    WebmailHost     = ""
    ADHost          = ""
    WebWinHost      = ""
    FTPHost         = ""
    WorkstationHost = ""

    # Firewall / Network Device IPs
    PaloAltoIP   = ""
    CiscoFTDIP   = ""
    VyOSRouterIP = ""

    # Competition Users
    CompAdmin1 = ""
    CompAdmin2 = ""
    CompUser1  = ""

    # Team Configuration
    RepoUrl      = "https://github.com/byui-soc/ccdc26.git"
    TeamNumber   = ""
    PasswordSalt = ""
}

$script:EnvConfigured = $false
# END CONFIG

function Get-EnvConfig {
    return $script:EnvConfig
}

function Test-EnvConfigured {
    if (-not $script:EnvConfigured) {
        Write-Host ""
        Write-Host "[!!] Environment is NOT configured." -ForegroundColor Red
        Write-Host "     Run deploy.sh --configure on the Linux box to regenerate." -ForegroundColor Red
        Write-Host ""
        return $false
    }
    return $true
}

function Set-EnvironmentConfig {
    <#
    .SYNOPSIS
        Interactively update environment configuration values.
    .DESCRIPTION
        Prompts for each configuration key and lets you accept the current
        default (press Enter) or type a new value. Persists changes to config.ps1.
    #>
    Write-Host "`n=== CCDC Environment Configuration ===" -ForegroundColor Cyan
    Write-Host "Fill in each value. Press Enter to keep current value (if any).`n" -ForegroundColor Gray

    foreach ($key in $script:EnvConfig.Keys | Sort-Object) {
        $current = $script:EnvConfig[$key]
        $displayCurrent = if ([string]::IsNullOrEmpty($current)) { "<empty>" } else { $current }
        $input = Read-Host "$key [$displayCurrent]"
        if (-not [string]::IsNullOrWhiteSpace($input)) {
            $script:EnvConfig[$key] = $input
        }
    }

    $script:EnvConfigured = $true
    Write-Host "`n[OK] Configuration updated in memory." -ForegroundColor Green

    $filePath = $null
    foreach ($candidate in @(
        (Join-Path $PSScriptRoot "config.ps1"),
        (Join-Path $PSScriptRoot "..\config.ps1"),
        (Join-Path $PSScriptRoot "..\..\config.ps1"),
        (Join-Path $PSScriptRoot "..\..\..\config.ps1")
    )) {
        if (Test-Path $candidate) {
            $filePath = (Resolve-Path $candidate).Path
            break
        }
    }

    if (-not $filePath) {
        Write-Host "[WARN] Could not locate config.ps1 on disk -- changes are in memory only." -ForegroundColor Yellow
        return
    }

    try {
        $fileContent = Get-Content $filePath -Raw

        if ($fileContent -notmatch '# BEGIN CONFIG') {
            Write-Host "[WARN] config.ps1 is missing persistence markers -- cannot save automatically." -ForegroundColor Yellow
            Write-Host "       Edit $filePath by hand to persist values." -ForegroundColor Yellow
            return
        }

        $keyGroups = [ordered]@{
            "Splunk Configuration"          = @("SplunkServer","SplunkPort","SplunkWebPort","SplunkMgmtPort","SplunkVersion","SplunkBuild")
            "Network Subnets"               = @("LinuxSubnet","WindowsSubnet","ManagementSubnet")
            "Host IPs"                      = @("SplunkHost","EcomHost","WebmailHost","ADHost","WebWinHost","FTPHost","WorkstationHost")
            "Firewall / Network Device IPs" = @("PaloAltoIP","CiscoFTDIP","VyOSRouterIP")
            "Competition Users"             = @("CompAdmin1","CompAdmin2","CompUser1")
            "Team Configuration"            = @("RepoUrl","TeamNumber","PasswordSalt")
        }

        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('# BEGIN CONFIG')
        [void]$sb.AppendLine('$script:EnvConfig = @{')

        $knownKeys = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($group in $keyGroups.GetEnumerator()) {
            [void]$sb.AppendLine("    # $($group.Key)")
            foreach ($k in $group.Value) {
                [void]$knownKeys.Add($k)
                $v = if ($script:EnvConfig.ContainsKey($k)) { $script:EnvConfig[$k] } else { "" }
                if ($null -eq $v) { $v = "" }
                $pad = $k.PadRight(17)
                [void]$sb.AppendLine("    $pad= `"$v`"")
            }
            [void]$sb.AppendLine()
        }

        $extraKeys = $script:EnvConfig.Keys | Where-Object { -not $knownKeys.Contains($_) } | Sort-Object
        if ($extraKeys) {
            [void]$sb.AppendLine("    # Other")
            foreach ($k in $extraKeys) {
                $v = $script:EnvConfig[$k]
                if ($null -eq $v) { $v = "" }
                $pad = $k.PadRight(17)
                [void]$sb.AppendLine("    $pad= `"$v`"")
            }
            [void]$sb.AppendLine()
        }

        [void]$sb.AppendLine('}')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('# Set to $true after filling in values above')
        [void]$sb.AppendLine('$script:EnvConfigured = $true')
        [void]$sb.Append('# END CONFIG')

        $newBlock = $sb.ToString()
        $fileContent = [regex]::Replace($fileContent, '(?s)# BEGIN CONFIG\r?\n.*?# END CONFIG', $newBlock)
        [System.IO.File]::WriteAllText($filePath, $fileContent)

        Write-Host "[OK] Configuration saved to $filePath" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to save config file: $_" -ForegroundColor Red
        Write-Host "        Changes are still active in memory for this session." -ForegroundColor Yellow
    }
}

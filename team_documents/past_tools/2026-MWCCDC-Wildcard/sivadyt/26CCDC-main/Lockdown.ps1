<#
CCDC Blue Team Lockdown (Domain-Joined Web Server) - Windows Server 2019

WARNING:
- This is a HARD LOCKDOWN: inbound blocked by default, outbound blocked by default.
- RDP will be disabled.
- Run from console/VM access.
- Do NOT run this on a Domain Controller (script will refuse).

What it does:
- Creates local admin: CCDCBlueTeam (password: M3tro-WEB)
- Disables ALL other LOCAL accounts
- Sets password policy (min 14, complexity ON, max age 90)
- Sets lockout policy (5 attempts, 15 min duration)
- Firewall:
  - Disables ALL inbound firewall rules
  - Default inbound: BLOCK, then allow only:
      Inbound UDP: 80,123
      Inbound TCP: 80,443,9997
  - Default outbound: BLOCK, then allow:
      Outbound DNS: TCP/UDP 53
      Outbound HTTP/HTTPS: TCP 80/443
      Outbound AD/DC traffic to DC only (Kerberos/LDAP/SMB/RPC/NTP)
- Disables: Print Spooler, RemoteRegistry, SMBv1, RDP
- Enables Defender + real-time + cloud-delivered protection
#>
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------
# CONFIG (edit if needed)
# -------------------------
$DomainControllerIP = "172.20.240.102"   # your DC/DNS from earlier
$NewAdminUser       = "CCDCBlueTeam"
$PlainPassword      = "M3tro-WEB"        # as requested (note: shorter than 14; created BEFORE policy is enforced)

$MinPwLen               = 14
$MaxPwAgeDays           = 90            # within 60–90 requirement
$LockoutThreshold       = 5
$LockoutDurationMinutes = 15
$LockoutWindowMinutes   = 15

# -------------------------
# GUARD: refuse to run on a Domain Controller
# -------------------------
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.DomainRole -ge 4) {
        throw "This machine appears to be a Domain Controller (DomainRole=$($cs.DomainRole)). Refusing to run."
    }
} catch {
    Write-Error $_
    exit 1
}

# -------------------------
# Helpers
# -------------------------
function Ensure-LocalAdminUser {
    param([string]$Username, [string]$Password)

    $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    $sec = ConvertTo-SecureString $Password -AsPlainText -Force

    if (-not $existing) {
        New-LocalUser -Name $Username -Password $sec -FullName $Username `
            -Description "CCDC Blue Team Local Admin" -PasswordNeverExpires:$false | Out-Null
    } else {
        $existing | Set-LocalUser -Password $sec
        if ($existing.Enabled -eq $false) { Enable-LocalUser -Name $Username }
    }

    # Add to local Administrators
    $isMember = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\\$Username$" }

    if (-not $isMember) {
        Add-LocalGroupMember -Group "Administrators" -Member $Username
    }
}

function Disable-AllOtherLocalAccounts {
    param([string]$KeepUser)

    foreach ($u in Get-LocalUser) {
        if ($u.Name -ieq $KeepUser) { continue }
        if ($u.Enabled) {
            try { Disable-LocalUser -Name $u.Name } catch {}
        }
    }
}

function Set-LocalAccountPolicies {
    param(
        [int]$MinLength,
        [int]$MaxAgeDays,
        [int]$LockThreshold,
        [int]$LockDurationMinutes,
        [int]$LockWindowMinutes
    )

    # Local password + lockout policy via net accounts
    & net accounts /minpwlen:$MinLength | Out-Null
    & net accounts /maxpwage:$MaxAgeDays | Out-Null
    & net accounts /lockoutthreshold:$LockThreshold | Out-Null
    & net accounts /lockoutduration:$LockDurationMinutes | Out-Null
    & net accounts /lockoutwindow:$LockWindowMinutes | Out-Null

    # Enforce complexity via local security policy (secedit)
    $tmp = Join-Path $env:TEMP "ccdc_secpol.inf"
    $db  = Join-Path $env:TEMP "ccdc_secpol.sdb"

    & secedit /export /cfg $tmp | Out-Null
    $content = Get-Content $tmp -Raw

    if ($content -notmatch "\[System Access\]") {
        $content += "`r`n[System Access]`r`n"
    }

    if ($content -match "PasswordComplexity\s*=") {
        $content = [regex]::Replace($content, "PasswordComplexity\s*=\s*\d+", "PasswordComplexity = 1")
    } else {
        $content = $content -replace "(\[System Access\]\s*)", "`$1`r`nPasswordComplexity = 1`r`n"
    }

    Set-Content -Path $tmp -Value $content -Encoding Unicode
    & secedit /configure /db $db /cfg $tmp /areas SECURITYPOLICY | Out-Null
    & gpupdate /force | Out-Null
}

function Set-CCDCFirewallLockdown {
    param([string]$DCIP)

    # Disable all existing inbound rules (as requested)
    Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue |
        Disable-NetFirewallRule -ErrorAction SilentlyContinue

    # Default: block inbound + outbound on all profiles
    Set-NetFirewallProfile -Profile Domain,Public,Private `
        -Enabled True `
        -DefaultInboundAction Block `
        -DefaultOutboundAction Block

    # -----------------------------
    # INBOUND allow-list (ONLY these)
    # -----------------------------
    New-NetFirewallRule -DisplayName "CCDC ALLOW IN UDP 80,123" `
        -Direction Inbound -Action Allow -Protocol UDP -LocalPort 80,123 -Profile Any | Out-Null

    New-NetFirewallRule -DisplayName "CCDC ALLOW IN TCP 80,443,9997" `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80,443,9997 -Profile Any | Out-Null

    # -----------------------------
    # OUTBOUND baseline allow-list
    # -----------------------------
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT DNS UDP 53" `
        -Direction Outbound -Action Allow -Protocol UDP -RemotePort 53 -Profile Any | Out-Null

    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT DNS TCP 53" `
        -Direction Outbound -Action Allow -Protocol TCP -RemotePort 53 -Profile Any | Out-Null

    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT HTTP/HTTPS" `
        -Direction Outbound -Action Allow -Protocol TCP -RemotePort 80,443 -Profile Any | Out-Null

    # -----------------------------
    # OUTBOUND Domain/DC required (scoped to DC IP)
    # -----------------------------
    # Kerberos
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT Kerberos TCP 88 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 88 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT Kerberos UDP 88 to DC" `
        -Direction Outbound -Action Allow -Protocol UDP -RemoteAddress $DCIP -RemotePort 88 -Profile Any | Out-Null

    # Kerberos password change
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT Kerberos TCP 464 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 464 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT Kerberos UDP 464 to DC" `
        -Direction Outbound -Action Allow -Protocol UDP -RemoteAddress $DCIP -RemotePort 464 -Profile Any | Out-Null

    # LDAP / LDAPS
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT LDAP TCP 389 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 389 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT LDAP UDP 389 to DC" `
        -Direction Outbound -Action Allow -Protocol UDP -RemoteAddress $DCIP -RemotePort 389 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT LDAPS TCP 636 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 636 -Profile Any | Out-Null

    # Global Catalog
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT GC TCP 3268 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 3268 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT GC SSL TCP 3269 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 3269 -Profile Any | Out-Null

    # SMB (SYSVOL/NETLOGON access)
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT SMB TCP 445 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 445 -Profile Any | Out-Null

    # RPC Endpoint Mapper + Dynamic RPC
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT RPC TCP 135 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 135 -Profile Any | Out-Null
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT RPC Dynamic TCP 49152-65535 to DC" `
        -Direction Outbound -Action Allow -Protocol TCP -RemoteAddress $DCIP -RemotePort 49152-65535 -Profile Any | Out-Null

    # NTP (time sync to DC)
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT NTP UDP 123 to DC" `
        -Direction Outbound -Action Allow -Protocol UDP -RemoteAddress $DCIP -RemotePort 123 -Profile Any | Out-Null

    #Allow Powershell to ping
    New-NetFirewallRule -DisplayName "CCDC ALLOW OUT ICMPv4" `
  	-Direction Outbound -Action Allow -Protocol ICMPv4 -Profile Any | Out-Null

}

function Disable-Services-And-Features {
    # Print Spooler
    try {
        Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        Set-Service -Name Spooler -StartupType Disabled
    } catch {}

    # RemoteRegistry
    try {
        Stop-Service -Name RemoteRegistry -Force -ErrorAction SilentlyContinue
        Set-Service -Name RemoteRegistry -StartupType Disabled
    } catch {}

    # SMBv1
    try { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null } catch {}
    try { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null } catch {}

    # Disable RDP
    try {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1
    } catch {}
    try {
        Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue |
            Disable-NetFirewallRule -ErrorAction SilentlyContinue
    } catch {}
}

function Enable-DefenderProtections {
    # Service
    try {
        Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
    } catch {}

    # Real-time + cloud
    try { Set-MpPreference -DisableRealtimeMonitoring $false } catch {}
    try { Set-MpPreference -MAPSReporting 2 } catch {}         # cloud-delivered
    try { Set-MpPreference -SubmitSamplesConsent 1 } catch {}  # automatic safe samples
    try { Set-MpPreference -DisableBehaviorMonitoring $false } catch {}
}

# -------------------------
# EXECUTE (order matters!)
# - Create user first (password is shorter than min length policy)
# - Then apply policy
# -------------------------
Write-Host "[1/7] Creating/ensuring local admin user: $NewAdminUser"
Ensure-LocalAdminUser -Username $NewAdminUser -Password $PlainPassword

Write-Host "[2/7] Disabling ALL other local accounts (including Administrator)"
Disable-AllOtherLocalAccounts -KeepUser $NewAdminUser

Write-Host "[3/7] Setting password + lockout policies"
Set-LocalAccountPolicies -MinLength $MinPwLen -MaxAgeDays $MaxPwAgeDays `
    -LockThreshold $LockoutThreshold -LockDurationMinutes $LockoutDurationMinutes -LockWindowMinutes $LockoutWindowMinutes

Write-Host "[4/7] Applying firewall lockdown (domain-joined safe outbound to DC)"
Set-CCDCFirewallLockdown -DCIP $DomainControllerIP

Write-Host "[5/7] Disabling Spooler, RemoteRegistry, SMBv1, and RDP"
Disable-Services-And-Features

Write-Host "[6/7] Enabling Windows Defender + real-time + cloud-delivered protection"
Enable-DefenderProtections

Write-Host "[7/7] Quick status checks"
Write-Host "  - Local users enabled:"; Get-LocalUser | Select-Object Name,Enabled | Format-Table -AutoSize
Write-Host "  - Firewall profiles:"; Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction | Format-Table -AutoSize
Write-Host "  - Defender status:"; try { Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,IsTamperProtected,MAPSReporting | Format-List } catch { Write-Host "    (Get-MpComputerStatus not available)" }

Write-Host "`nDONE. Reboot recommended (especially for SMB feature changes)."

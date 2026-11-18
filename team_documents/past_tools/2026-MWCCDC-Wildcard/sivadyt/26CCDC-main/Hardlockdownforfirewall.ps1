<#
CCDC Blue Team Lockdown (Works on Member Servers AND Domain Controllers)

Prompts for:
- New admin username + password
- Inbound TCP/UDP ports to allow (only those, plus DC-required ports if running on a DC)

Behavior:
- If MEMBER (not DC):
  - Create/ensure LOCAL admin user and add to local Administrators
  - Disable other LOCAL accounts (but never disables the account you're running as)
- If DOMAIN CONTROLLER:
  - Create/ensure DOMAIN user and add to "Domain Admins"
  - Does NOT disable other domain users/accounts

Firewall (INBOUND ONLY):
- Disables all existing inbound firewall rules
- Sets default inbound = Block (outbound unchanged)
- Adds allow rules:
   - Member: ONLY ports you enter
   - DC: AD/DNS essential ports + ports you enter

Disables:
- Print Spooler, RemoteRegistry, SMBv1, RDP

Enables:
- Defender protections (best effort)
#>

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Try-Ignore([scriptblock]$sb) { try { & $sb | Out-Null } catch {} }
function Read-NonEmpty([string]$Prompt) {
    while ($true) {
        $v = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
    }
}
function Read-Ports([string]$Prompt) {
    while ($true) {
        $raw = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $parts = $raw -split '[,\s]+' | Where-Object { $_ -and $_.Trim() -ne "" }
        $ports = @()
        $ok = $true

        foreach ($p in $parts) {
            if ($p -notmatch '^\d+$') { $ok = $false; break }
            $n = [int]$p
            if ($n -lt 1 -or $n -gt 65535) { $ok = $false; break }
            $ports += $n
        }

        if (-not $ok -or -not $ports) { continue }
        return ($ports | Sort-Object -Unique)   # int[]
    }
}
function Merge-Ports([int[]]$a, [int[]]$b) {
    return @($a + $b) | Sort-Object -Unique
}

# Detect DC vs Member
$cs = Get-CimInstance Win32_ComputerSystem
$IsDC = ($cs.DomainRole -ge 4)
$CurrentUserName = $env:USERNAME

# Prompts (works for both)
$NewAdminUser   = Read-NonEmpty "NEW admin username (local on member / domain user on DC)"
$SecurePassword = Read-Host "Password for $NewAdminUser" -AsSecureString
$InboundTcpUser = Read-Ports "Inbound TCP ports to ALLOW (e.g., 80,443)"
$InboundUdpUser = Read-Ports "Inbound UDP ports to ALLOW (e.g., 53,123)"

# --- Account actions
function Ensure-LocalAdminUser {
    param([string]$Username, [securestring]$Password)

    $existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-LocalUser -Name $Username -Password $Password -FullName $Username `
            -Description "CCDC Blue Team Local Admin" -PasswordNeverExpires:$false | Out-Null
    } else {
        $existing | Set-LocalUser -Password $Password
        if ($existing.Enabled -eq $false) { Enable-LocalUser -Name $Username }
    }

    $isMember = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\\$Username$" -or $_.Name -ieq $Username }

    if (-not $isMember) { Add-LocalGroupMember -Group "Administrators" -Member $Username }
}

function Disable-AllOtherLocalAccounts {
    param([string]$KeepUser, [string]$AlsoKeepUser)

    foreach ($u in Get-LocalUser) {
        if ($u.Name -ieq $KeepUser) { continue }
        if ($u.Name -ieq $AlsoKeepUser) { continue }
        if ($u.Enabled) { Try-Ignore { Disable-LocalUser -Name $u.Name } }
    }
}

function Ensure-DomainAdminUser {
    param([string]$Username, [securestring]$Password)

    Import-Module ActiveDirectory -ErrorAction Stop

    $dn = (Get-ADDomain).DistinguishedName
    $existing = Get-ADUser -Filter "SamAccountName -eq '$Username'" -ErrorAction SilentlyContinue

    if (-not $existing) {
        New-ADUser -Name $Username -SamAccountName $Username -Enabled $true `
            -AccountPassword $Password -ChangePasswordAtLogon $false `
            -Path ("CN=Users,$dn") | Out-Null
    } else {
        # reset password + ensure enabled
        Set-ADAccountPassword -Identity $Username -Reset -NewPassword $Password
        Enable-ADAccount -Identity $Username
    }

    # Add to Domain Admins (best effort)
    Try-Ignore { Add-ADGroupMember -Identity "Domain Admins" -Members $Username }
}

# --- Allow ports for logging ---

New-NetFirewallRule -DisplayName "CCDC-Wazuh-Outbound" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 1514,1515 -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "CCDC-Wazuh-Inbound" -Direction Inbound -Action Allow -Protocol TCP -RemotePort 1514,1515 -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "CCDC-Splunk" -Direction Outbound -Action Allow -Protocol TCP -RemotePort 8089-9997 -Profile Any | Out-Null

# --- Firewall (Inbound only)
function Set-InboundFirewallLockdown {
    param([int[]]$AllowTcpPorts, [int[]]$AllowUdpPorts)

    # Disable all inbound rules
    Try-Ignore { Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue }

    # Block inbound by default (leave outbound alone)
    Try-Ignore { Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -DefaultInboundAction Block }

    $tcpLabel = ($AllowTcpPorts -join ",")
    $udpLabel = ($AllowUdpPorts -join ",")

    Try-Ignore {
        New-NetFirewallRule -DisplayName "CCDC ALLOW IN TCP ($tcpLabel)" `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort $AllowTcpPorts -Profile Any | Out-Null
    }
    Try-Ignore {
        New-NetFirewallRule -DisplayName "CCDC ALLOW IN UDP ($udpLabel)" `
            -Direction Inbound -Action Allow -Protocol UDP -LocalPort $AllowUdpPorts -Profile Any | Out-Null
    }
}

# --- Disable services/features
function Disable-Services-And-Features {
    Try-Ignore { Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue }
    Try-Ignore { Set-Service  -Name Spooler -StartupType Disabled }

    Try-Ignore { Stop-Service -Name RemoteRegistry -Force -ErrorAction SilentlyContinue }
    Try-Ignore { Set-Service  -Name RemoteRegistry -StartupType Disabled }

    Try-Ignore { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null }
    Try-Ignore { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null }

    # Disable RDP
    Try-Ignore { Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 }
    Try-Ignore { Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue }
}

# --- Defender
function Enable-DefenderProtections {
    Try-Ignore { Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue }
    Try-Ignore { Start-Service -Name WinDefend -ErrorAction SilentlyContinue }
    Try-Ignore { Set-MpPreference -DisableRealtimeMonitoring $false }
    Try-Ignore { Set-MpPreference -MAPSReporting 2 }
    Try-Ignore { Set-MpPreference -SubmitSamplesConsent 1 }
    Try-Ignore { Set-MpPreference -DisableBehaviorMonitoring $false }
}

# =========================
# RUN (minimal output)
# =========================
Write-Host "CCDC lockdown starting... ($([string]::Join('', @('Member','DC')[$IsDC])))"

if ($IsDC) {
    # DC required inbound ports (so AD still works)
    $DcTcpRequired = @(53,88,135,389,445,464,636,3268,3269,5722,9389,5985,5986,49443,47001,49152..65535)
    $DcUdpRequired = @(53,88,123,389,464)

    # Note: 49152..65535 creates a big array; Windows Firewall supports range better as string.
    # So we allow most with arrays, and add RPC dynamic as a range rule separately.
    $DcTcpCore = @(53,88,135,389,445,464,636,3268,3269,5722,9389)
    $AllowTcp = Merge-Ports $InboundTcpUser $DcTcpCore
    $AllowUdp = Merge-Ports $InboundUdpUser $DcUdpRequired

    Ensure-DomainAdminUser -Username $NewAdminUser -Password $SecurePassword

    Set-InboundFirewallLockdown -AllowTcpPorts $AllowTcp -AllowUdpPorts $AllowUdp

    # Add RPC dynamic TCP range for DC (required for many AD ops)
    Try-Ignore {
        New-NetFirewallRule -DisplayName "CCDC ALLOW IN TCP (RPC Dynamic 49152-65535)" `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort 49152-65535 -Profile Any | Out-Null
    }

} else {
    Ensure-LocalAdminUser -Username $NewAdminUser -Password $SecurePassword
    Disable-AllOtherLocalAccounts -KeepUser $NewAdminUser -AlsoKeepUser $CurrentUserName
    Set-InboundFirewallLockdown -AllowTcpPorts $InboundTcpUser -AllowUdpPorts $InboundUdpUser
}

Disable-Services-And-Features
Enable-DefenderProtections

Write-Host "Done. Reboot recommended."

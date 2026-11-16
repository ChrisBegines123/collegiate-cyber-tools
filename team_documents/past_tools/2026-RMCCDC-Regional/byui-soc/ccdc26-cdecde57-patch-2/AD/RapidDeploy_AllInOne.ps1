#####################################################
# RMCCDC - RAPID DEPLOY ALL-IN-ONE HARDENING
# Run as Domain Admin on Domain Controller
# Use this for fastest possible hardening at competition start
#####################################################

param(
    [switch]$Force = $false,  # Skip confirmation prompts
    [switch]$WhatIf = $false  # Preview mode
)

$ErrorActionPreference = "Continue"

Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║     RMCCDC RAPID DEPLOY - ALL-IN-ONE HARDENING            ║
║     Applies all critical fixes in one execution           ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

if ($WhatIf) {
    Write-Host "[WHATIF MODE - No changes will be made]" -ForegroundColor Yellow
}

if (-not $Force -and -not $WhatIf) {
    Write-Host "`nThis script will make the following changes:" -ForegroundColor Yellow
    Write-Host "  1. Disable Print Spooler service"
    Write-Host "  2. Set MachineAccountQuota to 0"
    Write-Host "  3. Require LDAP Signing"
    Write-Host "  4. Strengthen password policy (14 char min)"
    Write-Host "  5. Secure DNS zones"
    Write-Host "  6. Fix PasswordNeverExpires on accounts"
    Write-Host "  7. Remove nested groups from Enterprise Admins"
    Write-Host "  8. Enable audit policies for Splunk"
    Write-Host "  9. Enable PowerShell logging"
    Write-Host "  10. Disable LLMNR and NBT-NS"
    Write-Host "  11. Disable SMBv1 (EternalBlue mitigation)"
    Write-Host "  12. Zerologon mitigation (CVE-2020-1472)"
    
    $confirm = Read-Host "`nProceed? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit
    }
}

$startTime = Get-Date
$results = @()

Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Starting rapid hardening...`n" -ForegroundColor Cyan

#region 1. Print Spooler
Write-Host "[1/12] Print Spooler..." -NoNewline
try {
    if (-not $WhatIf) {
        Stop-Service Spooler -Force -ErrorAction SilentlyContinue
        Set-Service Spooler -StartupType Disabled
    }
    Write-Host " DISABLED" -ForegroundColor Green
    $results += @{Check="Print Spooler"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="Print Spooler"; Result="FAIL"}
}
#endregion

#region 2. MachineAccountQuota
Write-Host "[2/12] MachineAccountQuota..." -NoNewline
try {
    if (-not $WhatIf) {
        Set-ADDomain -Identity (Get-ADDomain).DNSRoot -Replace @{"ms-DS-MachineAccountQuota"="0"}
    }
    Write-Host " SET TO 0" -ForegroundColor Green
    $results += @{Check="MachineAccountQuota"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="MachineAccountQuota"; Result="FAIL"}
}
#endregion

#region 3. LDAP Signing
Write-Host "[3/12] LDAP Signing..." -NoNewline
try {
    if (-not $WhatIf) {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerIntegrity" -Value 2 -Type DWord
    }
    Write-Host " REQUIRED" -ForegroundColor Green
    $results += @{Check="LDAP Signing"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="LDAP Signing"; Result="FAIL"}
}
#endregion

#region 4. Password Policy
Write-Host "[4/12] Password Policy..." -NoNewline
try {
    if (-not $WhatIf) {
        Set-ADDefaultDomainPasswordPolicy -Identity (Get-ADDomain).DNSRoot `
            -MinPasswordLength 14 `
            -LockoutThreshold 5 `
            -LockoutDuration "00:30:00" `
            -LockoutObservationWindow "00:30:00" `
            -PasswordHistoryCount 24 `
            -ComplexityEnabled $true
    }
    Write-Host " STRENGTHENED (14 char, lockout 5)" -ForegroundColor Green
    $results += @{Check="Password Policy"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="Password Policy"; Result="FAIL"}
}
#endregion

#region 5. DNS Zones
Write-Host "[5/12] DNS Zones..." -NoNewline
try {
    $zones = Get-DnsServerZone | Where-Object { $_.DynamicUpdate -eq "NonsecureAndSecure" -and $_.ZoneType -eq "Primary" }
    $count = 0
    foreach ($zone in $zones) {
        if (-not $WhatIf) {
            Set-DnsServerPrimaryZone -Name $zone.ZoneName -DynamicUpdate Secure
        }
        $count++
    }
    Write-Host " SECURED ($count zones)" -ForegroundColor Green
    $results += @{Check="DNS Zones"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="DNS Zones"; Result="FAIL"}
}
#endregion

#region 6. Password Never Expires
Write-Host "[6/12] PasswordNeverExpires..." -NoNewline
try {
    $users = Get-ADUser -Filter {PasswordNeverExpires -eq $true -and Enabled -eq $true} |
        Where-Object { $_.SamAccountName -notmatch "^(krbtgt|AZUREADSSOACC|DefaultAccount)$" }
    $count = 0
    foreach ($user in $users) {
        if (-not $WhatIf) {
            Set-ADUser -Identity $user -PasswordNeverExpires $false
        }
        $count++
    }
    Write-Host " FIXED ($count accounts)" -ForegroundColor Green
    $results += @{Check="PasswordNeverExpires"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="PasswordNeverExpires"; Result="FAIL"}
}
#endregion

#region 7. Nested EA Groups
Write-Host "[7/12] Nested EA Groups..." -NoNewline
try {
    $nestedGroups = Get-ADGroupMember "Enterprise Admins" | Where-Object { $_.objectClass -eq 'group' }
    $count = 0
    foreach ($group in $nestedGroups) {
        if (-not $WhatIf) {
            Remove-ADGroupMember -Identity "Enterprise Admins" -Members $group -Confirm:$false
        }
        $count++
    }
    Write-Host " REMOVED ($count groups)" -ForegroundColor Green
    $results += @{Check="Nested EA Groups"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="Nested EA Groups"; Result="FAIL"}
}
#endregion

#region 8. Audit Policy
Write-Host "[8/12] Audit Policy..." -NoNewline
try {
    if (-not $WhatIf) {
        $null = auditpol /set /subcategory:"Logon" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable 2>&1
        $null = auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable 2>&1
        
        # Command line auditing
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    }
    Write-Host " ENABLED" -ForegroundColor Green
    $results += @{Check="Audit Policy"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="Audit Policy"; Result="FAIL"}
}
#endregion

#region 9. PowerShell Logging
Write-Host "[9/12] PowerShell Logging..." -NoNewline
try {
    if (-not $WhatIf) {
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
        
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "EnableModuleLogging" -Value 1 -Type DWord
        $modulePath = "$regPath\ModuleNames"
        if (-not (Test-Path $modulePath)) { New-Item -Path $modulePath -Force | Out-Null }
        Set-ItemProperty -Path $modulePath -Name "*" -Value "*" -Type String
    }
    Write-Host " ENABLED" -ForegroundColor Green
    $results += @{Check="PowerShell Logging"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="PowerShell Logging"; Result="FAIL"}
}
#endregion

#region 10. LLMNR/NBT-NS
Write-Host "[10/12] LLMNR/NBT-NS..." -NoNewline
try {
    if (-not $WhatIf) {
        # LLMNR
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "EnableMulticast" -Value 0 -Type DWord
        
        # NBT-NS - using Get-CimInstance instead of deprecated Get-WmiObject
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        foreach ($adapter in $adapters) {
            $null = Invoke-CimMethod -InputObject $adapter -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions = 2}
        }
    }
    Write-Host " DISABLED" -ForegroundColor Green
    $results += @{Check="LLMNR/NBT-NS"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="LLMNR/NBT-NS"; Result="FAIL"}
}
#endregion

#region 11. SMBv1
Write-Host "[11/12] SMBv1 (EternalBlue)..." -NoNewline
try {
    if (-not $WhatIf) {
        # Disable SMBv1 Server
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop
        
        # Also set via registry as backup
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Host " DISABLED" -ForegroundColor Green
    $results += @{Check="SMBv1"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="SMBv1"; Result="FAIL"}
}
#endregion

#region 12. Zerologon
Write-Host "[12/12] Zerologon (CVE-2020-1472)..." -NoNewline
try {
    if (-not $WhatIf) {
        $netlogonPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        # Enable secure channel protection
        Set-ItemProperty -Path $netlogonPath -Name "FullSecureChannelProtection" -Value 1 -Type DWord -Force
        # Remove any vulnerable channel allowlist
        Remove-ItemProperty -Path $netlogonPath -Name "vulnerablechannelallowlist" -Force -ErrorAction SilentlyContinue
    }
    Write-Host " PATCHED" -ForegroundColor Green
    $results += @{Check="Zerologon"; Result="OK"}
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    $results += @{Check="Zerologon"; Result="FAIL"}
}
#endregion

#region Summary
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "RAPID DEPLOY COMPLETE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

$passed = ($results | Where-Object { $_.Result -eq "OK" }).Count
$failed = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
$total = $results.Count

Write-Host "`nResults: $passed/$total PASSED in $($duration.TotalSeconds.ToString('0.0')) seconds" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })

if ($failed -gt 0) {
    Write-Host "`nFailed items:" -ForegroundColor Red
    $results | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Check)" -ForegroundColor Red
    }
}

Write-Host @"

═══════════════════════════════════════════════════════════
REMAINING MANUAL TASKS:
═══════════════════════════════════════════════════════════
  1. Logoff admin sessions on workstations (check with query user)
  2. Remove Domain Users from RDP groups on workstations
  3. Apply GPO to deny DA logon to workstations
  4. Disable RC4 for Kerberos via GPO
  5. Deploy SMBv1 disable to member servers/workstations
  6. Deploy hardening to member servers (run separate scripts)

Run Verify_Hardening.ps1 to confirm all changes!
═══════════════════════════════════════════════════════════
"@ -ForegroundColor Yellow
#endregion

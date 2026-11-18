#####################################################
# RMCCDC Phase 2 - HIGH PRIORITY Hardening (5-15 Minutes)
# Run as Domain Admin on Domain Controller
#####################################################

param(
    [switch]$WhatIf = $false
)

$ErrorActionPreference = "Continue"
Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║     RMCCDC PHASE 2 - HIGH PRIORITY AD HARDENING           ║
║     Run after Phase 1 (minutes 5-15)                      ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "[WHATIF MODE - No changes will be made]`n" -ForegroundColor Yellow
}

$results = @()

#region 1. Check and Fix Nested Enterprise Admin Paths
Write-Host "[1/7] Checking for Nested Enterprise Admin Membership..." -ForegroundColor Yellow
try {
    $eaMembers = Get-ADGroupMember "Enterprise Admins" -ErrorAction Stop
    $nestedGroups = $eaMembers | Where-Object { $_.objectClass -eq 'group' }
    
    if ($nestedGroups) {
        Write-Host "  [!] NESTED GROUPS IN ENTERPRISE ADMINS:" -ForegroundColor Red
        foreach ($group in $nestedGroups) {
            Write-Host "    - $($group.Name)" -ForegroundColor Red
            
            # Show what's in the nested group
            $nestedMembers = Get-ADGroupMember $group.Name -ErrorAction SilentlyContinue
            foreach ($member in $nestedMembers) {
                Write-Host "      +-- $($member.Name) ($($member.objectClass))" -ForegroundColor Yellow
            }
            
            if (-not $WhatIf) {
                Write-Host "    Removing $($group.Name) from Enterprise Admins..." -ForegroundColor Yellow
                Remove-ADGroupMember -Identity "Enterprise Admins" -Members $group -Confirm:$false
                Write-Host "    [+] Removed" -ForegroundColor Green
            }
        }
        $results += [PSCustomObject]@{Check="Nested EA Groups"; Status="FIXED"; Notes="Removed $($nestedGroups.Count) nested group(s)"}
    } else {
        Write-Host "  [+] No nested groups in Enterprise Admins" -ForegroundColor Green
        $results += [PSCustomObject]@{Check="Nested EA Groups"; Status="OK"; Notes="No nested groups"}
    }
    
    # Show current EA membership
    Write-Host "`n  Current Enterprise Admins:" -ForegroundColor Cyan
    Get-ADGroupMember "Enterprise Admins" -Recursive | ForEach-Object {
        Write-Host "    - $($_.Name)" -ForegroundColor White
    }
} catch {
    $results += [PSCustomObject]@{Check="Nested EA Groups"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 2. Strengthen Password Policy
Write-Host "`n[2/7] Strengthening Default Domain Password Policy..." -ForegroundColor Yellow
try {
    $currentPolicy = Get-ADDefaultDomainPasswordPolicy
    $needsChange = $false
    $changes = @()
    
    if ($currentPolicy.MinPasswordLength -lt 14) {
        $changes += "MinLength: $($currentPolicy.MinPasswordLength) -> 14"
        $needsChange = $true
    }
    if ($currentPolicy.LockoutThreshold -eq 0 -or $currentPolicy.LockoutThreshold -gt 5) {
        $changes += "LockoutThreshold: $($currentPolicy.LockoutThreshold) -> 5"
        $needsChange = $true
    }
    if (-not $currentPolicy.ComplexityEnabled) {
        $changes += "Complexity: Disabled -> Enabled"
        $needsChange = $true
    }
    
    if ($needsChange) {
        if (-not $WhatIf) {
            Set-ADDefaultDomainPasswordPolicy -Identity (Get-ADDomain).DNSRoot `
                -MinPasswordLength 14 `
                -LockoutThreshold 5 `
                -LockoutDuration "00:30:00" `
                -LockoutObservationWindow "00:30:00" `
                -PasswordHistoryCount 24 `
                -ComplexityEnabled $true
        }
        $results += [PSCustomObject]@{Check="Password Policy"; Status="FIXED"; Notes=($changes -join ", ")}
        Write-Host "  [+] Password policy strengthened" -ForegroundColor Green
        $changes | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
    } else {
        $results += [PSCustomObject]@{Check="Password Policy"; Status="OK"; Notes="Already meets requirements"}
        Write-Host "  [+] Password policy already meets requirements" -ForegroundColor Green
    }
    
    Write-Host "`n  Current Policy:" -ForegroundColor Cyan
    Write-Host "    MinLength: $($currentPolicy.MinPasswordLength)" -ForegroundColor White
    Write-Host "    LockoutThreshold: $($currentPolicy.LockoutThreshold)" -ForegroundColor White
    Write-Host "    Complexity: $($currentPolicy.ComplexityEnabled)" -ForegroundColor White
} catch {
    $results += [PSCustomObject]@{Check="Password Policy"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 3. Secure DNS Zones
Write-Host "`n[3/7] Securing DNS Zones..." -ForegroundColor Yellow
try {
    $zones = Get-DnsServerZone -ErrorAction Stop | Where-Object { 
        $_.DynamicUpdate -eq "NonsecureAndSecure" -and 
        $_.ZoneType -eq "Primary" 
    }
    
    if ($zones) {
        foreach ($zone in $zones) {
            if (-not $WhatIf) {
                Set-DnsServerPrimaryZone -Name $zone.ZoneName -DynamicUpdate Secure
            }
            Write-Host "  [+] Secured: $($zone.ZoneName)" -ForegroundColor Green
        }
        $results += [PSCustomObject]@{Check="DNS Zones"; Status="FIXED"; Notes="Secured $($zones.Count) zone(s)"}
    } else {
        $results += [PSCustomObject]@{Check="DNS Zones"; Status="OK"; Notes="All zones already secured"}
        Write-Host "  [+] All DNS zones already secured" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="DNS Zones"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 4. Fix Password Never Expires on Privileged Accounts
Write-Host "`n[4/7] Fixing PasswordNeverExpires on Privileged Accounts..." -ForegroundColor Yellow
try {
    $privilegedUsers = Get-ADUser -Filter {
        PasswordNeverExpires -eq $true -and 
        Enabled -eq $true
    } -Properties PasswordNeverExpires, AdminCount | Where-Object {
        $_.SamAccountName -notmatch "^(krbtgt|AZUREADSSOACC|DefaultAccount)$"
    }
    
    if ($privilegedUsers) {
        $fixedCount = 0
        foreach ($user in $privilegedUsers) {
            if (-not $WhatIf) {
                Set-ADUser -Identity $user -PasswordNeverExpires $false
            }
            $fixedCount++
            $adminStatus = if ($user.AdminCount -eq 1) { "[PRIVILEGED]" } else { "" }
            Write-Host "  [+] Fixed: $($user.SamAccountName) $adminStatus" -ForegroundColor Green
        }
        $results += [PSCustomObject]@{Check="Password Expiration"; Status="FIXED"; Notes="Enabled expiration on $fixedCount account(s)"}
    } else {
        $results += [PSCustomObject]@{Check="Password Expiration"; Status="OK"; Notes="No accounts with PasswordNeverExpires"}
        Write-Host "  [+] No accounts need fixing" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="Password Expiration"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 5. Review Domain Admins
Write-Host "`n[5/7] Reviewing Domain Admin Membership..." -ForegroundColor Yellow
try {
    $domainAdmins = Get-ADGroupMember "Domain Admins" | Get-ADUser -Properties PasswordLastSet, LastLogonDate, PasswordNeverExpires
    
    Write-Host "  Current Domain Admins:" -ForegroundColor Cyan
    foreach ($da in $domainAdmins) {
        $flags = @()
        if ($da.PasswordNeverExpires) { $flags += "PwdNoExpire" }
        if ($da.LastLogonDate -lt (Get-Date).AddDays(-30)) { $flags += "Stale" }
        
        $flagStr = if ($flags) { " [" + ($flags -join ", ") + "]" } else { "" }
        $color = if ($flags) { "Yellow" } else { "White" }
        
        Write-Host "    - $($da.SamAccountName)$flagStr" -ForegroundColor $color
        Write-Host "      Last Logon: $($da.LastLogonDate)" -ForegroundColor Gray
    }
    
    if ($domainAdmins.Count -gt 2) {
        $results += [PSCustomObject]@{Check="Domain Admins"; Status="WARNING"; Notes="$($domainAdmins.Count) DAs - review for reduction"}
        Write-Host "`n  [!] Consider reducing DA count (currently $($domainAdmins.Count))" -ForegroundColor Yellow
    } else {
        $results += [PSCustomObject]@{Check="Domain Admins"; Status="OK"; Notes="$($domainAdmins.Count) Domain Admins"}
    }
} catch {
    $results += [PSCustomObject]@{Check="Domain Admins"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 6. Remove Domain Users from RDP (Info Only)
Write-Host "`n[6/7] Checking RDP Access on Member Systems..." -ForegroundColor Yellow
try {
    $dc = (Get-ADDomainController).Name
    $computers = Get-ADComputer -Filter * | Where-Object { $_.Name -ne $dc }
    
    $rdpIssues = @()
    foreach ($computer in $computers) {
        try {
            $rdpUsers = Invoke-Command -ComputerName $computer.Name -ScriptBlock {
                Get-LocalGroupMember "Remote Desktop Users" -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -match "Domain Users" }
            } -ErrorAction SilentlyContinue
            
            if ($rdpUsers) {
                $rdpIssues += $computer.Name
                Write-Host "  [!] $($computer.Name): Domain Users can RDP" -ForegroundColor Red
            } else {
                Write-Host "  [+] $($computer.Name): RDP restricted" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [?] $($computer.Name): Unable to check" -ForegroundColor Yellow
        }
    }
    
    if ($rdpIssues.Count -gt 0) {
        $results += [PSCustomObject]@{Check="RDP Access"; Status="WARNING"; Notes="Domain Users can RDP to: $($rdpIssues -join ', ')"}
        Write-Host "`n  === MANUAL FIX REQUIRED ===" -ForegroundColor Red
        Write-Host "  Run on each affected workstation:" -ForegroundColor Yellow
        Write-Host '  Remove-LocalGroupMember -Group "Remote Desktop Users" -Member "CCDCTEAM\Domain Users"' -ForegroundColor White
    } else {
        $results += [PSCustomObject]@{Check="RDP Access"; Status="OK"; Notes="RDP properly restricted"}
    }
} catch {
    $results += [PSCustomObject]@{Check="RDP Access"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 7. Zerologon Mitigation
Write-Host "`n[7/7] Applying Zerologon Mitigation (CVE-2020-1472)..." -ForegroundColor Yellow
try {
    $netlogonPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
    $currentValue = (Get-ItemProperty -Path $netlogonPath -Name "FullSecureChannelProtection" -ErrorAction SilentlyContinue).FullSecureChannelProtection
    
    if ($currentValue -ne 1) {
        if (-not $WhatIf) {
            # Enable secure channel protection
            Set-ItemProperty -Path $netlogonPath -Name "FullSecureChannelProtection" -Value 1 -Type DWord -Force
            # Remove any vulnerable channel allowlist
            Remove-ItemProperty -Path $netlogonPath -Name "vulnerablechannelallowlist" -Force -ErrorAction SilentlyContinue
        }
        $results += [PSCustomObject]@{Check="Zerologon"; Status="FIXED"; Notes="Enabled FullSecureChannelProtection"}
        Write-Host "  [+] Zerologon mitigation applied" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="Zerologon"; Status="OK"; Notes="Already patched"}
        Write-Host "  [+] Zerologon already mitigated" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="Zerologon"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region Summary
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PHASE 2 SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$fixed = ($results | Where-Object { $_.Status -eq "FIXED" }).Count
$ok = ($results | Where-Object { $_.Status -eq "OK" }).Count
$warnings = ($results | Where-Object { $_.Status -eq "WARNING" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAILED" }).Count

Write-Host "Fixed: $fixed | Already OK: $ok | Warnings: $warnings | Failed: $failed" -ForegroundColor $(if ($failed -gt 0) {'Red'} elseif ($warnings -gt 0) {'Yellow'} else {'Green'})
Write-Host "`n>> Next: Run Phase3_Auditing_Hardening.ps1 or apply GPO settings manually" -ForegroundColor Cyan
#endregion

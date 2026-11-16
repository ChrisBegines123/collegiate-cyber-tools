#####################################################
# RMCCDC Phase 1 - CRITICAL Hardening (First 5 Minutes)
# Run as Domain Admin on Domain Controller
#####################################################

param(
    [switch]$WhatIf = $false
)

$ErrorActionPreference = "Continue"
Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║     RMCCDC PHASE 1 - CRITICAL AD HARDENING                ║
║     Run within first 5 minutes of competition             ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "[WHATIF MODE - No changes will be made]`n" -ForegroundColor Yellow
}

$results = @()

#region 1. Disable Print Spooler (PrintNightmare)
Write-Host "[1/4] Disabling Print Spooler Service..." -ForegroundColor Yellow
try {
    $spooler = Get-Service Spooler -ErrorAction Stop
    if ($spooler.Status -eq 'Running' -or $spooler.StartType -ne 'Disabled') {
        if (-not $WhatIf) {
            Stop-Service Spooler -Force -ErrorAction Stop
            Set-Service Spooler -StartupType Disabled -ErrorAction Stop
        }
        $results += [PSCustomObject]@{Check="Print Spooler"; Status="FIXED"; Notes="Stopped and disabled"}
        Write-Host "  [+] Print Spooler disabled" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="Print Spooler"; Status="OK"; Notes="Already disabled"}
        Write-Host "  [+] Print Spooler already disabled" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="Print Spooler"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 2. Set MachineAccountQuota to 0 (RBCD Prevention)
Write-Host "[2/4] Setting MachineAccountQuota to 0..." -ForegroundColor Yellow
try {
    $domain = Get-ADDomain
    $currentQuota = (Get-ADObject $domain.DistinguishedName -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota'
    
    if ($currentQuota -ne 0) {
        if (-not $WhatIf) {
            Set-ADDomain -Identity $domain.DNSRoot -Replace @{"ms-DS-MachineAccountQuota"="0"}
        }
        $results += [PSCustomObject]@{Check="MachineAccountQuota"; Status="FIXED"; Notes="Changed from $currentQuota to 0"}
        Write-Host "  [+] MachineAccountQuota set to 0 (was $currentQuota)" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="MachineAccountQuota"; Status="OK"; Notes="Already 0"}
        Write-Host "  [+] MachineAccountQuota already 0" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="MachineAccountQuota"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 3. Require LDAP Signing
Write-Host "[3/4] Requiring LDAP Signing..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"
    $currentValue = (Get-ItemProperty -Path $regPath -Name "LDAPServerIntegrity" -ErrorAction SilentlyContinue).LDAPServerIntegrity
    
    if ($currentValue -ne 2) {
        if (-not $WhatIf) {
            Set-ItemProperty -Path $regPath -Name "LDAPServerIntegrity" -Value 2 -Type DWord
        }
        $results += [PSCustomObject]@{Check="LDAP Signing"; Status="FIXED"; Notes="Changed from $currentValue to 2 (Required)"}
        Write-Host "  [+] LDAP Signing now required" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="LDAP Signing"; Status="OK"; Notes="Already required"}
        Write-Host "  [+] LDAP Signing already required" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="LDAP Signing"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 4. Identify Admin Sessions on Workstations
Write-Host "[4/4] Checking for Admin Sessions on Non-DCs..." -ForegroundColor Yellow
try {
    $dc = (Get-ADDomainController).Name
    $computers = Get-ADComputer -Filter * | Where-Object { $_.Name -ne $dc }
    
    Write-Host "  Domain Controller: $dc" -ForegroundColor Cyan
    Write-Host "  Checking workstations/servers for admin sessions..." -ForegroundColor Cyan
    
    $sessionsFound = @()
    foreach ($computer in $computers) {
        try {
            $sessions = Invoke-Command -ComputerName $computer.Name -ScriptBlock {
                query user 2>$null | Select-Object -Skip 1 | ForEach-Object {
                    $parts = $_ -split '\s+'
                    [PSCustomObject]@{
                        Username = $parts[0]
                        SessionID = $parts[2]
                        State = $parts[3]
                    }
                }
            } -ErrorAction SilentlyContinue
            
            # Match privileged account patterns - Domain Admins, Enterprise Admins, local admin
            $adminSessions = $sessions | Where-Object { 
                $_.Username -match '(?i)^(administrator|admin)$|admin(istrator)?s?$|^da[-_]|^ea[-_]|[-_]admin$'
            }
            
            if ($adminSessions) {
                foreach ($session in $adminSessions) {
                    $sessionsFound += [PSCustomObject]@{
                        Computer = $computer.Name
                        Username = $session.Username
                        SessionID = $session.SessionID
                    }
                    Write-Host "  [!] ADMIN SESSION: $($session.Username) on $($computer.Name) (Session $($session.SessionID))" -ForegroundColor Red
                }
            } else {
                Write-Host "  [+] $($computer.Name): No admin sessions" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [?] $($computer.Name): Unable to query (offline or access denied)" -ForegroundColor Yellow
        }
    }
    
    if ($sessionsFound.Count -gt 0) {
        $results += [PSCustomObject]@{Check="Admin Sessions"; Status="WARNING"; Notes="$($sessionsFound.Count) admin session(s) on workstations - LOGOFF REQUIRED"}
        Write-Host "`n  === ACTION REQUIRED ===" -ForegroundColor Red
        Write-Host "  Run the following to logoff admin sessions:" -ForegroundColor Yellow
        foreach ($s in $sessionsFound) {
            Write-Host "  Invoke-Command -ComputerName $($s.Computer) -ScriptBlock { logoff $($s.SessionID) }" -ForegroundColor White
        }
    } else {
        $results += [PSCustomObject]@{Check="Admin Sessions"; Status="OK"; Notes="No admin sessions on workstations"}
    }
} catch {
    $results += [PSCustomObject]@{Check="Admin Sessions"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region Summary
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PHASE 1 SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$fixed = ($results | Where-Object { $_.Status -eq "FIXED" }).Count
$ok = ($results | Where-Object { $_.Status -eq "OK" }).Count
$warnings = ($results | Where-Object { $_.Status -eq "WARNING" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAILED" }).Count

Write-Host "Fixed: $fixed | Already OK: $ok | Warnings: $warnings | Failed: $failed" -ForegroundColor $(if ($failed -gt 0) {'Red'} elseif ($warnings -gt 0) {'Yellow'} else {'Green'})
Write-Host "`n>> Next: Run Phase2_HighPriority_Hardening.ps1" -ForegroundColor Cyan
#endregion

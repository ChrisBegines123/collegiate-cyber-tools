#####################################################
# RMCCDC Phase 3 - AUDITING & ADVANCED HARDENING
# Run as Domain Admin on Domain Controller
#####################################################

param(
    [switch]$WhatIf = $false
)

$ErrorActionPreference = "Continue"
Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║     RMCCDC PHASE 3 - AUDITING & ADVANCED HARDENING        ║
║     Enable detection capabilities (15-30 minutes)         ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "[WHATIF MODE - No changes will be made]`n" -ForegroundColor Yellow
}

$results = @()

#region 1. Enable Advanced Audit Policy
Write-Host "[1/7] Enabling Advanced Audit Policy..." -ForegroundColor Yellow
try {
    $auditSettings = @(
        @{Category="Logon"; Success=$true; Failure=$true},
        @{Category="Logoff"; Success=$true; Failure=$false},
        @{Category="Account Lockout"; Success=$true; Failure=$true},
        @{Category="Kerberos Service Ticket Operations"; Success=$true; Failure=$true},
        @{Category="Kerberos Authentication Service"; Success=$true; Failure=$true},
        @{Category="Directory Service Access"; Success=$true; Failure=$true},
        @{Category="Directory Service Changes"; Success=$true; Failure=$true},
        @{Category="Computer Account Management"; Success=$true; Failure=$true},
        @{Category="User Account Management"; Success=$true; Failure=$true},
        @{Category="Security Group Management"; Success=$true; Failure=$true},
        @{Category="Process Creation"; Success=$true; Failure=$false},
        @{Category="Sensitive Privilege Use"; Success=$true; Failure=$true}
    )
    
    foreach ($setting in $auditSettings) {
        $successFlag = if ($setting.Success) { "enable" } else { "disable" }
        $failureFlag = if ($setting.Failure) { "enable" } else { "disable" }
        
        if (-not $WhatIf) {
            $null = auditpol /set /subcategory:"$($setting.Category)" /success:$successFlag /failure:$failureFlag 2>&1
        }
        Write-Host "  [+] $($setting.Category): Success=$successFlag, Failure=$failureFlag" -ForegroundColor Green
    }
    $results += [PSCustomObject]@{Check="Audit Policy"; Status="FIXED"; Notes="Enabled $($auditSettings.Count) audit subcategories"}
} catch {
    $results += [PSCustomObject]@{Check="Audit Policy"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 2. Enable Command-Line Auditing in Process Creation
Write-Host "`n[2/7] Enabling Command-Line Process Auditing..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    
    if (-not (Test-Path $regPath)) {
        if (-not $WhatIf) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    
    $currentValue = (Get-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -ErrorAction SilentlyContinue).ProcessCreationIncludeCmdLine_Enabled
    
    if ($currentValue -ne 1) {
        if (-not $WhatIf) {
            Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
        }
        $results += [PSCustomObject]@{Check="CmdLine Auditing"; Status="FIXED"; Notes="Enabled command-line logging in 4688 events"}
        Write-Host "  [+] Command-line auditing enabled" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="CmdLine Auditing"; Status="OK"; Notes="Already enabled"}
        Write-Host "  [+] Already enabled" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="CmdLine Auditing"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 3. Enable PowerShell Script Block Logging
Write-Host "`n[3/7] Enabling PowerShell Script Block Logging..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    
    if (-not (Test-Path $regPath)) {
        if (-not $WhatIf) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    
    if (-not $WhatIf) {
        Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
    }
    $results += [PSCustomObject]@{Check="PS ScriptBlock Log"; Status="FIXED"; Notes="Enabled 4104 events"}
    Write-Host "  [+] PowerShell ScriptBlock logging enabled (Event 4104)" -ForegroundColor Green
} catch {
    $results += [PSCustomObject]@{Check="PS ScriptBlock Log"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 4. Enable Module Logging
Write-Host "`n[4/7] Enabling PowerShell Module Logging..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    
    if (-not (Test-Path $regPath)) {
        if (-not $WhatIf) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    
    if (-not $WhatIf) {
        Set-ItemProperty -Path $regPath -Name "EnableModuleLogging" -Value 1 -Type DWord
        
        # Log all modules
        $modulePath = "$regPath\ModuleNames"
        if (-not (Test-Path $modulePath)) {
            New-Item -Path $modulePath -Force | Out-Null
        }
        Set-ItemProperty -Path $modulePath -Name "*" -Value "*" -Type String
    }
    $results += [PSCustomObject]@{Check="PS Module Log"; Status="FIXED"; Notes="Enabled for all modules"}
    Write-Host "  [+] PowerShell Module logging enabled for all modules" -ForegroundColor Green
} catch {
    $results += [PSCustomObject]@{Check="PS Module Log"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 5. Disable LLMNR
Write-Host "`n[5/7] Disabling LLMNR (Responder mitigation)..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    
    if (-not (Test-Path $regPath)) {
        if (-not $WhatIf) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    
    $currentValue = (Get-ItemProperty -Path $regPath -Name "EnableMulticast" -ErrorAction SilentlyContinue).EnableMulticast
    
    if ($currentValue -ne 0) {
        if (-not $WhatIf) {
            Set-ItemProperty -Path $regPath -Name "EnableMulticast" -Value 0 -Type DWord
        }
        $results += [PSCustomObject]@{Check="LLMNR"; Status="FIXED"; Notes="Disabled multicast name resolution"}
        Write-Host "  [+] LLMNR disabled" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="LLMNR"; Status="OK"; Notes="Already disabled"}
        Write-Host "  [+] LLMNR already disabled" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="LLMNR"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 6. Disable NBT-NS
Write-Host "`n[6/7] Disabling NBT-NS (Responder mitigation)..." -ForegroundColor Yellow
try {
    $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
    $disabledCount = 0
    
    foreach ($adapter in $adapters) {
        $currentSetting = $adapter.TcpipNetbiosOptions
        if ($currentSetting -ne 2) {
            if (-not $WhatIf) {
                # Use CIM method invocation for setting NetBIOS options
                $null = Invoke-CimMethod -InputObject $adapter -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions = 2}
            }
            $disabledCount++
            Write-Host "  [+] Disabled NBT-NS on: $($adapter.Description)" -ForegroundColor Green
        }
    }
    
    if ($disabledCount -gt 0) {
        $results += [PSCustomObject]@{Check="NBT-NS"; Status="FIXED"; Notes="Disabled on $disabledCount adapter(s)"}
    } else {
        $results += [PSCustomObject]@{Check="NBT-NS"; Status="OK"; Notes="Already disabled"}
        Write-Host "  [+] NBT-NS already disabled on all adapters" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="NBT-NS"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region 7. Disable SMBv1
Write-Host "`n[7/7] Disabling SMBv1 (EternalBlue mitigation)..." -ForegroundColor Yellow
try {
    $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop
    
    if ($smbConfig.EnableSMB1Protocol -eq $true) {
        if (-not $WhatIf) {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
            # Also set via registry as backup
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        }
        $results += [PSCustomObject]@{Check="SMBv1"; Status="FIXED"; Notes="Disabled SMBv1 protocol"}
        Write-Host "  [+] SMBv1 disabled" -ForegroundColor Green
    } else {
        $results += [PSCustomObject]@{Check="SMBv1"; Status="OK"; Notes="Already disabled"}
        Write-Host "  [+] SMBv1 already disabled" -ForegroundColor Green
    }
} catch {
    $results += [PSCustomObject]@{Check="SMBv1"; Status="FAILED"; Notes=$_.Exception.Message}
    Write-Host "  [-] Error: $_" -ForegroundColor Red
}
#endregion

#region Display Current Audit Policy
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "CURRENT AUDIT POLICY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
auditpol /get /category:* | Select-String -Pattern "(Logon|Kerberos|Directory|Account|Process)" | ForEach-Object {
    Write-Host $_ -ForegroundColor Gray
}
#endregion

#region Summary
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PHASE 3 SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$fixed = ($results | Where-Object { $_.Status -eq "FIXED" }).Count
$ok = ($results | Where-Object { $_.Status -eq "OK" }).Count
$warnings = ($results | Where-Object { $_.Status -eq "WARNING" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAILED" }).Count

Write-Host "Fixed: $fixed | Already OK: $ok | Warnings: $warnings | Failed: $failed" -ForegroundColor $(if ($failed -gt 0) {'Red'} elseif ($warnings -gt 0) {'Yellow'} else {'Green'})

Write-Host "`n=== KEY EVENT IDS NOW BEING LOGGED ===" -ForegroundColor Cyan
Write-Host @"
  4624  - Logon events (watch Type 3 for PtH, Type 10 for RDP)
  4625  - Failed logons (password spray detection)
  4648  - Explicit credential use (lateral movement)
  4662  - Directory service access (DCSync detection)
  4663  - Object access (LSASS access for cred dump)
  4688  - Process creation with command line
  4768  - TGT request (AS-REP roasting)
  4769  - TGS request (Kerberoasting - watch for RC4)
  4771  - Kerberos pre-auth failed
  4104  - PowerShell script block
  5136  - AD object modification (RBCD detection)
"@ -ForegroundColor White

Write-Host "`n>> Next: Run Verify_Hardening.ps1 to confirm all changes" -ForegroundColor Cyan
#endregion

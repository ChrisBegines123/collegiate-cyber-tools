#####################################################
# RMCCDC - VERIFY ALL HARDENING MEASURES
# Run as Domain Admin on Domain Controller
# Run after completing Phases 1-3
#####################################################

Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║     RMCCDC AD HARDENING VERIFICATION                       ║
║     Confirm all security measures are in place            ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

$checks = @()

#region Print Spooler
$spooler = Get-Service Spooler -ErrorAction SilentlyContinue
$status = if ($spooler.Status -eq 'Stopped' -and $spooler.StartType -eq 'Disabled') { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "Print Spooler Disabled"
    Status = $status
    Current = "$($spooler.Status) / $($spooler.StartType)"
    Expected = "Stopped / Disabled"
}
Write-Host "Print Spooler: $status ($($spooler.Status))" -ForegroundColor $color
#endregion

#region MachineAccountQuota
$quota = (Get-ADObject (Get-ADDomain).DistinguishedName -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota'
$status = if ($quota -eq 0) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "MachineAccountQuota = 0"
    Status = $status
    Current = $quota
    Expected = "0"
}
Write-Host "MachineAccountQuota: $status ($quota)" -ForegroundColor $color
#endregion

#region LDAP Signing
$ldapSigning = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerIntegrity" -ErrorAction SilentlyContinue).LDAPServerIntegrity
$status = if ($ldapSigning -eq 2) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "LDAP Signing Required"
    Status = $status
    Current = $ldapSigning
    Expected = "2"
}
Write-Host "LDAP Signing: $status ($ldapSigning)" -ForegroundColor $color
#endregion

#region Password Policy
$pwdPolicy = Get-ADDefaultDomainPasswordPolicy
$status = if ($pwdPolicy.MinPasswordLength -ge 14) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "MinPasswordLength >= 14"
    Status = $status
    Current = $pwdPolicy.MinPasswordLength
    Expected = ">=14"
}
Write-Host "Min Password Length: $status ($($pwdPolicy.MinPasswordLength))" -ForegroundColor $color

$status = if ($pwdPolicy.LockoutThreshold -gt 0 -and $pwdPolicy.LockoutThreshold -le 5) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "LockoutThreshold 1-5"
    Status = $status
    Current = $pwdPolicy.LockoutThreshold
    Expected = "1-5"
}
Write-Host "Lockout Threshold: $status ($($pwdPolicy.LockoutThreshold))" -ForegroundColor $color
#endregion

#region DNS Zones
$unsecureZones = Get-DnsServerZone | Where-Object { $_.DynamicUpdate -eq "NonsecureAndSecure" -and $_.ZoneType -eq "Primary" }
$status = if ($unsecureZones.Count -eq 0) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "DNS Zones Secured"
    Status = $status
    Current = "$($unsecureZones.Count) unsecure"
    Expected = "0 unsecure"
}
Write-Host "DNS Zone Security: $status ($($unsecureZones.Count) unsecure zones)" -ForegroundColor $color
#endregion

#region Enterprise Admins Nesting
$eaGroups = Get-ADGroupMember "Enterprise Admins" | Where-Object { $_.objectClass -eq 'group' }
$status = if ($eaGroups.Count -eq 0) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "No Nested EA Groups"
    Status = $status
    Current = "$($eaGroups.Count) nested groups"
    Expected = "0 nested groups"
}
Write-Host "Enterprise Admin Nesting: $status ($($eaGroups.Count) nested groups)" -ForegroundColor $color
#endregion

#region Password Never Expires
$pwdNeverExpires = Get-ADUser -Filter {PasswordNeverExpires -eq $true -and Enabled -eq $true} | 
    Where-Object { $_.SamAccountName -notmatch "^(krbtgt|AZUREADSSOACC|DefaultAccount)$" }
$status = if ($pwdNeverExpires.Count -eq 0) { "[+] PASS" } else { "[!] WARN" }
$color = if ($status -match "PASS") { "Green" } elseif ($status -match "WARN") { "Yellow" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "No PasswordNeverExpires"
    Status = $status
    Current = "$($pwdNeverExpires.Count) accounts"
    Expected = "0 accounts"
}
Write-Host "PasswordNeverExpires: $status ($($pwdNeverExpires.Count) accounts)" -ForegroundColor $color
#endregion

#region LLMNR
$llmnr = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue).EnableMulticast
$status = if ($llmnr -eq 0) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "LLMNR Disabled"
    Status = $status
    Current = $llmnr
    Expected = "0"
}
Write-Host "LLMNR: $status ($llmnr)" -ForegroundColor $color
#endregion

#region Command Line Auditing
$cmdLine = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" -ErrorAction SilentlyContinue).ProcessCreationIncludeCmdLine_Enabled
$status = if ($cmdLine -eq 1) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "CmdLine Auditing"
    Status = $status
    Current = $cmdLine
    Expected = "1"
}
Write-Host "Command-Line Auditing: $status ($cmdLine)" -ForegroundColor $color
#endregion

#region PowerShell Logging
$psLogging = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue).EnableScriptBlockLogging
$status = if ($psLogging -eq 1) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "PowerShell ScriptBlock Logging"
    Status = $status
    Current = $psLogging
    Expected = "1"
}
Write-Host "PowerShell Logging: $status ($psLogging)" -ForegroundColor $color
#endregion

#region SMBv1
$smbv1 = (Get-SmbServerConfiguration -ErrorAction SilentlyContinue).EnableSMB1Protocol
$status = if ($smbv1 -eq $false) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "SMBv1 Disabled"
    Status = $status
    Current = $smbv1
    Expected = "False"
}
Write-Host "SMBv1: $status ($smbv1)" -ForegroundColor $color
#endregion

#region Zerologon
$zerologon = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "FullSecureChannelProtection" -ErrorAction SilentlyContinue).FullSecureChannelProtection
$status = if ($zerologon -eq 1) { "[+] PASS" } else { "[-] FAIL" }
$color = if ($status -match "PASS") { "Green" } else { "Red" }
$checks += [PSCustomObject]@{
    Check = "Zerologon Mitigated"
    Status = $status
    Current = $zerologon
    Expected = "1"
}
Write-Host "Zerologon (CVE-2020-1472): $status ($zerologon)" -ForegroundColor $color
#endregion

#region Summary
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

$checks | Format-Table Check, Status, Current, Expected -AutoSize

$passed = ($checks | Where-Object { $_.Status -match "PASS" }).Count
$failed = ($checks | Where-Object { $_.Status -match "FAIL" }).Count
$warned = ($checks | Where-Object { $_.Status -match "WARN" }).Count
$total = $checks.Count

$scoreColor = if ($failed -eq 0) { "Green" } elseif ($failed -le 2) { "Yellow" } else { "Red" }
Write-Host "`nScore: $passed/$total PASSED" -ForegroundColor $scoreColor

if ($failed -gt 0) {
    Write-Host "`n=== ITEMS NEEDING ATTENTION ===" -ForegroundColor Red
    $checks | Where-Object { $_.Status -match "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Check): Current=$($_.Current), Expected=$($_.Expected)" -ForegroundColor Red
    }
}

if ($warned -gt 0) {
    Write-Host "`n=== WARNINGS ===" -ForegroundColor Yellow
    $checks | Where-Object { $_.Status -match "WARN" } | ForEach-Object {
        Write-Host "  - $($_.Check): $($_.Current)" -ForegroundColor Yellow
    }
}
#endregion

#region Quick Privilege Audit
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PRIVILEGED ACCOUNT AUDIT" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`nDomain Admins:" -ForegroundColor White
Get-ADGroupMember "Domain Admins" | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }

Write-Host "`nEnterprise Admins:" -ForegroundColor White
Get-ADGroupMember "Enterprise Admins" | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }

Write-Host "`nSchema Admins:" -ForegroundColor White
Get-ADGroupMember "Schema Admins" | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
#endregion

Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Re-run Purple Knight and BloodHound to confirm improvements!" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

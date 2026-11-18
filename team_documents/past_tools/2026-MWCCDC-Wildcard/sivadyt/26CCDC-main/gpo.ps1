<# =====================================================================
Password Policy GPO Builder + Report Export
- Creates/updates a domain GPO with password/lockout/Kerberos settings
- Writes Security Template (GptTmpl.inf) into the GPO in SYSVOL
- Sets “no password hints” supporting settings (password reveal + local reset Qs)
- Exports an HTML GPO report for submission

Run on a DC or admin workstation with RSAT:
  - GroupPolicy module
  - ActiveDirectory module
===================================================================== #>

param(
  [string]$GpoName    = "ORG - Password & Lockout Policy",
  [string]$ReportPath = "C:\Temp\ORG-PasswordPolicy-GPOReport.html"
)

$ErrorActionPreference = "Stop"

Import-Module GroupPolicy
Import-Module ActiveDirectory

$domain = Get-ADDomain
$domainDns  = $domain.DNSRoot
$domainDn   = $domain.DistinguishedName
$sysvolRoot = "\\$domainDns\SYSVOL\$domainDns\Policies"

# --- Create or get the GPO ---
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
  $gpo = New-GPO -Name $GpoName -Comment "Domain password/lockout/Kerberos policy baseline"
}

# --- Link to the domain root (enforced baseline) ---
# Note: Linking at domain root is typical for Account Policies.
New-GPLink -Name $GpoName -Target $domainDn -LinkEnabled Yes -ErrorAction SilentlyContinue | Out-Null

# --- SYSVOL paths for this GPO ---
$gpoGuid = "{0}" -f $gpo.Id.Guid
$gpoPath = Join-Path $sysvolRoot $gpoGuid

$secEditDir = Join-Path $gpoPath "Machine\Microsoft\Windows NT\SecEdit"
$gptTmplInf = Join-Path $secEditDir "GptTmpl.inf"
$gptIni     = Join-Path $gpoPath "GPT.ini"

New-Item -Path $secEditDir -ItemType Directory -Force | Out-Null

# --- Build the security template (Account Policies + Kerberos) ---
# Values are in days/minutes as expected by security templates:
#   MinimumPasswordAge / MaximumPasswordAge: days
#   LockoutDuration / ResetLockoutCount: minutes
#   MaxClockSkew: minutes
$inf = @"
[Unicode]
Unicode=yes

[Version]
signature="`$CHICAGO`$"
Revision=1

[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 90
MinimumPasswordLength = 15
PasswordComplexity = 1
PasswordHistorySize = 3
ClearTextPassword = 0

LockoutBadCount = 5
ResetLockoutCount = 15
LockoutDuration = 15

[Kerberos Policy]
MaxClockSkew = 5
"@

Set-Content -Path $gptTmplInf -Value $inf -Encoding Unicode

# --- Supporting “No password hints” controls (local UX controls) ---
# Domain accounts don’t use “password hints” like local accounts do,
# but these settings help prevent hint/reveal style behavior on endpoints.
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
  -ValueName "DisablePasswordReveal" -Type DWord -Value 1

# Disable local password reset questions (Windows 10/11)
Set-GPRegistryValue -Name $GpoName `
  -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
  -ValueName "NoLocalPasswordResetQuestions" -Type DWord -Value 1

# --- Bump GPT.ini machine version so clients recognize the change ---
# Version is a 32-bit value: HighWord=User, LowWord=Machine
if (-not (Test-Path $gptIni)) {
  Set-Content -Path $gptIni -Value "[General]`r`nVersion=0`r`n" -Encoding ASCII
}

$iniText = Get-Content $gptIni -Raw
if ($iniText -match "Version=(\d+)") {
  $ver = [int]$Matches[1]
  $userVer    = ($ver -shr 16) -band 0xFFFF
  $machineVer = $ver -band 0xFFFF
  $machineVer++
  $newVer = ($userVer -shl 16) -bor ($machineVer -band 0xFFFF)
  $iniText = [regex]::Replace($iniText, "Version=\d+", "Version=$newVer")
  Set-Content -Path $gptIni -Value $iniText -Encoding ASCII
}

# --- Export GPO report (HTML) ---
$reportDir = Split-Path -Path $ReportPath -Parent
if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }

Get-GPOReport -Name $GpoName -ReportType Html -Path $ReportPath

Write-Host "DONE"
Write-Host "GPO Name:      $GpoName"
Write-Host "GPO GUID:      $gpoGuid"
Write-Host "GptTmpl.inf:   $gptTmplInf"
Write-Host "Report saved:  $ReportPath"
Write-Host ""
Write-Host "SCREENSHOTS to include (manual):"
Write-Host "1) Open Group Policy Management (gpmc.msc)"
Write-Host "2) Go to: Forest > Domains > $domainDns > Group Policy Objects > '$GpoName'"
Write-Host "3) Screenshot these nodes:"
Write-Host "   - Computer Config > Policies > Windows Settings > Security Settings > Account Policies > Password Policy"
Write-Host "   - ... > Account Lockout Policy"
Write-Host "   - ... > Kerberos Policy"
Write-Host "4) Also screenshot the GPO link at the domain root showing it is linked/enabled."

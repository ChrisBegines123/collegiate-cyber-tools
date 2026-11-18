#Requires -RunAsAdministrator
# CCDC26 - Post-Hardening Sanity Check
# Validates that 01-blitz.ps1 hardening was applied correctly.

$ErrorActionPreference = "Continue"

$pass = 0; $fail = 0; $warn = 0

function Check-Pass { param([string]$M) $script:pass++; Write-Host "  [PASS] $M" -ForegroundColor Green }
function Check-Fail { param([string]$M) $script:fail++; Write-Host "  [FAIL] $M" -ForegroundColor Red }
function Check-Warn { param([string]$M) $script:warn++; Write-Host "  [WARN] $M" -ForegroundColor Yellow }
function Section    { param([string]$M) Write-Host "`n=== $M ===" -ForegroundColor Cyan }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CCDC26 Hardening Sanity Check" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Time:     $(Get-Date)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ── SMBv1 ──
Section "SMB"
try {
    $smb1 = (Get-SmbServerConfiguration).EnableSMB1Protocol
    if ($smb1) { Check-Fail "SMBv1 is ENABLED" } else { Check-Pass "SMBv1 disabled" }
} catch { Check-Warn "Cannot query SMB config" }

try {
    $signing = (Get-SmbServerConfiguration).RequireSecuritySignature
    if ($signing) { Check-Pass "SMB signing required" } else { Check-Fail "SMB signing NOT required" }
} catch {}

# ── Print Spooler ──
Section "Print Spooler"
$spooler = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
if ($spooler -and $spooler.Status -eq "Running") { Check-Warn "Print Spooler is running (expected: Stopped/Manual)" }
elseif ($spooler) { Check-Pass "Print Spooler stopped (StartType: $($spooler.StartType))" }
else { Check-Pass "Print Spooler service not found" }

# ── Firewall ──
Section "Firewall"
$profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
foreach ($p in $profiles) {
    if ($p.Enabled) { Check-Pass "Firewall $($p.Name): enabled" } else { Check-Fail "Firewall $($p.Name): DISABLED" }
    if ($p.DefaultInboundAction -eq "Block") { Check-Pass "Firewall $($p.Name): default inbound = Block" }
    else { Check-Fail "Firewall $($p.Name): default inbound = $($p.DefaultInboundAction)" }
}

# ── LOLBin outbound rules ──
Section "LOLBin Blocking"
$lolbins = @("mshta","regsvr32","wscript","cscript","rundll32","certutil")
foreach ($bin in $lolbins) {
    $rule = Get-NetFirewallRule -DisplayName "CCDC-Block-Outbound-$bin" -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled -eq "True") { Check-Pass "LOLBin blocked: $bin" }
    else { Check-Fail "LOLBin NOT blocked: $bin" }
}

# ── LSASS Protection ──
Section "Credential Protection"
$runAsPPL = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue).RunAsPPL
if ($runAsPPL -eq 1) { Check-Pass "LSASS RunAsPPL enabled" } else { Check-Fail "LSASS RunAsPPL NOT set" }

$wdigest = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -ErrorAction SilentlyContinue).UseLogonCredential
if ($wdigest -eq 0) { Check-Pass "WDigest UseLogonCredential = 0" } else { Check-Fail "WDigest UseLogonCredential != 0" }

$noLM = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "NoLmHash" -ErrorAction SilentlyContinue).NoLmHash
if ($noLM -eq 1) { Check-Pass "LM hash storage disabled" } else { Check-Fail "LM hash storage NOT disabled" }

# ── UAC ──
Section "UAC"
$uac = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue).EnableLUA
if ($uac -eq 1) { Check-Pass "UAC enabled" } else { Check-Fail "UAC DISABLED" }

# ── PowerShell Logging ──
Section "PowerShell Logging"
$sbLog = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue).EnableScriptBlockLogging
if ($sbLog -eq 1) { Check-Pass "Script Block Logging enabled" } else { Check-Fail "Script Block Logging NOT enabled" }

$modLog = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" -ErrorAction SilentlyContinue).EnableModuleLogging
if ($modLog -eq 1) { Check-Pass "Module Logging enabled" } else { Check-Fail "Module Logging NOT enabled" }

$trans = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" -Name "EnableTranscripting" -ErrorAction SilentlyContinue).EnableTranscripting
if ($trans -eq 1) { Check-Pass "Transcription enabled" } else { Check-Fail "Transcription NOT enabled" }

# ── Command Line Auditing ──
Section "Auditing"
$cmdLine = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" -ErrorAction SilentlyContinue).ProcessCreationIncludeCmdLine_Enabled
if ($cmdLine -eq 1) { Check-Pass "Command line auditing enabled" } else { Check-Fail "Command line auditing NOT enabled" }

# ── ASR Rules ──
Section "Windows Defender ASR"
try {
    $asr = (Get-MpPreference -ErrorAction Stop).AttackSurfaceReductionRules_Ids
    if ($asr -and $asr.Count -ge 10) { Check-Pass "ASR rules active: $($asr.Count) rules" }
    elseif ($asr) { Check-Warn "Only $($asr.Count) ASR rules (expected 15)" }
    else { Check-Fail "No ASR rules configured" }
} catch { Check-Warn "Cannot query ASR rules (Defender may not support)" }

# ── Defender Real-Time ──
try {
    $rt = (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled
    if ($rt) { Check-Pass "Defender real-time protection ON" } else { Check-Fail "Defender real-time protection OFF" }
} catch { Check-Warn "Cannot query Defender status" }

# ── Anonymous Access ──
Section "Anonymous Access"
$restrictAnon = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -ErrorAction SilentlyContinue).RestrictAnonymous
if ($restrictAnon -ge 1) { Check-Pass "Anonymous access restricted" } else { Check-Fail "Anonymous access NOT restricted" }

# ── Summary ──
Write-Host ""
Write-Host "========================================" -ForegroundColor $(if($fail -gt 0){"Red"}else{"Green"})
Write-Host "  Results: $pass PASS / $fail FAIL / $warn WARN" -ForegroundColor $(if($fail -gt 0){"Red"}else{"Green"})
Write-Host "========================================" -ForegroundColor $(if($fail -gt 0){"Red"}else{"Green"})

if ($fail -gt 0) {
    Write-Host "`n  Re-run 01-blitz.ps1 to fix failures" -ForegroundColor Yellow
}

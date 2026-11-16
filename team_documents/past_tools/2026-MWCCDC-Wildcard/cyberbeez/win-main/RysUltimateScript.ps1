#Block Credential Stealing from Windows Local Security Authority Subsystem
Add-MpPreference -AttackSurfaceReductionRules_Ids 9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2 -AttackSurfaceReductionRules_Actions Enabled

#Block executable files from running if they dont meet criteria
Add-MpPreference -AttackSurfaceReductionRules_Ids 01443614-cd74-433a-b99e-2ecdc07bfc25 -AttackSurfaceReductionRules_Actions Enabled
##If this command blocks your scripts then type "powershell -noexit -ExecutionPolicy Bypass -File RysUltimateScript.ps1" this should allow you to run the script##

#Enable Network Protection
Set-MpPreference -EnableNetworkProtection Enabled 

#Disable SMB
Set-SmbServerConfiguration -EnableSMB1protocol $false

#Set RRL (DDOS Prevention)
Set-DnsServerResponseRateLimiting -WindowInSec 10 -LeakRate 2 -ResponsesPerSec 10

#Enable Defender exploit system-wide protection
Set-Processmitigation -System -Enable DEP,EmulateAtlThunks,BottomUp,HighEntropy,SEHOP,SEHOPTelemetry,TerminateOnError

#Blocks executation of obfuscated scripts
Add-MpPreference -AttackSurfaceReductionRules_Ids 5BEB7EFE-FD9A-4556-801D-275E5FFC04CC -AttackSurfaceReductionRules_Actions Enabled

#Blocks executable content from Email/Webmail
Add-MpPreference -AttackSurfaceReductionRules_Ids BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550 -AttackSurfaceReductionRules_Actions Enabled
#Stop/Disable certain services
Stop-Service -Name "Print Spooler"
Stop-Service -Name "Windows Mobile Hotspot Service"

# Reset Windows Firewall to Default
(New-Object -ComObject HNetCfg.FwPolicy2).RestoreLocalFirewallDefaults()

#Secure Execution Policy
Set-ExecutionPolicy Restricted



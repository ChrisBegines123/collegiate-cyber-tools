# Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

pause

#IMPORTANTSERVICEID                                         ImportantServiceName

#TlntSvr                                                    Telnet
#Msftpsvc, ftpsvc                                           FTP 
#snmptrap                                                   SNMP
#ssdpsrv                                                    SSDP Discovery
#termservice, sessionenv, Remoteaccess                      REMOTE DESKTOP, REMOTE ACCESS
#mnmsrvc                                                    NetMeeting Remoted Desktop Sharing
#remoteregistry                                             Remote Registry
#upnphos                                                    Universal Plug n Play
#WAS                                                        Web Server Service
#Smtpsvc                                                    SMTP

function WIN-disableServices() {

    Write-Warning "disableServices STARTING"
    Write-Host

    # Unnecessary Services
    Write-host "Terminating vulnerable services..."
    $disableService = get-service spooler, SessionEnv, TermService, UmRdpService, RemoteRegistry, iisadmin, 
    W3svc, SharedAccess, LanmanServer, SNMPTRAP, SSDPSRV, lmhosts, simptcp, TapiSrv, TlntSvr, 
    upnphos, UPnP, RemoteAccess, messenger, WebClient, msftpsvc, iprip, ftpsvc, WAS, mnmsrvc, 
    NetTcpPortSharing, RasMan, TabletInputService, RpcSs, SENS, EventSystem, XblAuthManager, 
    XblGameSave, XboxGipSvc, xboxgip, xbgm, SysMain, seclogon, p2pimsvc, fax, RasAuto, Smtpsvc, 
    Dfs, TrkWks, MSDTC, ERSvc, NtFrs, IsmServ, WmdmPmSN, helpsvc, RDSessMgr, RSoPProv, SCardSvr, 
    Sacsvr, uploadmgr, VDS, VSS, WINS, CscService, hidserv, IPBusEnum, PolicyAgent, SCPolicySvc, 
    Themes, upnphost, nfssvc, nfsclnt, MSSQLServerADHelper, Server, TeamViewer, TeamViewer7, 
    HomeGroupListener, HomeGroupProvider, AxInstSV, Netlogon, lltdsvc, iphlpsvc, AdobeARMservice
    stop-service -InputObject $disableService -force -verbose
    $disableService | Set-Service -StartupType Disabled
    $disableService

    Write-Host "disableServices DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-disableServices

function WIN-enableServices() {

    Write-Warning "enableServices STARTING"

    # Essential Services
    Write-host "Starting essential services..."
    $enableService = get-service wuauserv, EventLog, MpsSvc, WinDefend, WdNisSvc, Sense, Schedule, ScDeviceEnum, wscsvc
    $enableService | Set-Service -StartupType Automatic
    start-service -InputObject $enableService -verbose
    $enableService

    Write-Host "enableServices DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-enableServices

function WIN-firewall() {

    Write-Warning "firewall STARTING"
    Write-Host

    # Firewall Startup
    Write-host "Enabling Firewall and applying settings..."
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    Set-NetFirewallProfile -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True -AllowUnicastResponseToMulticast True -LogFileName %SystemRoot%\System32\LogFiles\Firewall\pfirewall.log
    
    Write-Host "firewall DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-firewall

function WIN-networkDefense() {

    Write-Warning "networkDefense STARTING"
    Write-Host

    # Network Profiles
    netsh advfirewall firewall set rule group="Network Discovery" new enable=No
    Set-NetConnectionProfile -NetworkCategory Public
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24" -Name "Category" -ErrorAction SilentlyContinue

    # Primary Port Checks
    Write-host "Port Checks"
    netstat -aon
    Write-host "Disabling vulnerable ports..."

    # Network Status
    netstat -ano | Out-File $Dir\netstat.txt

    # TCP Ports
    New-NetFirewallRule -DisplayName "TCP Port 21" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Block # FTP
    New-NetFirewallRule -DisplayName "TCP Port 22" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Block # SSH
    New-NetFirewallRule -DisplayName "TCP Port 23" -Direction Inbound -LocalPort 23 -Protocol TCP -Action Block # TELNET
    New-NetFirewallRule -DisplayName "TCP Port 25" -Direction Inbound -LocalPort 25 -Protocol TCP -Action Block # SMTP
    New-NetFirewallRule -DisplayName "TCP Port 80" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "TCP Port 110" -Direction Inbound -LocalPort 110 -Protocol TCP -Action Block # POP3
    New-NetFirewallRule -DisplayName "TCP Port 161" -Direction Inbound -LocalPort 161 -Protocol TCP -Action Block # SNMP
    New-NetFirewallRule -DisplayName "TCP Port 162" -Direction Inbound -LocalPort 162 -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "TCP Port 389" -Direction Inbound -LocalPort 389 -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "TCP Port 3389" -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Block # RDP
    New-NetFirewallRule -DisplayName "TCP Port 4444" -Direction Inbound -LocalPort 4444 -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "TCP Port 8080" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "TCP Port 8088" -Direction Inbound -LocalPort 8088 -Protocol TCP -Action Block
    New-NetFirewallRule -DisplayName "TCP Port 8888" -Direction Inbound -LocalPort 8888 -Protocol TCP -Action Block

    # UDP Ports
    New-NetFirewallRule -DisplayName "UDP Port 3389" -Direction Inbound -LocalPort 3389 -Protocol UDP -Action Block
    New-NetFirewallRule -DisplayName "UDP Port 161" -Direction Inbound -LocalPort 161 -Protocol UDP -Action Block
    New-NetFirewallRule -DisplayName "UDP Port 162" -Direction Inbound -LocalPort 162 -Protocol UDP -Action Block
    New-NetFirewallRule -DisplayName "UDP Port 389" -Direction Inbound -LocalPort 389 -Protocol UDP -Action Block
    New-NetFirewallRule -DisplayName "UDP Port 636" -Direction Inbound -LocalPort 636 -Protocol UDP -Action Block
    Write-host "Ports such as FTP, SSH, TelNet, SNMP, LDAP, and RDP Were Disabled."

    Write-Host "networkDefense DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-networkDefense

function WIN-powershellSettings() {

    Write-Warning "powershellSettings STARTING"
    Write-Host

    # Powershell Logging
    reg ADD HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription /v EnableTranscripting /t REG_DWORD /d 1 /f
    reg ADD HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" /v EnableModuleLogging /t REG_DWORD /d 1 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f

    Write-Host "powershellSettings DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-powershellSettings

function WIN-remoteDesktop () {

    Write-Warning "remoteDesktop STARTING"
    Write-host

    # Disable Remote Desktop
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "fDenyTSConnections" /t REG_DWORD /d 1 /f

    # Disable Remote Assistance
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "fAllowToGetHelp" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "fAllowUnsolicited" /t REG_DWORD /d 0 /f

    # Disable RDP Files
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows NT\Terminal Services" /v "AllowSignedFiles" /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows NT\Terminal Services" /v "AllowUnsignedFiles" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "AllowSignedFiles" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "AllowUnsignedFiles" /t REG_DWORD /d 0 /f

    # Disable password saving 
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows NT\Terminal Services" /v "DisablePasswordSaving" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "DisablePasswordSaving" /t REG_DWORD /d 1 /f
    
    # Disable RD Sharing
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Conferencing" /v "NoRDS" /t REG_DWORD /d 1 /f

    # Secure RDP
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "CreateEncryptedOnlyTickets" /t REG_DWORD /d 1 /f

    # Disable Remote Shell
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS" /v "AllowRemoteShellAccess" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile\RemoteAdminSettings" /v "Enabled" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile\Services\RemoteDesktop" /v "Enabled" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile\Services\UPnPFramework" /v "Enabled" /t REG_DWORD /d 0 /f

    # Terminal Server
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 1 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v AllowTSConnections /t REG_DWORD /d 0 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fAllowToGetHelp /t REG_DWORD /d 0 /f

    # Terminal Services

    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" /v "fEnableUsbBlockDeviceBySetupClass" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" /v "fEnableUsbNoAckIsochWriteToDevice" /t REG_DWORD /d 80 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" /v "fEnableUsbSelectDeviceByInterface" /t REG_DWORD /d 1 /f

    Write-Host "remoteDesktop DONE" -ForegroundColor blue -BackgroundColor green
    Write-host
    
}

WIN-remoteDesktop

function WIN-registryKeys() {

    Write-Warning "registryKeys STARTING"
    Write-host

    # Windows Automatically Updates
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v AutoInstallMinorUpdates /t REG_DWORD /d 1 /f
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v NoAutoUpdate /t REG_DWORD /d 0 /f
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v AUOptions /t REG_DWORD /d 4 /f
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v AUOptions /t REG_DWORD /d 4 /f
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate /v DisableWindowsUpdateAccess /t REG_DWORD /d 0 /f
    reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate /v ElevateNonAdmins /t REG_DWORD /d 0 /f
    reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer /v NoWindowsUpdate /t REG_DWORD /d 0 /f
    reg add "HKLM\SYSTEM\Internet Communication Management\Internet Communication" /v DisableWindowsUpdateAccess /t REG_DWORD /d 0 /f
    reg add HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate /v DisableWindowsUpdateAccess /t REG_DWORD /d 0 /f

    # Content Execution Blocking
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\access\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\excel\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\excel\security" /v "blockcontentexecutionfrominternet" /t REG_DWORD /d 1 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\excel\security" /v "excelbypassencryptedmacroscan" /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\ms project\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\ms project\security" /v "level" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\outlook\security" /v "level" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\powerpoint\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\powerpoint\security" /v "blockcontentexecutionfrominternet" /t REG_DWORD /d 1 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\publisher\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\visio\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\visio\security" /v "blockcontentexecutionfrominternet" /t REG_DWORD /d 1 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\word\security" /v "vbawarnings" /t REG_DWORD /d 4 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\word\security" /v "blockcontentexecutionfrominternet" /t REG_DWORD /d 1 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\16.0\word\security" /v "wordbypassencryptedmacroscan" /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\office\common\security" /v "automationsecurity" /t REG_DWORD /d 3 /f
    reg add "HKCU\Software\Policies\Microsoft\Office\16.0\outlook\options\mail" /v "blockextcontent" /t REG_DWORD /d 1 /f
    reg add "HKCU\Software\Policies\Microsoft\Office\16.0\outlook\options\mail" /v "junkmailenablelinks" /t REG_DWORD /d 0 /f

    # Restrict CDROM drive
    reg ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AllocateCDRoms /t REG_DWORD /d 1 /f

    # Disable remote access to floppy disk
    reg ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AllocateFloppies /t REG_DWORD /d 1 /f

    # Disable Auto Admin Login
    reg ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_DWORD /d 0 /f

    # Clear Page Files
    reg ADD "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 1 /f

    # Remove Printer Drivers
    reg ADD "HKLM\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers" /v AddPrinterDrivers /t REG_DWORD /d 1 /f

    # LSASS.exe
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" /v AuditLevel /t REG_DWORD /d 00000008 /f

    # LSA protection
    reg add HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v RunAsPPL /t REG_DWORD /d 00000001 /f

    # Disable WiFi Sense
    reg ADD HKLM\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting /v Value /t REG_DWORD /d 0 /f
    reg ADD HKLM\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots /v Value /t REG_DWORD /d 0 /f
    reg ADD HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config /v AutoConnectAllowedOEM /t REG_DWORD /d 0 /f
    reg ADD HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config /v WiFISenseAllowed /t REG_DWORD /d 0 /f

    # Limit use of blank passwords
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v LimitBlankPasswordUse /t REG_DWORD /d 1 /f

    # Auditing access of Global System Objects
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v auditbaseobjects /t REG_DWORD /d 1 /f

    # Auditing Backup and Restore
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v fullprivilegeauditing /t REG_DWORD /d 1 /f

    # Restrict Anonymous Enumeration
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v restrictanonymous /t REG_DWORD /d 1 /f
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v restrictanonymoussam /t REG_DWORD /d 1 /f

    # Disable storage of domain passwords
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v disabledomaincreds /t REG_DWORD /d 1 /f

    # Anonymous/Everone removed
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v everyoneincludesanonymous /t REG_DWORD /d 0 /f

    # Allow Machine ID for NTLM
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v UseMachineId /t REG_DWORD /d 0 /f

    # Do not display last user on logon
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v dontdisplaylastusername /t REG_DWORD /d 1 /f

    # Enable UAC
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v EnableLUA /t REG_DWORD /d 1 /f

    # UAC max security
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v PromptOnSecureDesktop /t REG_DWORD /d 1 /f

    # Enable Installer Detection
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v EnableInstallerDetection /t REG_DWORD /d 1 /f

    # Disable undocking without logon
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v undockwithoutlogon /t REG_DWORD /d 0 /f

    # Enable CTRL+ALT+DEL
    reg ADD HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v DisableCAD /t REG_DWORD /d 0 /f

    # Max password age
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters /v MaximumPasswordAge /t REG_DWORD /d 15 /f

    # Disable machine account password changes
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters /v DisablePasswordChange /t REG_DWORD /d 1 /f

    # Disable Password Reveal
    reg ADD 'HKLM\SOFTWARE\Policies\Microsoft\Internet Explorer\Main' /v DisablePasswordReveal /t REG_DWORD /d 1 /f
    reg ADD HKCU\Software\Policies\Microsoft\Windows\CredUI /v DisablePasswordReveal /t REG_DWORD /d 1 /f

    # Require strong session key
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters /v RequireStrongKey /t REG_DWORD /d 1 /f

    # Require Sign/Seal
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters /v RequireSignOrSeal /t REG_DWORD /d 1 /f

    # Sign Channel
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters /v SignSecureChannel /t REG_DWORD /d 1 /f

    # Seal Channel
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters /v SealSecureChannel /t REG_DWORD /d 1 /f

    # Set idle time to 45 minutes
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters /v autodisconnect /t REG_DWORD /d 45 /f

    # Require Security Signature
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters /v enablesecuritysignature /t REG_DWORD /d 0 /f

    # Enable Security Signature
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters /v requiresecuritysignature /t REG_DWORD /d 0 /f

    # Clear null session pipes
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters /v NullSessionPipes /t REG_MULTI_SZ /d "" /f

    # Restict Anonymous user access to named pipes and shares
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters /v NullSessionShares /t REG_MULTI_SZ /d "" /f

    # Encrypt SMB Passwords
    reg ADD HKLM\SYSTEM\CurrentControlSet\services\LanmanWorkstation\Parameters /v EnablePlainTextPassword /t REG_DWORD /d 0 /f

    # Clear remote registry paths
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\SecurePipeServers\winreg\AllowedExactPaths /v Machine /t REG_MULTI_SZ /d "" /f

    # Clear remote registry paths and sub-paths
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\SecurePipeServers\winreg\AllowedPaths /v Machine /t REG_MULTI_SZ /d "" /f

    # Secure Biometrics
    reg ADD HKLM\SOFTWARE\Policies\Microsoft\Biometrics\FacialFeatures /v EnhancedAntiSpoofing /t REG_DWORD /d 1 /f

    # IE Smart Screen
    reg ADD "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableSmartScreen /t REG_DWORD /d 1 /f
    reg ADD "HKCU\Software\Microsoft\Internet Explorer\PhishingFilter" /v EnabledV8 /t REG_DWORD /d 1 /f
    reg ADD "HKCU\Software\Microsoft\Internet Explorer\PhishingFilter" /v EnabledV9 /t REG_DWORD /d 1 /f
    reg ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" /v EnableWebContentEvaluation /t REG_DWORD /d 1 /f

    # Disable IE password caching
    reg ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v DisablePasswordCaching /t REG_DWORD /d 1 /f

    # Bad Certificate Warning
    reg ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v WarnonBadCertRecving /t REG_DWORD /d 1 /f

    # Warn users if website redirects
    reg ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v WarnOnPostRedirect /t REG_DWORD /d 1 /f

    # Enable Do Not Track
    reg ADD "HKCU\Software\Microsoft\Internet Explorer\Main" /v DoNotTrack /t REG_DWORD /d 1 /f
    reg ADD "HKCU\Software\Microsoft\Internet Explorer\Download" /v RunInvalidSignatures /t REG_DWORD /d 1 /f
    reg ADD "HKCU\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_LOCALMACHINE_LOCKDOWN\Settings" /v LOCALMACHINE_CD_UNLOCK /t REG_DWORD /d 1 /f
    reg ADD "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v WarnonZoneCrossing /t REG_DWORD /d 1 /f

    # Disable sticky keys
    reg ADD 'HKCU\Control Panel\Accessibility\StickyKeys' /v 'Flags' /t REG_SZ /d 506 /f
    reg ADD "HKU\.DEFAULT\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 506 /f

    # Show super hidden files
    reg ADD HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v ShowSuperHidden /t REG_DWORD /d 1 /f

    # Disable dump file creation
    reg ADD HKLM\SYSTEM\CurrentControlSet\Control\CrashControl /v CrashDumpEnabled /t REG_DWORD /d 0 /f

    # Disable autoruns
    reg ADD HKCU\SYSTEM\CurrentControlSet\Services\CDROM /v AutoRun /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoAutorun" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoDriveTypeAutoRun" /t REG_DWORD /d 255 /f

    # Disable Find My Device
    reg ADD "HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice" /v AllowFindMyDevice /t REG_DWORD /d 0 /f
    reg ADD "HKLM\SOFTWARE\Microsoft\Settings\FindMyDevice" /v LocationSyncEnabled /t REG_DWORD /d 0 /f

    # Enable internet explorer phishing filter
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\Internet Explorer\PhishingFilter" /v "EnabledV9" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Internet Explorer\PhishingFilter" /v "EnabledV9" /t REG_DWORD /d 1 /f

    Write-Host "registryKeys DONE" -ForegroundColor blue -BackgroundColor green
    Write-host
}

WIN-registryKeys

function WIN-windowsDefender() {

    Write-Warning "windowsDefender STARTING"
    Write-host

    # Enable Windows Defender
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiSpyware" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender" /v "ServiceKeepAlive" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableIOAVProtection" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableBehaviorMonitoring" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableRealtimeMonitoring" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" /v "CheckForSignaturesBeforeRunningScan" /t REG_DWORD /d 1 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" /v "DisableHeuristics" /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments" /v "ScanWithAntiVirus" /t REG_DWORD /d 3 /f

    # Privacy
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SpyNet" /v "LocalSettingOverrideSpynetReporting" /t REG_DWORD /d 0 /f
	
    # Disable Sample Submission
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SpyNet" /v "SpyNetReporting" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\SpyNet" /v "SubmitSamplesConsent" /t REG_DWORD /d 2 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting" /v "DisableGenericRePorts" /t REG_DWORD /d 1 /f

    # Configure Windows Defender
    setx /M MP_FORCE_USE_SANDBOX 1
    cmd.exe /c "%ProgramFiles%"\"Windows Defender"\MpCmdRun.exe -SignatureUpdate
    Set-MpPreference -PUAProtection enable
    Add-MpPreference -AttackSurfaceReductionRules_Ids e6db77e5-3df2-4cf1-b95a-636979351e5b -AttackSurfaceReductionRules_Actions Enabled
    Set-MpPreference -AttackSurfaceReductionRules_Ids D1E49AAC-8F56-4280-B9BA-993A6D -AttackSurfaceReductionRules_Actions Enabled
    Add-MpPreference -AttackSurfaceReductionRules_Ids C1DB55AB-C21A-4637-BB3F-A12568109D35 -AttackSurfaceReductionRules_Actions Enabled
    Add-MpPreference -AttackSurfaceReductionRules_Ids 9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2 -AttackSurfaceReductionRules_Actions Enabled
    
    Write-Host "windowsDefender DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-windowsDefender

function WIN-localAccounts() {

    Write-Warning "localAccounts STARTING"
    Write-Host

    # List local accounts to Desktop\users.txt
    New-Item C:\Users\$env:UserName\Desktop\users.txt
    $accounts = Get-Wmiobject Win32_UserAccount -filter 'LocalAccount=TRUE' | select-object -expandproperty Name
    $accounts | Out-File -FilePath C:\Users\$env:UserName\Desktop\users.txt
    
    Write-Host "localAccounts DONE" -ForegroundColor blue -BackgroundColor green
    Write-Host

}

WIN-localAccounts

function WIN-passwordManagement() {

    Write-Warning "passwordManagement STARTING"
    Write-Host

    # Set passwords for all accounts
    $Usernames = Get-WmiObject -class win32_useraccount -filter "LocalAccount='True'"
    foreach ($Username in $Usernames) {
        net user $Username.Name Cyb3rPatr1ot!@ /passwordreq:yes /logonpasswordchg:yes | out-null }
    wmic UserAccount set PasswordExpires=True | out-null
    wmic UserAccount set Lockout=False | out-null

    # Passwords BACKUP
    Write-Host "Password for all users changed to: Cyb3rPatr1ot!@"
    Get-WmiObject win32_useraccount | Foreach-object {
    ([adsi]("WinNT://"+$_.caption).replace("\","/")).SetPassword("Cyb3rPatr1ot!@")
    }
    
    Write-Host "passwordManagement DONE" -ForegroundColor blue -BackgroundColor green
    Write-Host

}

WIN-passwordManagement

function WIN-filescan() {

    Write-Warning "filescan STARTING"
    Write-Host

    # Show hidden files and file extensions 
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -name Hidden -value 1 | out-null
    Set-ItemProperty -path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -name HideFileExt -value 0 | out-null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -name ShowSuperHidden -value 1 | out-null
    Stop-Process -ProcessName Explorer | out-null

    # File Scan
    Write-Host "Starting File Scan..."
    Get-ChildItem -Path C:\Users -Include *.jpg,*.png,*.jpeg,*.avi,*.mp4,*.mp3,*.mp2,*.wav,*.gif,*.aac,*.ac3,*.aiff,*.bat,*.bmp,*.exe,*.flac,*.mov,
    *.m3u,*.m4a,*.m4p,*.mpeg4,*.midi,*.msi,*.ogg,*.txt,*.sh,*.wma,*.vqf -Exclude *.dll,*.doc,*.docx,  -File -Recurse -force -ErrorAction SilentlyContinue | Out-File -filepath C:\UnwantedFiles.txt
    Write-Host "File with all unwanted files stored in C:\UnwantedFiles.txt"

    # Directory Scan
    Write-Host "Starting Directory Scan..."
    $searchinfolder = 'C:\Program Files (x86)*', 'C:\Program Files*', 'C:\Users*'
    Get-ChildItem -Path $searchinfolder -Filter '*Cain*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt
    Get-ChildItem -Path $searchinfolder -Filter '*nmap*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*keylogger*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*Key logger*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*Armitage*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*Wireshark*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*Metasploit*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*TIGHTVNC*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*CODEC*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*netcat*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*backdoor*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*debugger*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*virus*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Get-ChildItem -Path $searchinfolder -Filter '*Shellter*.*' -Recurse | Out-File -FilePath C:\malwarelog.txt -Append
    Write-Host "Results stored in C:\malwarelog.txt"

    # Disable offline files
    Set-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\CSC" -name Start -value 4 | out-null

    # Flush DNS
    ipconfig /flushdns

    # Hosts File
    Copy-Item "C:\WINDOWS\system32\drivers\etc\hosts" -Destination "C:\"
    attrib -r -s C:\WINDOWS\system32\drivers\etc\hosts
    echo "# Hosts File Reset"> C:\Windows\System32\drivers\etc\hosts
    
    Write-Host "filescan DONE" -ForegroundColor blue -BackgroundColor green
    Write-Host

}

WIN-filescan

function WIN-miscellaneous {

    Write-Warning "miscellaneous STARTING"
    Write-host
        
    # Enable Internet Explorer ESC
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 1
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 1
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) enabled."

    # Enable Structured Exception Handling Overwrite Protection
    Set-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -name DisableExceptionChainValidation -value 0 | out-null
    Set-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -name LocalAccountTokenFilterPolicy -value 0 | out-null

    # Disable Autoplay
    $TestPath = Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if($TestPath -match 'False'){
    New-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies" -Name Explorer | out-null }
    New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -name NoDriveTypeAutoRun -value 0xff -ErrorAction SilentlyContinue | out-null
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -name NoDriveTypeAutoRun -value 0xff | out-null
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -name DisableAutoplay -value 1 -ErrorAction SilentlyContinue | out-null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -name DisableAutoplay -value 1 | out-null

    # Disable ipv6
    New-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Services\tcpip6\Parameters" -name DisabledComponents -value 0xff | out-null

    # Require a password on wakeup
    powercfg -SETACVALUEINDEX SCHEME_BALANCED SUB_NONE CONSOLELOCK 1 | out-null
    powercfg -SETDCVALUEINDEX SCHEME_MIN SUB_NONE CONSOLELOCK 1 | out-null
    powercfg -SETDCVALUEINDEX SCHEME_MAX SUB_NONE CONSOLELOCK 1 | out-null

    # Disable optional features
    Get-WindowsFeature Windows-Server-Backup
    Install-WindowsFeature -Name Windows-Server-Backup
    
    Write-Host "miscellaneous DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

    }

WIN-miscellaneous

function WIN-userAction() {

    Write-Warning "userAction STARTING"
    Write-host

    # Control Panel Settings
    Write-host "Check Checklist for tasks to be done here"
    control inetcpl.cpl
    control firewall.cpl

    # Check for updates
    Write-host "Begin updates"
    control /name Microsoft.WindowsUpdate

    # Manage Users
    Write-host "Modify Users"
    Start-Process C:\Windows\System32\lusrmgr.msc

    Write-Host "userAction DONE" -ForegroundColor blue -BackgroundColor green
    Write-host

}

WIN-userAction

pause

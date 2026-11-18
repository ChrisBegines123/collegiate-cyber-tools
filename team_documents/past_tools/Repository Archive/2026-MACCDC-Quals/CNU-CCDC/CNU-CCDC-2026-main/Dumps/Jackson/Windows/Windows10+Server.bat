REM Things to Remember
REM Search for "Active Directory" to manage domain users and groups.
REM Edit group policy in gpmc.msc as that has the default domain.

@echo off
setlocal EnableDelayedExpansion
net session 
if %ERRORLEVEL% neq 0 (
	echo Run as admin!
	echo Please exit the program.
	pause
	exit
)

set passwd=SigmaHolo23!

echo Exit the program if you have not completed the forensic questions.
echo.
pause

:main
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "|   _______    ______     ______     _        __     ______                 __      __     ________     __             ________   |"
echo "|  /       \  /      |   /      \   / \      /  |   /      \               /  |    /  |   /        \   /  |           /        \  |"
echo "| /$$$$$$  |  $$$$$$/   /$$$$$$_/   $$ \     $$ |  /$$$$$$  |              $$ |    $$ |  /$$$$$$$$  |  $$ |          /$$$$$$$$  | |"
echo "| $$ \__$$/     $$ |    $$ | ____   $$$ \   $$$ |  $$ |__$$ |    ______    $$ |    $$ |  $$  |  $$  |  $$ |          $$  |  $$  | |"
echo "| $$\    \      $$ |    $$ |/    |  $$$$ \ $$$$ |  $$    $$ |   |______|   $$ |    $$ |  $$  |  $$  |  $$ |          $$  |  $$  | |"
echo "|  $$$$$$ \     $$ |    $$ |$$$$ |  $$ $$ $$ $$ |  $$$$$$$$ |              $$$$$$$$$$ |  $$  |  $$  |  $$ |          $$  |  $$  | |"
echo "| / \___$$ |   _$$ |_   $$ \__$$ |  $$ |$$$ /$$ |  $$ |  $$ |              $$ |    $$ |  $$  |  $$  |  $$ |_______   $$  |  $$  | |"
echo "| $$    $$/   / $$   |  $$    $$/   $$ | $_/ $$ |  $$ |  $$ |              $$ |    $$ |  $$  \  $$  |  $$         |  $$  \  $$  | |"
echo "|  $$$$$$/    $$$$$$/    $$$$$$/    $$/      $$/   $$/   $$/               $$/     $$/    $$$$$$$$_/   $$$$$$$$$$/    $$$$$$$$_/  |"
echo "|            __           ___     ______     ___       __    _______       _______      __           ___      _______             |"
echo "|           /  \         /   |   /      |   /   \     /  |  /       \     /       \    /  \         /   |    /       \            |"
echo "|           $$$ |        $$$ |   $$$$$$/    $$$$ \    $$ |  $$$$$$$  \   /$$$$$$$$ \   $$$ |        $$$ |   /$$$$$$  |            |"
echo "|           $$$ |        $$$ |     $$ |     $$ $$ \   $$ |  $$    $$$ \  $$ |    $$ |  $$$ |        $$$ |   $$ \__$$/             |"
echo "|           $$$ |    _   $$$ |     $$ |     $$ |$$ \  $$ |  $$     $$ |  $$ |    $$ |  $$$ |    _   $$$ |   $$\    \              |"
echo "|           $$$ |   $ \  $$$ |     $$ |     $$ | $$ \ $$ |  $$     $$ |  $$ |    $$ |  $$$ |   $ \  $$$ |    $$$$$$ \             |"
echo "|           $$$ |  $$$ \ $$$ |    _$$ |_    $$ |  $$ \$$ |  $$     $$ |  $$ |    $$ |  $$$ |  $$$ \ $$$ |   / \___$$ |            |"
echo "|            $$$ $$$ $$$ $$ /    / $$   |   $$ |   $$ $$ |  $$    $$$ /  $$ \    $$ |   $$$ $$$ $$$ $$ /    $$    $$/             |"
echo "|              $$$_/   $$$_/     $$$$$$/    $$/     $$$$/   $$$$$$$__/    $$$$$$$$_/     $$$_/    $$$_/      $$$$$$/              |"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Written by: Jackson Campbell ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "|    1) Do some automatic stuff^! (WARNING: Really long runtime.)                                                                  |"
echo "|    2) Checklist^!                                                                                                                |"
echo "|    3) Exit Program                                                                                                              |"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

set /p "answer=What do you want to do: "
if "%answer%"=="1" goto Auto
if "%answer%"=="2" goto Checklist
if "%answer%"=="3" exit

echo Error -- Invalid input.  Please enter a number 1-2.
pause
cls
goto main

REM ----------------------------------------------------------------------------------------------

:Auto
cls
echo Doing Autonomous Stuff

echo Checking PC health
dism /online /cleanup-image /checkhealth
echo Scanning PC health
dism /online /cleanup-image /scanhealth
echo Restoring PC health
dism /online /cleanup-image /restorehealth 

echo Making Windows Defender scan exes
powershell "Add-MpPreference -ExclusionExtension '.exe'"

echo Adding users
:AddUsers
set /p "user=Enter the name of a user to add.  Type '0' to move on. "
if "%user%"=="0" goto EndOfAddUsers
net user %user% %passwd% /add
goto AddUsers

:EndOfAddUsers
echo Users added

echo Deleting users
:DelUsers
set /p "user=Enter the name of a user to delete.  Type '0' to move on. "
if "%user%"=="0" goto EndOfDelUsers
net user %user% %passwd% /delete
goto DelUsers

:EndOfDelUsers
echo Users deleted

echo Adding groups
:AddGroups
set /p "group=Enter the name of a group to add.  Type '0' to move on. "
if "%group%"=="0" goto EndOfAddGroups 
net localgroup /add %group%
goto AddGroups

:EndOfAddGroups
echo Groups added

echo Deleting groups
:DelGroups
set /p "group=Enter the name of a group to delete.  Type '0' to move on. "
if "%group%"=="0" goto EndOfDelGroups
net localgroup /delete %group%
goto DelGroups

:EndOfDelGroups
echo Groups deleted

echo Managing group members
echo Please note that this command has three lines that are not groups and should be skipped.  These are the first, second, and last lines.
echo They look like this:
echo 1. "Aliases for HOSTNAME"
echo 2. "-------------------------------------------------------------"
echo 3. "The command completed successfully."
for /f "tokens=1 delims=*" %%g in ('net localgroup') do (
	REM Allowing the user to skip modification of a group.
	set /p "skip=Enter '0' to skip modifying group %%g"
	if "%skip%"=="0" goto DontModifyGroup

	REM Printing the members of the group for the user to better manage them.
	echo Users of %%g
	net localgroup %%g

	:AddUserToGroup
	set /p "user=Enter the name of a user to add to group %%g.  Type '0' to move on. "
	if "%user%"=="0" goto EndOfAddUserToGroup
	net localgroup %%g /add %user%
	goto AddUserToGroup

	:EndOfAddUserToGroup

	REM Printing the members of the group for the user to better manage them.
	echo Users of %%g
	net localgroup %%g

	:DelUserFromGroup
	set /p "user=Enter the name of a user to delete from group %%g.  Type '0' to move on. "
	if "%user%"=="0" goto EndOfDelUserFromGroup
	net localgroup %%g /delete %user%
	goto DelUserFromGroup

	:EndOfDelUserFromGroup

	:DontModifyGroup
)

echo Configuring System users
net user Administrator /active:no 
net user Guest /active:no
wmic useraccount where name='Guest' rename NotAGuest
wmic useraccount where name='Administrator' rename NotAnAdmin
echo System users configured
endlocal

setlocal EnableExtensions
echo Managing users
for /f "tokens=2* delims==" %%u in ('powershell "glu | select -ExpandProperty Name"') do (
	REM Skips over the output if it is one of these strings.
	net user "%%u" "%passwd%"
	wmic useraccount where "Name='%%~u'" set PasswordExpires=TRUE
	wmic useraccount where "Name='%%~u'" set PasswordRequired=TRUE
	wmic useraccount where "Name='%%~u'" set PasswordChangeable=TRUE
)
endlocal

setlocal EnableDelayedExpansion	

echo Cleaning out the DNS cache...
ipconfig /flushdns 

echo Clearing the hosts file...
attrib -r -s C:\Windows\System32\drivers\etc\hosts
echo "" > C:\Windows\System32\drivers\etc\hosts
attrib +r +s C:\Windows\System32\drivers\etc\hosts
if %ERRORLEVEL%==1 echo There was an error in overwriting

echo Showing you the services...
net start
echo Now writing services to a file and searching for vulnerable services...
net start > servicesstarted.txt
echo These are only some common services, so this might not get everything.
echo Setting audit policies
auditpol /set /category:* /success:enable 
auditpol /set /category:* /failure:enable 

echo Removing all saved credentials
for /f "tokens=2 delims= " %%l in ('cmdkey /list') do cmdkey.exe /delete:%%l

echo Configuring Windows Firewall

netsh advfirewall set allprofiles state on 
netsh advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound 
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=no 
netsh advfirewall firewall set rule group="remote desktop" new enable=no 

netsh advfirewall firewall add rule name="Block135tout" protocol=TCP dir=out remoteport=135 action=block
netsh advfirewall firewall add rule name="Block135uout" protocol=UDP dir=out remoteport=135 action=block
netsh advfirewall firewall add rule name="Block135tin" protocol=TCP dir=in localport=135 action=block
netsh advfirewall firewall add rule name="Block135uin" protocol=UDP dir=in localport=135 action=block

netsh advfirewall firewall add rule name="Block137tout" protocol=TCP dir=out remoteport=137 action=block
netsh advfirewall firewall add rule name="Block137uout" protocol=UDP dir=out remoteport=137 action=block
netsh advfirewall firewall add rule name="Block137tin" protocol=TCP dir=in localport=137 action=block
netsh advfirewall firewall add rule name="Block137uin" protocol=UDP dir=in localport=137 action=block

netsh advfirewall firewall add rule name="Block138tout" protocol=TCP dir=out remoteport=138 action=block
netsh advfirewall firewall add rule name="Block138uout" protocol=UDP dir=out remoteport=138 action=block
netsh advfirewall firewall add rule name="Block138tin" protocol=TCP dir=in localport=138 action=block
netsh advfirewall firewall add rule name="Block138uin" protocol=UDP dir=in localport=138 action=block

netsh advfirewall firewall add rule name="Block139tout" protocol=TCP dir=out remoteport=139 action=block
netsh advfirewall firewall add rule name="Block139uout" protocol=UDP dir=out remoteport=139 action=block
netsh advfirewall firewall add rule name="Block139tin" protocol=TCP dir=in localport=139 action=block
netsh advfirewall firewall add rule name="Block139uin" protocol=UDP dir=in localport=139 action=block

netsh advfirewall firewall set rule name="netcat" new enable=no 
netsh advfirewall firewall set rule name="Remote Assistance (DCOM-In)" new enable=no 
netsh advfirewall firewall set rule name="Remote Assistance (PNRP-In)" new enable=no 
netsh advfirewall firewall set rule name="Remote Assistance (RA Server TCP-In)" new enable=no 
netsh advfirewall firewall set rule name="Remote Assistance (SSDP TCP-In)" new enable=no 
netsh advfirewall firewall set rule name="Remote Assistance (SSDP UDP-In)" new enable=no 
netsh advfirewall firewall set rule name="Remote Assistance (TCP-In)" new enable=no 
netsh advfirewall firewall set rule name="Telnet Server" new enable=no 

echo Disabling IPv6
netsh interface IPV6 set global randomizeidentifier=disabled
netsh interface IPV6 set privacy state=disable
netsh interface ipv6 6to4 set state state=disabled
netsh interface ipv6 isatap set state state=disabled
netsh interface ipv6 set teredo disable

echo Failsafe
if %ERRORLEVEL%==1 netsh advfirewall firewall set service type=remotedesktop mode=disable 

echo Disabling weak/old services
dism /online /disable-feature /featurename:IIS-WebServerRole /NoRestart
dism /online /disable-feature /featurename:IIS-WebServer /NoRestart
dism /online /disable-feature /featurename:IIS-CommonHttpFeatures /NoRestart
dism /online /disable-feature /featurename:IIS-HttpErrors /NoRestart
dism /online /disable-feature /featurename:IIS-HttpRedirect /NoRestart
dism /online /disable-feature /featurename:IIS-ApplicationDevelopment /NoRestart
dism /online /disable-feature /featurename:IIS-NetFxExtensibility /NoRestart
dism /online /disable-feature /featurename:IIS-NetFxExtensibility45 /NoRestart
dism /online /disable-feature /featurename:IIS-HealthAndDiagnostics /NoRestart
dism /online /disable-feature /featurename:IIS-HttpLogging /NoRestart
dism /online /disable-feature /featurename:IIS-LoggingLibraries /NoRestart
dism /online /disable-feature /featurename:IIS-RequestMonitor /NoRestart
dism /online /disable-feature /featurename:IIS-HttpTracing /NoRestart
dism /online /disable-feature /featurename:IIS-Security /NoRestart
dism /online /disable-feature /featurename:IIS-URLAuthorization /NoRestart
dism /online /disable-feature /featurename:IIS-RequestFiltering /NoRestart
dism /online /disable-feature /featurename:IIS-IPSecurity /NoRestart
dism /online /disable-feature /featurename:IIS-Performance /NoRestart
dism /online /disable-feature /featurename:IIS-HttpCompressionDynamic /NoRestart
dism /online /disable-feature /featurename:IIS-WebServerManagementTools /NoRestart
dism /online /disable-feature /featurename:IIS-ManagementScriptingTools /NoRestart
dism /online /disable-feature /featurename:IIS-IIS6ManagementCompatibility /NoRestart
dism /online /disable-feature /featurename:IIS-Metabase /NoRestart
dism /online /disable-feature /featurename:IIS-HostableWebCore /NoRestart
dism /online /disable-feature /featurename:IIS-StaticContent /NoRestart
dism /online /disable-feature /featurename:IIS-DefaultDocument /NoRestart
dism /online /disable-feature /featurename:IIS-DirectoryBrowsing /NoRestart
dism /online /disable-feature /featurename:IIS-WebDAV /NoRestart
dism /online /disable-feature /featurename:IIS-WebSockets /NoRestart
dism /online /disable-feature /featurename:IIS-ApplicationInit /NoRestart
dism /online /disable-feature /featurename:IIS-ASPNET /NoRestart
dism /online /disable-feature /featurename:IIS-ASPNET45 /NoRestart
dism /online /disable-feature /featurename:IIS-ASP /NoRestart
dism /online /disable-feature /featurename:IIS-CGI /NoRestart
dism /online /disable-feature /featurename:IIS-ISAPIExtensions /NoRestart
dism /online /disable-feature /featurename:IIS-ISAPIFilter /NoRestart
dism /online /disable-feature /featurename:IIS-ServerSideIncludes /NoRestart
dism /online /disable-feature /featurename:IIS-CustomLogging /NoRestart
dism /online /disable-feature /featurename:IIS-BasicAuthentication /NoRestart
dism /online /disable-feature /featurename:IIS-HttpCompressionStatic /NoRestart
dism /online /disable-feature /featurename:IIS-ManagementConsole /NoRestart
dism /online /disable-feature /featurename:IIS-ManagementService /NoRestart
dism /online /disable-feature /featurename:IIS-WMICompatibility /NoRestart
dism /online /disable-feature /featurename:IIS-LegacyScripts /NoRestart
dism /online /disable-feature /featurename:IIS-LegacySnapIn /NoRestart
dism /online /disable-feature /featurename:IIS-FTPServer /NoRestart
dism /online /disable-feature /featurename:IIS-FTPSvc /NoRestart
dism /online /disable-feature /featurename:IIS-FTPExtensibility /NoRestart
dism /online /disable-feature /featurename:SMB1Protocol /NoRestart
dism /online /disable-feature /featurename:SMB1Protocol-Client /NoRestart
dism /online /disable-feature /featurename:SMB1Protocol-Server /NoRestart
dism /online /disable-feature /featurename:SMB1Protocol-Deprecation /NoRestart
dism /online /disable-feature /featurename:TFTP /NoRestart
dism /online /disable-feature /featurename:TelnetClient /NoRestart
dism /online /disable-feature /featurename:TelnetServer /NoRestart


echo Configures UAC
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorUser" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableVirtualization" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableLUA" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "FilterAdministratorToken" /t REG_DWORD /d "1" /f 
reg ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "PromptOnSecureDesktop" /t REG_DWORD /d "1" /f 


echo Configuring Remote Services
reg add "HKLM\SYSTEM\ControlSet001\Control\Remote Assistance" /v "CreateEncryptedOnlyTickets" /t REG_DWORD /d "1" /f 
reg add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v "fDisableEncryption" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\ControlSet001\Control\Remote Assistance" /v "fAllowFullControl" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\ControlSet001\Control\Remote Assistance" /v "fAllowToGetHelp" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v "AllowRemoteRPC" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v "AllowTSConnections" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v "fAllowToGetHelp" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v "fDenyTSConnections" /t REG_DWORD /d "1" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v "UserAuthentication" /t REG_DWORD /d "0" /f 

echo Enabling automatic updates
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v "AUOptions" /t REG_DWORD /d "3" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AutoInstallMinorUpdates" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /t REG_DWORD /d "4" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "DisableWindowsUpdateAccess" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "ElevateNonAdmins" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoWindowsUpdate" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\Internet Communication Management\Internet Communication" /v "DisableWindowsUpdateAccess" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate" /v "DisableWindowsUpdateAccess" /t REG_DWORD /d "0" /f 

echo Enabling Do Not Track
reg add "HKLM\SOFTWARE\Microsoft\Internet Explorer\Download" /v "RunInvalidSignatures" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Internet Explorer\Main" /v "DoNotTrack" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_LOCALMACHINE_LOCKDOWN\Settings" /v "LOCALMACHINE_CD_UNLOCK" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings" /v "DisablePasswordCaching" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings" /v "WarnOnBadCertRecving" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings" /v "WarnOnPostRedirect" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings" /v "WarnOnZoneCrossing" /t REG_DWORD /d "1" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v "CrashDumpEnabled" /t REG_DWORD /d "0" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Services\CDROM" /v "AutoRun" /t REG_DWORD /d "1" /f 

echo Disabling Autorun
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer" /v "NoDriveTypeAutorun" /t REG_DWORD /d "255" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer" /v "NoAutorun" /t REG_DWORD /d "1" /f 

echo Misc Stuff (IDK what it does.)
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\Current Version\Winlogon" /v "CachedLogonsCount" /t REG_SZ /d "0" /f 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "DisableExceptionChainValidation" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowSignInOptions" /v "value" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DownloadMode" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DODownloadMode" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" /v "AutoConnectAllowedOEM" /t REG_DWORD /d "0" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v "DisableFileSyncNGSC" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v "DisableFileSync" /t REG_DWORD /d "1" /f 

echo Disabling Location
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableWindowsLocationProvider" /t REG_DWORD /d "1" /f 
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d "1" /f 

echo Configuring Windows Update
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v "ElevateNonAdmins" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v "IncludeRecommendedUpdates" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v "ScheduledInstallTime" /t REG_DWORD /d "22" /f

echo Restricting CD ROM drive
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AllocateCDRoms" /t REG_DWORD /d "1" /f 
echo Disabling automatic Admin logon
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon" /t REG_DWORD /d "0" /f 
echo Editing logo message text
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "LegalNoticeText" /t REG_SZ /d "" /f 
echo Editing logon message title bar
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "LegalNoticeCaption" /t REG_SZ /d "" /f 
echo Wiping page file from shutdown
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "ClearPageFileAtShutdown" /t REG_DWORD /d "1" /f 
echo Disallowing remote access to floppie disks
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AllocateFloppies" /t REG_DWORD /d "1" /f 
echo Preventing print driver installs 
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers" /v "AddPrinterDrivers" /t REG_DWORD /d "1" /f 
echo Limiting local account use of blank passwords to console
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "LimitBlankPasswordUse" /t REG_DWORD /d "1" /f 
echo Auditing access of Global System Objects
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "auditbaseobjects" /t REG_DWORD /d "1" /f 
echo Auditing Backup and Restore
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "fullprivilegeauditing" /t REG_DWORD /d "1" /f 
echo Do not display last user on logon
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "dontdisplaylastusername" /t REG_DWORD /d "1" /f 
echo Disabling undock without logon
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "undockwithoutlogon" /t REG_DWORD /d "0" /f 
echo Setting Maximum Machine Password Age
reg add "HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters" /v "MaximumPasswordAge" /t REG_DWORD /d "15" /f 
echo Disabling machine account password changes
reg add "HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters" /v "DisablePasswordChange" /t REG_DWORD /d "1" /f 
echo Requiring Strong Session Key
reg add "HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters" /v "RequireStrongKey" /t REG_DWORD /d "1" /f 
echo Requiring Sign/Seal
reg add "HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters" /v "RequireSignOrSeal" /t REG_DWORD /d "1" /f 
echo Requiring Sign Channel
reg add "HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters" /v "SignSecureChannel" /t REG_DWORD /d "1" /f 
echo Requiring Seal Channel
reg add "HKLM\SYSTEM\CurrentControlSet\services\Netlogon\Parameters" /v "SealSecureChannel" /t REG_DWORD /d "1" /f 
echo Disabling CTRL+ALT+DEL (It's weird)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "DisableCAD" /t REG_DWORD /d "1" /f 
echo Restricting Anonymous Enumeration #1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "restrictanonymous" /t REG_DWORD /d "1" /f 
echo Restricting Anonymous Enumeration #2
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "restrictanonymoussam" /t REG_DWORD /d "1" /f 
echo Setting Idle Time Limit - 45 mins
reg add "HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters" /v "autodisconnect" /t REG_DWORD /d "45" /f 
echo Requiring Security Signature - Disabled pursuant to checklist
reg add "HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters" /v "enablesecuritysignature" /t REG_DWORD /d "0" /f 
echo Enabling Security Signature - Disabled pursuant to checklist
reg add "HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters" /v "requiresecuritysignature" /t REG_DWORD /d "0" /f 
echo Disabling Domain Credential Storage
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "disabledomaincreds" /t REG_DWORD /d "1" /f 
echo Not giving Anons Everyone Permissions
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "everyoneincludesanonymous" /t REG_DWORD /d "0" /f 
echo Encryping SMB Passwords
reg add "HKLM\SYSTEM\CurrentControlSet\services\LanmanWorkstation\Parameters" /v "EnablePlainTextPassword" /t REG_DWORD /d "0" /f 
echo Clearing Null Session Pipes
reg add "HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters" /v "NullSessionPipes" /t REG_MULTI_SZ /d "" /f 
echo Clearing remotely accessible registry paths
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurePipeServers\winreg\AllowedExactPaths" /v "Machine" /t REG_MULTI_SZ /d "" /f 
echo Clearing remotely accessible registry paths and sub-paths
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurePipeServers\winreg\AllowedPaths" /v "Machine" /t REG_MULTI_SZ /d "" /f 
echo Resticting anonymous access to named pipes and shares
reg add "HKLM\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters" /v "NullSessionShares" /t REG_MULTI_SZ /d "" /f 
echo Allowing use of Machine ID for NTLM
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "UseMachineId" /t REG_DWORD /d "0" /f 
echo Adding auditing to Lsass.exe
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" /v "AuditLevel" /t REG_DWORD /d "00000008" /f 
echo Enabling LSA protection
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "RunAsPPL" /t REG_DWORD /d "00000001" /f 
echo Enabling smart screen for IE8
reg add "HKLM\SOFTWARE\Microsoft\Internet Explorer\PhishingFilter" /v "EnabledV8" /t REG_DWORD /d "1" /f 
echo Enabling smart screen for IE9 and up
reg add "HKLM\SOFTWARE\Microsoft\Internet Explorer\PhishingFilter" /v "EnabledV9" /t REG_DWORD /d "1" /f 
echo Showing hidden files
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Hidden" /t REG_DWORD /d "1" /f 
echo Showing file extensions
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d "0" /f 
echo Showing super hidden files
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSuperHidden" /t REG_DWORD /d "1" /f 
echo Disabling sticky keys
reg add "HKU\.DEFAULT\Control Panel\Accessibility\StickyKeys" /v "Flags" /t REG_SZ /d "506" /f 
echo Enable Installer Detection
reg ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableInstallerDetection" /t REG_DWORD /d "1" /f 

echo Registry editing complete.  Changing password policies.
echo Passwords must be 10 digits
net accounts /minpwlen:10
echo Passwords must be changed every 90 days
net accounts /maxpwage:90
echo Passwords can only be changed after 7 days have passed
net accounts /minpwage:7
echo Lockout threshold is 5
net accounts /lockoutthreshold:5 
echo Passwords remembered is 24
net accounts /uniquepw:24

echo Uninstalling OneDrive
taskkill /f /im OneDrive.exe 
%SystemRoot%\System32\OneDriveSetup.exe /uninstall

echo Disabling Unnecessary Services
sc config bthhfsrv start=disabled 
sc stop bthhfsrv 
sc config bthserv start=disabled 
sc stop bthserv 
sc config fax start=disabled 
sc stop fax 
sc config ftpsvc start=disabled 
sc stop ftpsvc 
sc config HomeGroupListener start=disabled 
sc stop HomeGroupListener 
sc config HomeGroupProvider start=disabled 
sc stop HomeGroupProvider 
sc config iphlpsvc start=disabled 
sc stop iphlpsvc 
sc config irmon start=disabled 
sc stop irmon 
sc config lfsvc start=disabled 
sc stop lfsvc 
sc config mcx2svc start=disabled 
sc stop mcx2svc 
sc config msftpsvc start=disabled 
sc stop msftpsvc 
sc config nettcpportsharing start=disabled 
sc stop nettcpportsharing 
sc config p2pimsvc start=disabled 
sc stop p2pimsvc 
sc config remoteAccess start=disabled 
sc stop remoteAccess 
sc config remoteRegistry start=disabled 
sc stop remoteRegistry 
sc config RpcSs start=disabled 
sc stop RpcSs 
sc config seclogon start=disabled 
sc stop seclogon 
sc config SessionEnv start=disabled 
sc stop SessionEnv 
sc config SharedAccess start=disabled 
sc stop SharedAccess 
sc config simptcp start=disabled 
sc stop simptcp 
sc config SNMP start=disabled 
sc stop SNMP 
sc config SNMPTRAP start=disabled 
sc stop SNMPTRAP 
sc config SSDPSRV start=disabled 
sc stop SSDPSRV 
sc config TapiSrv start=disabled 
sc stop TapiSrv 
sc config Telephony start=disabled 
sc stop Telephony 
sc config termservice start=disabled 
sc stop termservice 
sc config telnet start=disabled 
sc stop telnet 
sc config TlntSvr start=disabled 
sc stop TlntSvr 
sc config UmRdpService start=disabled 
sc stop UmRdpService 
sc config W3SVC start=disabled 
sc stop W3SVC 
sc config xblauthmanager start=disabled 
sc stop xblauthmanager 
sc config xblgamesave start=disabled 
sc stop xblgamesave 
sc config xboxnetapisvc start=disabled 
sc stop xboxnetapisvc 

echo Enabling Auto-start Services
sc config eventlog start=auto 
sc start eventlog 
sc config mpssvc start=auto 
sc start mpssvc 

echo Enabling Delayed Auto-start Services
sc config sppsvc start=delayed-auto 
sc start sppsvc 
sc config windefend start=delayed-auto 
sc start windefend 
sc config wuauserv start=delayed-auto 
sc start wuauserv 

echo Enabling On-Demand Services
sc config wersvc start=demand 
sc config wecsvc start=demand 

echo Power configuration (require password on wakeup)
powercfg -SETDCVALUEINDEX SCHEME_BALANCED SUB_NONE CONSOLELOCK 1
powercfg -SETACVALUEINDEX SCHEME_BALANCED SUB_NONE CONSOLELOCK 1
powercfg -SETDCVALUEINDEX SCHEME_MIN SUB_NONE CONSOLELOCK 1
powercfg -SETDCVALUEINDEX SCHEME_MIN SUB_NONE CONSOLELOCK 1
powercfg -SETDCVALUEINDEX SCHEME_MAX SUB_NONE CONSOLELOCK 1
powercfg -SETDCVALUEINDEX SCHEME_MAX SUB_NONE CONSOLELOCK 1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1

echo Finding audio files in C:\
where /r C:\ *.mp3 > audio.txt
where /r C:\ *.ac3 >> audio.txt
where /r C:\ *.aac >> audio.txt
where /r C:\ *.aiff >> audio.txt
where /r C:\ *.flac >> audio.txt
where /r C:\ *.m4a >> audio.txt
where /r C:\ *.m4p >> audio.txt
where /r C:\ *.midi >> audio.txt
where /r C:\ *.mp2 >> audio.txt
where /r C:\ *.m3u >> audio.txt
where /r C:\ *.ogg >> audio.txt
where /r C:\ *.vqf >> audio.txt
where /r C:\ *.wav >> audio.txt

echo Finding video files in C:\
where /r C:\ *.wma > vids.txt
where /r C:\ *.mp4 >> vids.txt
where /r C:\ *.avi >> vids.txt
where /r C:\ *.mpeg4 >> vids.txt

echo Finding picture files in C:\
where /r C:\ *.gif > pics.txt
where /r C:\ *.png >> pics.txt
where /r C:\ *.bmp >> pics.txt
where /r C:\ *.jpg >> pics.txt
where /r C:\ *.jpeg >> pics.txt

echo Finding executable files in C:\
where /r C:\ *.exe > exes.txt

echo Flashing Program Files to a .txt file to reference.
dir /b /s "C:\Program Files\" > programfiles_flashed.txt
dir /b /s "C:\Program Files (x86)\" >> programfiles_flashed.txt

echo Finding common Hacktools...
findstr "Cain" programfiles_flashed.txt | findstr Cain && echo Cain > BadApps.txt
findstr "nmap" programfiles_flashed.txt | findstr nmap && echo nmap >> BadApps.txt
findstr "keylogger" programfiles_flashed.txt | findstr keylogger && echo keylogger >> BadApps.txt
findstr "Armitage" programfiles_flashed.txt | findstr Armitage && echo Armitage >> BadApps.txt
findstr "Metasploit" programfiles_flashed.txt | findstr Metasploit && echo Metasploit >> BadApps.txt
findstr "Shellter" programfiles_flashed.txt | findstr Shellter && echo Shellter >> BadApps.txt
findstr "ophcrack" programfiles_flashed.txt | findstr ophcrack && echo ophcrack >> BadApps.txt
findstr "BitTorrent" programfiles_flashed.txt | findstr BitTorrent && echo BitTorrent >> BadApps.txt
findstr "Wireshark" programfiles_flashed.txt | findstr Wireshark && echo Wireshark >> BadApps.txt
findstr "Npcap" programfiles_flashed.txt | findstr Npcap && echo Npcap >> BadApps.txt

del programfiles_flashed.txt

echo Starts sfc scan
sfc /scannow
echo Sfc scan complete

echo Downloading Malwarebytes Rootkit Scanner
curl https://data-cdn.mbamupdates.com/web/mbar-1.10.3.1001.exe -o MBARSetup.exe
echo Remember to run the setup!

echo Creating GodMode directory
mkdir GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}
echo GodMode directory created

echo Downloading new updates
wuauclt /resetauthorization
wuauclt /detectnow /updatenow
echo Updates downloaded

echo Deleting Windows Shares

reg query "HKLM\System\CurrentControlSet\Services\LanmanServer\Shares" > %APPDATA%\shares.txt
findstr /I /v "HKEY_LOCAL_MACHINE" %APPDATA%\shares.txt | findstr /I /v HKLM >> %APPDATA%\shares2.txt

setlocal EnableDelayedExpansion
for /f "usebackq delims=" %%S in ("%APPDATA%\shares2.txt") do (
	set "tempy=%%S"
	echo Grabs the first section in the line deliniated by 4 spaces.
	for /f "tokens=1 delims=|" %%N in ("!tempy:=|!") do (
		net share "%%N" /delete 
	)
)
endlocal

del %APPDATA%\shares.txt & del %APPDATA%\shares2.txt

echo Windows Shares deleted.

echo Automatic Stuff Complete

echo Opening location of created files.
start .

echo This program doesn't do a few things.
echo It doesn't handle Task Scheduler
echo It doesn't handle startup tasks
echo You can find them here ("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\" and "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\")
echo And in Registry ("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce")
echo Restart the computer after handling any penalties.
pause
cls
goto main

REM ---------------------------------------------------------------------------------------------------------------

:Checklist
cls
echo Windows 10 Checklist
echo 1) Install Malware Bytes and CCleaner
echo 2) Run Malware Bytes and CCleaner
echo 3) If there are any stubborn programs, install IOBit Uninstaller and remove
echo 4) Update Firefox
echo 5) Read readme, if you haven't or only read once, I bet there will be something in there for points
echo 6) Check past checklists
echo 7) Help teamates
echo 8) Get teamates to help you
echo 9) Win!!!
echo.
echo.
echo Windows Server Checklist:
echo 1) Execute the Script
echo 2) Uninstall malware with Malwarebytes
echo 3) Delete and promote/demote users
echo 4) Update firefox
echo 5) Enable the firefox pop-up blocker
echo 6) Enable firefox blocks dangerous downloads
echo 7) Create GodMode directory (it contains over 200 utilities)
echo.
echo.
echo Useful Commands:
echo - rmdir: Remove Directories (rmdir [dir])
echo - dir: View Directories (dir [dir])
echo - where: Find Files by Extension (where /r [dir] *.[xxx] .[etc])
echo - shutdown: Shut Down PC
echo - tree: Shows Graphical Tree of Directories and Files (tree [dir])
echo.
echo.
echo This program does not do a few things... Make sure to do them manually.
echo 1) Check the file shares.  To know what to delete, go to Google.
echo 2) It cannot edit group policy reliably, so refer to the checklist for that.
echo 	2) Some Policies to change:
echo 	2a) Always sign communication over Microsoft network Server
echo 	2b) Disable everyone perms for anonymous users
echo 	2c) Enable RDP network level authentication
echo 	2d) Disable remote assistance connections
echo 3) Disable DNS Server in Chrome
echo 4) Install Windows Defender from https://aka.ms/WindowsDefender
echo 5) Enable Windows Firewall (Just make everything green in Windows Defender)
echo.
echo Press Enter to return to menu...
pause
cls
goto main
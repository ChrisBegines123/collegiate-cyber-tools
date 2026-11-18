# Inprogress PowerShell Script
<#
What this program does:
1. Creates `ccdcadmin` account
2. Changes password of `ccdcadmin` depending on what machine the script is running on
3. Changes account security policies
4. Sets a login banner
5. Disables default Guest and Administrator account | NEW: Disables UserOne account on Win11 Wkst
6. Sets a random password for default accounts every run
7. Enables firewalls
8. Disables legacy services
9. Sets UAC to maximum
10. Installs and Deploys Wazuh Agent | Sets Manager IP to Splunk IP
11. Downloads and configures ClamAV
12. Downloads and runs DeepBlueCLI
13. Creates System Inventory Report
14. Creates scheduled tasks to automatically run Audit.ps1, ClamAV.ps1 (REMOVED), DeepBlueCLIScan.ps1

#>

# Logs are created at "C:\Logs"

# Change the below parameters for competition
# ----
# Parameters
# ----
$DSRMPassword = "!Changeme123"
$WazuhManagerIP = "172.20.242.20" # Ensure that this is the IP of Splunk

# ----
# Logging
# ----
$LogDir = "C:\Logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$TimestampName = Get-Date -Format "HHmm"
$LogFile = Join-Path $LogDir "initialHardening_$TimestampName.log"

Start-Transcript -Path $LogFile

# ----
# Status Function
# ----
function Write-Status {
 param (
    [Parameter(Mandatory)]
    [string]$Message,

    [ValidateSet("Info","Success","Warning","Error")]
    [string]$Level = "Info"
 ) 
 
 $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 $LogEntry = "$Timestamp [$Level] $Message"
 switch ($Level) {
    "Success" {Write-Host "[SUCCESS] $Message" -ForegroundColor Green}
    "Warning" {Write-Host "[WARNING] $Message" -ForegroundColor Yellow}
    "Error" {Write-Host "[ERROR] $Message" -ForegroundColor Red}
    default {Write-Host "[INFO] $Message"}
 }
}

# ----
# Visual C++ Redist Check Function
# ----
function Test-VCRedistributableInstalled {
    $UninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($Key in $UninstallKeys) {
        try {
            $Matches = Get-ItemProperty $Key -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match "Microsoft Visual C\+\+.*Redistributable" }
            if ($Matches) {
                return $true
            }
        } catch {
            continue
        }
    }
    return $false
}

# ----
# Detects Active Directory (If applicable)
# ----
$ADAvailable = $false

$ADCmd = Get-Command Get-ADUser -ErrorAction SilentlyContinue
if ($ADCmd -and $ADCmd.Source -eq "ActiveDirectory"){
    $ADAvailable = $true
    Write-Status "Active Directory PowerShell module detected" "Success"
} else {
    Write-Status "Active Directory PowerShell module not available" "Info"
}

# ----
# Detects Joined Domain
# ----
$DomainJoined = $false
if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain -or $ADAvailable) {
    $Domain = (Get-CimInstance Win32_ComputerSystem).Domain
    $SysVol = "\\$Domain\SYSVOL\$Domain"
    Write-Status "Domain '$Domain' Detected" "Success"
    $DomainJoined = $true
} else {
    Write-Status "Machine is not domain-joined" "Warning"
}

# ----
# Determine Windows Version
# ----
$OSInfo = Get-CimInstance Win32_OperatingSystem
$OSCaption = $OSInfo.Caption
Write-Status "Detected OS: $OSCaption" "Info"

# ----
# Set password based on OS and AD presence
# ----
if ($OSCaption -match "Windows Server 2019") {
    if ($ADAvailable) {
        $CCDCPassword = "Level-president00!"      # Password if Server 2019 with AD
        $MachineName = "AD"
    } else {
        $CCDCPassword = "Purpose-brought15!"   # Password if Server 2019 without AD
        $MachineName = "Web"
    }
} elseif ($OSCaption -match "Windows Server 2022") {
    $CCDCPassword = "Washington-hours00!"            # Same for AD or local on 2022
    $MachineName = "FTP"
} elseif ($OSCaption -match "Windows 11") {
    $CCDCPassword = "Services-brought41!"             # Workstation Windows 11
    $MachineName = "Wkst"
} else {
    $CCDCPassword = "Cases-planning30!"              # Default fallback
    $MachineName = "Unknown"
} 

# ----
# CCDCAdmin Account
# ----
$SecureCCDCPassword = ConvertTo-SecureString $CCDCPassword -AsPlainText -Force
$CCDCAccountName = "ccdcadmin"

try {
    if ($ADAvailable) {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$CCDCAccountName'" -ErrorAction SilentlyContinue)) {
            Write-Host "Testing"
            $DomainDN = (Get-ADDomain).DistinguishedName
            $UserOU = "CN=Users," + $DomainDN
            New-ADUser -Name $CCDCAccountName -SamAccountName $CCDCAccountName -AccountPassword $SecureCCDCPassword -Enabled $true -PasswordNeverExpires $true -Path $UserOU -PassThru
            $AdminGroups = @("Administrators","Domain Admins","Enterprise Admins","Group Policy Creator Owners","Schema Admins","DnsAdmins")
            foreach ($Group in $AdminGroups) { Add-ADGroupMember -Identity $Group -Members $CCDCAccountName -ErrorAction SilentlyContinue }
            Write-Status "AD account '$CCDCAccountName' created and added to admin groups" "Success"
        } else {
            Write-Status "AD account '$CCDCAccountName' already exists" "Info"
        }
    } else {
        if (-not (Get-LocalUser -Name $CCDCAccountName -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $CCDCAccountName -Password $SecureCCDCPassword -FullName "CCDC Administrator" -PasswordNeverExpires | Out-Null
            Add-LocalGroupMember -Group "Administrators" -Member $CCDCAccountName
            Write-Status "Local account '$CCDCAccountName' created and added to Administrators group" "Success"
        } else {
            Write-Status "Local account '$CCDCAccountName' already exists" "Info"
        }
    }
} catch {
    Write-Status "Failed to create $CCDCAccountName account: $_" "Error"
}

<#
# ----
# Change DSRM Password
# ----
if ($ADAvailable) {
    try {
        Write-Status "Changing DSRM password..." "Info"

        $NTDSInput = @"
activate instance ntds
set dsrm password
reset password on server null
$DSRMPassword
$DSRMPassword
quit
quit
"@

        $Result = $NTDSInput | ntdsutil.exe

        if ($Result -match "Error") {
            throw "ntdsutil reported an error: $Result"
        }

        Write-Status "DSRM password successfully updated" "Success"
    } catch {
        Write-Status "Failed to update DSRM password: $_" "Error"
    }
} else {
    Write-Status "Skipping DSRM password update because AD is not present" "Warning"
}

#>

# ----
# Security Policies and Interactive Logon Banner
# ----

$LegalNoticeTitle = "Authorized Use Notice"

$LegalNoticeText = @"
This computer system is restricted to authorized users only.
Activities on this system may be monitored, logged, and reviewed.
By continuing, you consent to monitoring and acknowledge your responsibility.
Unauthorized access is prohibited and may result in disciplinary or legal action.
"@

if ($ADAvailable) {

    Write-Status "Checking Active Directory password policy and logon banner" "Info"

    try {
        $CurrentPolicy = Get-ADDefaultDomainPasswordPolicy
        if ($CurrentPolicy.MinPasswordLength -eq 14 -and $CurrentPolicy.ComplexityEnabled -eq $true -and $CurrentPolicy.MaxPasswordAge.Days -eq 90) {
            Write-Status "Domain password policy already compliant" "Info"
        } else {
            Set-ADDefaultDomainPasswordPolicy -Identity $Domain -MinPasswordLength 14 -ComplexityEnabled $true -MaxPasswordAge (New-TimeSpan -Days 90) -ErrorAction Stop
            Write-Status "Domain password policy applied successfully" "Success"
        }
    } catch {
        Write-Status "Failed to process domain password policy: $_" "Error"
    }

    try {
        $SysReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $CurrentTitle = (Get-ItemProperty -Path $SysReg -Name legalnoticecaption -ErrorAction SilentlyContinue).legalnoticecaption
        $CurrentText  = (Get-ItemProperty -Path $SysReg -Name legalnoticetext -ErrorAction SilentlyContinue).legalnoticetext

        if ($CurrentTitle -eq $LegalNoticeTitle -and $CurrentText -eq $LegalNoticeText) {
            Write-Status "Domain interactive logon banner already configured" "Info"
        } else {
            Set-ItemProperty -Path $SysReg -Name legalnoticecaption -Value $LegalNoticeTitle -Force
            Set-ItemProperty -Path $SysReg -Name legalnoticetext -Value $LegalNoticeText -Force
            Write-Status "Domain interactive logon banner configured" "Success"
        }
    } catch {
        Write-Status "Failed to configure domain logon banner: $_" "Error"
    }

} else {

    Write-Status "Checking local password policy and logon banner" "Info"

    try {
        secedit /export /cfg "$env:TEMP\secpol.cfg" | Out-Null
        $SecPol = Get-Content "$env:TEMP\secpol.cfg"

        $MinLenOK = ($SecPol -match "^MinimumPasswordLength\s*=\s*9$")
        $ComplexOK = ($SecPol -match "^PasswordComplexity\s*=\s*1$")
        $MaxAgeOK = ($SecPol -match "^MaximumPasswordAge\s*=\s*90$")

        if ($MinLenOK -and $ComplexOK -and $MaxAgeOK) {
            Write-Status "Local password policy already compliant" "Info"
        } else {
            $SecPol.Replace("MinimumPasswordLength =", "MinimumPasswordLength = 9").
                    Replace("PasswordComplexity =", "PasswordComplexity = 1").
                    Replace("MaximumPasswordAge =", "MaximumPasswordAge = 90") |
                    Set-Content "$env:TEMP\secpol.cfg"

            secedit /configure /db "$env:TEMP\secedit.sdb" /cfg "$env:TEMP\secpol.cfg" /areas SECURITYPOLICY | Out-Null
            Write-Status "Local password policy applied successfully" "Success"
        }
    } catch {
        Write-Status "Failed to process local password policy: $_" "Error"
    }

    try {
        $SysReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $CurrentTitle = (Get-ItemProperty -Path $SysReg -Name legalnoticecaption -ErrorAction SilentlyContinue).legalnoticecaption
        $CurrentText  = (Get-ItemProperty -Path $SysReg -Name legalnoticetext -ErrorAction SilentlyContinue).legalnoticetext

        if ($CurrentTitle -eq $LegalNoticeTitle -and $CurrentText -eq $LegalNoticeText) {
            Write-Status "Local interactive logon banner already configured" "Info"
        } else {
            Set-ItemProperty -Path $SysReg -Name legalnoticecaption -Value $LegalNoticeTitle -Force
            Set-ItemProperty -Path $SysReg -Name legalnoticetext -Value $LegalNoticeText -Force
            Write-Status "Local interactive logon banner configured" "Success"
        }
    } catch {
        Write-Status "Failed to configure local logon banner: $_" "Error"
    }
}


# DNS Configuration and Logging
try {
    if ($ADAvailable) {
        $DNSLog = Join-Path $LogDir "DNS-Log.txt"
        Set-DNSServerDiagnostics -All $true -Verbose
        Set-DNSServerDiagnostics -LogFilePath $DNSLog -Verbose
        Write-Status "DNS logging enabled at $DNSLog" "Success"
    } else {
        Write-Status "Active Directory not detected, skipping DNS server logging" "Info"
    }

    AuditPol /set /category:"Logon/Logoff" /success:enable /failure:enable | Out-Null
    AuditPol /set /category:"Account Management" /success:enable /failure:enable | Out-Null
    AuditPol /set /category:"Policy Change" /success:enable /failure:enable | Out-Null

    Write-Status "Audit policy configured for Logon Events, Account Management, and Policy Changes" "Success"

} catch {
    Write-Status "Failed to configure DNS or audit policy: $_" "Error"
}

# Disable Default Accounts
$AccountsToDisable = @("Administrator","Guest","UserOne")

foreach ($Account in $AccountsToDisable) {
    try {
        if ($ADAvailable) {
            $User = Get-ADUser -Identity $Account -Properties Enabled -ErrorAction SilentlyContinue
            if ($User) {
                if ($User.Enabled) {
                    Disable-ADAccount -Identity $Account -Confirm:$false
                    Write-Status "Disabled AD account: '$Account'" "Success"
                } else {
                    Write-Status "AD account '$Account' already disabled" "Info"
                }
            } else {
                Write-Status "AD account '$Account' does not exist" "Warning"
            }
        } else {
            $User = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
            if ($User) {
                if ($User.Enabled) {
                    Disable-LocalUser -Name $Account
                    Write-Status "Disabled local account '$Account'" "Success"
                } else {
                    Write-Status "Local account '$Account' already disabled" "Info"
                }
            } else {
                Write-Status "Local account '$Account' does not exist" "Warning"
            }
        }
    } catch {
        Write-Status "Error processing account '$Account': $_" "Error"
    }
}

# ----
# Reset Passwords for Sensitive Accounts
# ----
$SensitiveAccounts = @("krbtgt","Administrator","Guest")  # Add more accounts here if needed

if ($ADAvailable) {
    foreach ($Acct in $SensitiveAccounts) {
        try {
            $CurrentUser = Get-ADUser -Identity $Acct -ErrorAction SilentlyContinue
            if ($CurrentUser) {
                Add-Type -AssemblyName System.Web
                $Password = [System.Web.Security.Membership]::GeneratePassword(100,20)
                $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
                Set-ADAccountPassword -Identity $CurrentUser -NewPassword $SecurePassword -Reset -ErrorAction Stop
                Write-Status "Password reset for AD account '$Acct'" "Success"
            } else {
                Write-Status "AD account '$Acct' does not exist" "Warning"
            }
        } catch {
            Write-Status "Failed to reset password for AD account '$Acct': $_" "Error"
        }
    }
} else {
    foreach ($Acct in $SensitiveAccounts) {
        try {
            $LocalUser = Get-LocalUser -Name $Acct -ErrorAction SilentlyContinue
            if ($LocalUser) {
                Add-Type -AssemblyName System.Web
                $Password = [System.Web.Security.Membership]::GeneratePassword(100,20)
                $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
                $LocalUser | Set-LocalUser -Password $SecurePassword
                Write-Status "Password reset for local account '$Acct'" "Success"
            } else {
                Write-Status "Local account '$Acct' does not exist" "Warning"
            }
        } catch {
            Write-Status "Failed to reset password for local account '$Acct': $_" "Error"
        }
    }
}

# ----
# Ensure Windows Defender Firewall is enabled
# ----

try {
    $FirewallProfiles = @("Domain","Private","Public")

    foreach ($Profile in $FirewallProfiles) {
        $ProfileStatus = (Get-NetFirewallProfile -Profile $Profile).Enabled
        if ($ProfileStatus -eq $false) {
            Set-NetFirewallProfile -Profile $Profile -Enabled True
            Write-Status "Firewall enabled for $Profile profile" "Success"
        } else {
            Write-Status "Firewall already enabled for $Profile profile" "Info"
        }
    }
} catch {
    Write-Status "Failed to configure Windows Defender Firewall: $_" "Error"
}

# ----
# Disable legacy services: NetBIOS, Telnet, SMBv1, and LLMNR
# ----

try {
    $NetAdapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true}
    foreach ($Adapter in $NetAdapters) {
        $Adapter | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions=2} | Out-Null
    }
    Write-Status "NetBIOS over TCP/IP disabled on all active adapters" "Success"
} catch {
    Write-Status "Failed to disable NetBIOS: $_" "Warning"
}

try {
    if (Get-Service -Name TlntSvr -ErrorAction SilentlyContinue) {
        Stop-Service -Name TlntSvr -Force -ErrorAction SilentlyContinue
        Set-Service -Name TlntSvr -StartupType Disabled
        Write-Status "Telnet service stopped and disabled" "Success"
    } else {
        Write-Status "Telnet service not installed or already disabled" "Info"
    }
} catch {
    Write-Status "Failed to stop/disable Telnet service: $_" "Warning"
}

try {
    $SMB1Feature = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
    if ($SMB1Feature.State -ne "Disabled") {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop
        Write-Status "SMBv1 protocol disabled" "Success"
    } else {
        Write-Status "SMBv1 protocol already disabled" "Info"
    }
} catch {
    Write-Status "Failed to disable SMBv1: $_" "Warning"
}

try {
    $LLMNRReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $LLMNRReg)) {
        New-Item -Path $LLMNRReg -Force | Out-Null
    }
    Set-ItemProperty -Path $LLMNRReg -Name "EnableMulticast" -Value 0 -Force
    Write-Status "LLMNR (Link-Local Multicast Name Resolution) disabled" "Success"
} catch {
    Write-Status "Failed to disable LLMNR: $_" "Warning"
}

# ----
# Set UAC to Maximum Security
# ----

try {
    $UACReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

    Set-ItemProperty $UACReg EnableLUA 1 -Force
    Set-ItemProperty $UACReg ConsentPromptBehaviorAdmin 2 -Force
    Set-ItemProperty $UACReg PromptOnSecureDesktop 1 -Force

    Write-Status "UAC set to maximum security level" "Success"
} catch {
    Write-Status "Failed to configure UAC: $_" "Error"
}

# ----
# Wazuh Agent Deployment
# ----
if ($DomainJoined) {

    Write-Status "Starting Wazuh Agent deployment check" "Info"

    $WazuhServiceName = "WazuhSvc"
    $InstallerPath   = "$Sysvol\Software\wazuh-agent-4.14.2-1.msi"
    $WazuhService = Get-Service -Name $WazuhServiceName -ErrorAction SilentlyContinue
    if ($WazuhService) {
        if ($WazuhService.Status -ne "Running") {
            Write-Status "Wazuh service not running, attempting to start" "Warning"
            Start-Service $WazuhServiceName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            if ($WazuhService.Status -ne "Running") {
                Write-Status "Wazuh agent installed and service successfully started" "Success"
            } else {
                Write-Status "Wazuh agent installed but Failed to start Wazuh service" "Error"
            }
        } else {
            Write-Status "Wazuh Agent already installed and running" "Success"
        }
    } else {
        if (-not (Test-Path $InstallerPath)) {
            Write-Status "Wazuh Agent installer not found at $InstallerPath" "Error"
        } else {
            Write-Status "Installing Wazuh Agent from SYSVOL" "Info"
            $InstallArgs = "/i `"$InstallerPath`" /q WAZUH_MANAGER=`"$WazuhManagerIP`""
            $InstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru
            if ($InstallProc.ExitCode -eq 0) {
                Write-Status "Wazuh Agent installed successfully" "Success"
            } else {
                Write-Status "Wazuh Agent installation failed with exit code $($InstallProc.ExitCode)" "Error"
            }
            Start-Sleep -Seconds 5
            if (Get-Service -Name $WazuhServiceName -ErrorAction SilentlyContinue) {
                Write-Status "Started Wazuh" "Success"
                Start-Service $WazuhServiceName -ErrorAction SilentlyContinue
            } else {
                Write-Status "Wazuh service not detected after install" "Error"
            }
        }
    }
} else {
    Write-Status "Skipping Wazuh Deployment. Not Domain Joined" "Warning"
}

<#
# ----
# Install VC++ if uninstalled for ClamAV/FreshClam
# ----
if ($DomainJoined){
    $VCRedistInstalled = $false
    $VCRedistPath = "$Sysvol\Software\VC_redist.x64.exe"
    if (-Not(Test-VCRedistributableInstalled)){
        Write-Status "VC++ Redist not detected. Trying to install from SYSVOL" "Warning"
        if (-Not(Test-Path $VCRedistPath)) {
            Write-Status "VC++ Redist installer not found" "Error"
        } else {
            try {
                Start-Process -FilePath $VCRedistPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
                if (Test-VCRedistributableInstalled){
                    Write-Status "Visual C++ Redistributables successfully installed" "Success"
                    $VCRedistInstalled = $true
                } else {
                    Write-Status "Visual C++ Redistributables failed to install" "Error"
                }
            } catch {
                Write-Status "Failed to install VC++ Redist: $_" "Error"
            }
        }
    } else {
        Write-Status "Visual C++ Redistributables already installed" "Info"
        $VCRedistInstalled = $true
    }
} else {
    Write-Status "Skipping check for C++ redist. Not Domain Joined" "Warning"
}
#>
$VCRedistInstalled = $true
# ----
# ClamAV Installation and Setup
# ----
Write-Status "VCRedistInstalled = $VCRedistInstalled" "Info"

if ($VCRedistInstalled) {

    $InstallerPath   = "C:\clamav-1.5.1.win.x64.msi"
    $FreshClamPath   = "C:\Program Files\ClamAV\freshclam.exe"
    $FreshClamConfig = "C:\Program Files\ClamAV\freshclam.conf"
    $ClamDConfig     = "C:\Program Files\ClamAV\clamd.conf"

    # ---- Install ClamAV ----
    if (-not (Test-Path $FreshClamPath)) {
        Write-Status "ClamAV not detected. Installing from $InstallerPath" "Info"

        if (-not (Test-Path $InstallerPath)) {
            Write-Status "Installer not found at $InstallerPath. Installing from internet." "Info"
            try {
                $ClamAVUrl = "https://www.clamav.net/downloads/production/clamav-1.5.1.win.x64.msi"
                Invoke-WebRequest -Uri $ClamAVUrl -OutFile $InstallerPath -UseBasicParsing
                Write-Status "ClamAV installer downloaded successfully." "Success"
            }
            catch {
                Write-Status "Failed to download ClamAV installer: $_" "Error"
                return
            }
        }

        $InstallArgs = "/i `"$InstallerPath`" /qn"
        try {
            $InstallProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru
            Write-Status "ClamAV installed successfully." "Success"
        }
        catch {
            Write-Status "ClamAV installation failed: $_" "Error"
            return
        }
    }
    else {
        Write-Status "ClamAV already installed. Skipping installation." "Info"
    }

    # ---- Configure freshclam.conf ----
    if (-not (Test-Path $FreshClamConfig)) {
        Write-Status "freshclam.conf not found. Creating from sample." "Info"
        Copy-Item "C:\Program Files\ClamAV\conf_examples\freshclam.conf.sample" $FreshClamConfig -Force

        $fileContent = Get-Content $FreshClamConfig
        $fileContent = $fileContent | ForEach-Object {
            if ($_ -match "Example") { $null }
            elseif ($_ -match "^#\s*UpdateLogFile") { $_ -replace "^#\s*", "" }
            else { $_ }
        }

        $fileContent | Set-Content $FreshClamConfig
        Write-Status "freshclam.conf configured." "Success"
    }
    else {
        Write-Status "freshclam.conf already exists. Skipping configuration." "Info"
    }

    # ---- Configure clamd.conf ----
    if (-not (Test-Path $ClamDConfig)) {
        Write-Status "clamd.conf not found. Creating from sample." "Info"
        Copy-Item "C:\Program Files\ClamAV\conf_examples\clamd.conf.sample" $ClamDConfig -Force

        $fileContent = Get-Content $ClamDConfig
        $fileContent = $fileContent | ForEach-Object {
            if ($_ -match "Example") { $null }
            elseif ($_ -match "^#LogTime") { $_ -replace "^#LogTime", "LogTime" }
            elseif ($_ -match "^#LogVerbose") { $_ -replace "^#LogVerbose", "LogVerbose" }
            elseif ($_ -match "^#ExtendedDetectionInfo") { $_ -replace "^#ExtendedDetectionInfo", "ExtendedDetectionInfo" }
            elseif ($_ -match "^#DetectPUA") { $_ -replace "^#DetectPUA", "DetectPUA" }
            elseif ($_ -match "^#HeuristicAlerts") { $_ -replace "^#HeuristicAlerts", "HeuristicAlerts" }
            elseif ($_ -match "^#?MaxThreads") { "MaxThreads 2" }
            else { $_ }
        }

        $fileContent | Set-Content $ClamDConfig
        Write-Status "clamd.conf configured." "Success"
    }
    else {
        Write-Status "clamd.conf already exists. Skipping configuration." "Info"
    }

    # ---- Create FreshClam Log File ----
    $FreshClamLog = "C:\Program Files\ClamAV\freshclam.log"
    if (-not (Test-Path $FreshClamLog)) {
        try {
            New-Item -Path $FreshClamLog -ItemType File -Force | Out-Null
            Write-Status "FreshClam log file created at $FreshClamLog" "Success"
        }
        catch {
            Write-Status "Failed to create FreshClam log file: $_" "Error"
        }
    }
    else {
        Write-Status "FreshClam log file already exists." "Info"
    }

    # ---- Ensure ClamAV Certificate Installed ----
    $CertPath = "C:\Program Files\ClamAV\certs\clamav.crt"
    if (Test-Path $CertPath) {
        $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $Cert.Import($CertPath)

        $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root","LocalMachine"
        $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

        $Store.Add($Cert)
        $Store.Close()

        Write-Host "clamav.crt has been added to the Trusted Root store" -ForegroundColor Green
    }

    # ---- Run FreshClam ----
    if (Test-Path $FreshClamPath) {
        Write-Status "Running freshclam.exe to update virus definitions..." "Info"
        try {
            Start-Process -FilePath $FreshClamPath -ArgumentList "--quiet" -Wait
            Write-Status "FreshClam update completed successfully." "Success"
        }
        catch {
            Write-Status "FreshClam failed to update virus database: $_" "Error"
        }
    }
    else {
        Write-Status "FreshClam executable not found. Cannot update virus database." "Error"
    }

    Write-Status "Go to FreshClam.log to ensure no errors" "Warning"
}
else {
    Write-Status "Skipping ClamAV Deployment. Visual C++ Redistributables not installed" "Warning"
}

# ----
# DeepBlueCLI
# ----
$DeepBlueDir = "C:\Tools\DeepBlueCLI"

if (-not (Test-Path $DeepBlueDir)) {
    Write-Status "DeepBlueCLI not found. Downloading..." "Warning"
    New-Item -ItemType Directory -Path $DeepBlueDir -Force | Out-Null

    Invoke-WebRequest `
        -Uri "https://github.com/sans-blue-team/DeepBlueCLI/archive/refs/heads/master.zip" `
        -OutFile "$env:TEMP\DeepBlueCLI.zip" `
        -UseBasicParsing

    Expand-Archive "$env:TEMP\DeepBlueCLI.zip" "$env:TEMP\DeepBlueCLI" -Force
    Copy-Item "$env:TEMP\DeepBlueCLI\DeepBlueCLI-master\*" $DeepBlueDir -Recurse -Force

    Write-Status "DeepBlueCLI installed successfully"
}
else {
    Write-Status "DeepBlueCLI already installed"
}

$RegexFile   = "$DeepBlueDir\regexes.txt"
$SafelistFile = "$DeepBlueDir\safelist.txt"

if (-not (Test-Path $RegexFile)) {
    Write-Status "Downloading regexes.txt" "Warning"
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/sans-blue-team/DeepBlueCLI/master/regexes.txt" `
        -OutFile $RegexFile `
        -UseBasicParsing
}

if (-not (Test-Path $SafelistFile)) {
    Write-Status "Downloading safelist.txt" "Warning"
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/sans-blue-team/DeepBlueCLI/master/safelist.txt" `
        -OutFile $SafelistFile `
        -UseBasicParsing
}

# -------- Run DeepBlueCLI --------
Write-Status "Running DeepBlueCLI analysis"

try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -Command "Set-Location '$DeepBlueDir'; .\DeepBlue.ps1 -Log Security -OutFile '$LogFile' -OutputFormat Text"

    Write-Status "DeepBlueCLI analysis completed successfully" "Success"
    Write-Status "Results saved to $LogFile"
}
catch {
    Write-Status "DeepBlueCLI execution failed: $_" "Error"
}

# ----
# Inventory Report Generator
# ----
function Generate-InventoryReport {
    if ($DomainJoined -and $SysVol) {
        $SysVolPath = "\\$Domain\SYSVOL\$Domain\InventoryReports"
        if (-not (Test-Path $SysVolPath)) {
            try {
                New-Item -Path $SysVolPath -ItemType Directory -Force | Out-Null
                Write-Status "Created SYSVOL InventoryReports folder at $SysVolPath" "Success"
            } catch {
                Write-Status "Failed to create SYSVOL folder. Defaulting to C:\Logs" "Warning"
                $SysVolPath = "C:\Logs"
            }
        }
    } else {
        $SysVolPath = "C:\Logs"
    }

    $ReportPath = Join-Path -Path $SysVolPath -ChildPath "${MachineName}Inventory.txt"
    Write-Status "Generating inventory report at $ReportPath" "Info"

    # System Info
    $SystemName = $MachineName
    $Platform = (Get-CimInstance Win32_OperatingSystem).Caption

    # Local Accounts
    try {
        $LocalAccounts = Get-LocalUser | Select-Object -ExpandProperty Name
    } catch {
        $LocalAccounts = @("Could not retrieve local accounts")
    }

    # Domain Accounts (if AD available)
    $DomainAccounts = @()
    if ($ADAvailable) {
        try {
            $DomainAccounts = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
        } catch {
            $DomainAccounts = @("Could not retrieve domain accounts")
        }
    }

    # Services with status
    try {
        $Services = Get-Service | ForEach-Object { "$($_.Name) [$($_.Status)]" }
    } catch {
        $Services = @("Could not retrieve services")
    }

    # Build report
    $ReportContent = @()
    $ReportContent += "==== INVENTORY REPORT ===="
    $ReportContent += "System Name: $SystemName"
    $ReportContent += "Platform/OS: $Platform"
    $ReportContent += ""
    $ReportContent += "Local Accounts:"
    foreach ($Account in $LocalAccounts) {
        $ReportContent += " - $Account"
    }
    if ($DomainAccounts.Count -gt 0) {
        $ReportContent += ""
        $ReportContent += "Domain Accounts:"
        foreach ($Account in $DomainAccounts) {
            $ReportContent += " - $Account"
        }
    }
    $ReportContent += ""
    $ReportContent += "Services:"
    foreach ($Service in $Services) {
        $ReportContent += " - $Service"
    }
    $ReportContent += "========================="

    $ReportContent | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Status "Inventory report generated successfully" "Success"
}

# Generate the report
Generate-InventoryReport

# ----
# Create Scheduled Tasks (Server 2019+, Win11 Compatible)
# ----

$Domain = $env:USERDNSDOMAIN
$SysvolScriptRoot = "\\$Domain\SYSVOL\$Domain\Scripts"

$ScheduledTasks = @(
<#    @{
        TaskName   = "ClamAV Scan"
        Script     = "$SysvolScriptRoot\ClamAV.ps1"
        Interval   = 30
        UseMutex   = $true
        Settings   = @{
            MultipleInstances = 'IgnoreNew'
            ExecutionTimeLimit = (New-TimeSpan -Hours 1)
        }
    }, #>
    @{
        TaskName   = "DeepBlueCLI Scan"
        Script     = "$SysvolScriptRoot\DeepBlueCLIScan.ps1"
        Interval   = 15
        UseMutex   = $false
        Settings   = @{
            MultipleInstances = 'IgnoreNew'
            ExecutionTimeLimit = (New-TimeSpan -Minutes 30)
        }
    },
    @{
        TaskName   = "Audit Scan"
        Script     = "$SysvolScriptRoot\Audit.ps1"
        Interval   = 15
        UseMutex   = $false
        Settings   = @{
            MultipleInstances = 'IgnoreNew'
            ExecutionTimeLimit = (New-TimeSpan -Minutes 30)
        }
    }
)

foreach ($Task in $ScheduledTasks) {

    if (Get-ScheduledTask -TaskName $Task.TaskName -ErrorAction SilentlyContinue) {
        Write-Host "Scheduled task already exists: $($Task.TaskName). Skipping."
        continue
    }

    if (-not (Test-Path $Task.Script)) {
        Write-Host "Scheduled task script not found: $($Task.Script). Skipping."
        continue
    }

    $TriggerStartTime = (Get-Date).AddMinutes($Task.Interval)

    $Action = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($Task.Script)`""

    $Trigger = New-ScheduledTaskTrigger `
        -Once `
        -At $TriggerStartTime `
        -RepetitionInterval (New-TimeSpan -Minutes $Task.Interval) `
        -RepetitionDuration (New-TimeSpan -Days 365)

    $Principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $Settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -MultipleInstances $Task.Settings.MultipleInstances `
        -ExecutionTimeLimit $Task.Settings.ExecutionTimeLimit

    try {
        Register-ScheduledTask `
            -TaskName $Task.TaskName `
            -Action $Action `
            -Trigger $Trigger `
            -Principal $Principal `
            -Settings $Settings `
            -Force

        Start-ScheduledTask -TaskName $Task.TaskName

        Write-Host "Scheduled task created and started immediately: $($Task.TaskName)"
    }
    catch {
        Write-Host "Failed to create or start scheduled task '$($Task.TaskName)': $_"
    }
}
# ============================================================
# FULL END-TO-END WINDOWS / DC HARDENING (SERVICE-SAFE)
# ============================================================
# This is still baseline. It still needs to use the Write-Status function and confirm $ADAvailable for actions that require Domain Controller or Active Directory
# Removed temp. Due to the changes of the End-to-End hardening, it will be implemented last to ensure that everything else works.

Write-Status "Script Execution Finished" "Success"


Stop-Transcript

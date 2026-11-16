curl.exe -o 'Windows Server 2022 Security Baseline.zip' 'https://download.microsoft.com/download/8/5/c/85c25433-a1b0-4ffa-9429-7e023e7da8d8/Windows%20Server%202022%20Security%20Baseline.zip'
Expand-Archive -Path 'Windows Server 2022 Security Baseline.zip' -DestinationPath 'C:\Security Baseline' -force 
curl.exe -o 'Windows 10 Version 1809 and Windows Server 2019 Security Baseline.zip' 'https://download.microsoft.com/download/8/5/c/85c25433-a1b0-4ffa-9429-7e023e7da8d8/Windows%2010%20Version%201809%20and%20Windows%20Server%202019%20Security%20Baseline.zip' 
Expand-Archive -Path 'Windows 10 Version 1809 and Windows Server 2019 Security Baseline.zip' -DestinationPath 'C:\Security Baseline\WinServer2019\' -force 
curl.exe -o 'Windows 11 v25H2 Security Baseline.zip' 'https://download.microsoft.com/download/e99be2d2-e077-4986-a06b-6078051999dd/Windows%2011%20v25H2%20Security%20Baseline.zip'
Expand-Archive -Path 'Windows 11 v25H2 Security Baseline.zip' -DestinationPath 'C:\Security Baseline' -force

cd 'C:\Security Baseline\Windows 11 v25H2 Security Baseline\Scripts'
.\Baseline-ADImport.ps1
Copy-Item -Path 'C:\Security Baseline\Windows 11 v25H2 Security Baseline\Scripts\' -Destination 'C:\Security Baseline\WinServer2019\' -Force -Recurse
cd 'C:\Security Baseline\WinServer2019\Scripts'
.\Baseline-ADImport.ps1
cd 'C:\Security Baseline\Windows Server-2022-Security-Baseline-FINAL\Scripts'
.\Baseline-ADImport.ps1

try {
    new-adorganizationalunit -name "Win11Workstation"
}
catch {
    Write-Host "OU Win11Workstation already exists, moving on"
}
try {
    new-adorganizationalunit -name "Win22Server"
}
catch {
    Write-Host "OU Win22Server already exists, moving on"
}
try {
    new-adorganizationalunit -name "Win19Server"
}
catch {
    Write-Host "OU Win19Server already exists, moving on"
}

$root = (Get-ADRootDSE).defaultNamingContext

try{
    $gpo = get-gpo -Name "MSFT Windows 11 25H2 - Computer"
    write-host $gpo
    new-gplink -target "OU=Win11Workstation,$root" -ID $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows 11 25H2 - User"
    new-gplink -target "OU=Win11Workstation,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows 11 25H2 - Defender Antivirus"
    new-gplink -target "OU=Win11Workstation,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows 11 25H2 - Credential Guard"
    new-gplink -Target "OU=Win11Workstation,$root" -Id $gpo.Id
}
catch {
    Write-Host "GPO for Windows 11 already exists, moving on"
}
try{
    $gpo = get-gpo -Name "MSFT Windows Server 2022 - Member Server"
    new-gplink -target "OU=Win22Server,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows Server 2022 - Defender Antivirus"
    new-gplink -target "OU=Win22Server,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows Server 2022 - Member Server Credential Guard"
    new-gplink -target "OU=Win22Server,$root" -Id $gpo.Id
}
catch {
    Write-Host "GPO for Windows Server 2022 already exists, moving on"
}
try{
    $gpo = get-gpo -Name "MSFT Windows Server 2019 - Member Server"
    new-gplink -target "OU=Win19Server,$root"  -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows 10 1809 and Server 2019 - Defender Antivirus"
    new-gplink -target "OU=Win19Server,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows 10 1809 and Server 2019 Member Server - Credential Guard"
    new-gplink -target "OU=Win19Server,$root" -Id $gpo.Id
}
catch {
    Write-Host "GPO for Windows Server 2019 already exists, moving on"
}
try{
    $gpo = get-gpo -Name "MSFT Windows 10 1809 and Server 2019 - Defender Antivirus"
    new-gplink -target "OU=Domain Controllers,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows 10 1809 and Server 2019 - Domain Security"
    new-gplink -target "$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows Server 2019 - Domain Controller"
    new-gplink -target "OU=Domain Controllers,$root" -Id $gpo.Id
    $gpo = get-gpo -Name "MSFT Windows Server 2019 - Domain Controller Virtualization Based Security"
    new-gplink -target "OU=Domain Controllers,$root" -Id $gpo.Id
}
catch {
    Write-Host "GPO for Windows Server 2019 domain controller, moving on"
}

# Import necessary modules
Import-Module -Name Microsoft.PowerShell.LocalAccounts
Import-Module -Name NetSecurity
Import-Module -Name BitsTransfer

#The following was borrowed from UWStout, so credit for them, its edited and stuff, but they wrote the base.

## Clear persistence and document it ##

# Registry persistence
$startupRegistryPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run",
    "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows\Run",
    "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Windows\Run"
)

foreach ($path in $startupRegistryPaths) {
    Write-Host "Clearing startup items from $path"
    $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    if ($items) {
        $items.PSObject.Properties | ForEach-Object {
            if ($_.Name -ne "PSPath" -and $_.Name -ne "PSParentPath" -and $_.Name -ne "PSChildName" -and $_.Name -ne "PSDrive" -and $_.Name -ne "PSProvider") {
                $items >> "C:\Users\administrator\Desktop\persistence-registry.txt"
                Remove-ItemProperty -Path $path -Name $_.Name -ErrorAction SilentlyContinue
            }
        }
    }
}

# Start menu persistence
$startupFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)

foreach ($folder in $startupFolders) {
    Write-Host "Clearing startup items from $folder"
    Get-ChildItem -Path $folder | ForEach-Object {
        $_.FullName >> "C:\Users\administrator\Desktop\persistence-startup.txt"
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

# Clear scheduled tasks
Write-Host "Clearing scheduled tasks..."
Get-ScheduledTask | Where-Object { $_.TaskPath -notlike "\Microsoft\*" } | ForEach-Object {
    $_.TaskName >> "C:\Users\administrator\Desktop\persistence-schtasks.txt"
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
}


# Rotate Kerberos account password
try {
    $count = 0;
    while ($count -lt 3) {
        Write-Host "Rotating Kerberos account password..."
        $password = ""
        $letterNumberArray = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '1', '2', '3', '4', '5', '6', '7', '8','9','0', '!', '@', '#', '$', '%', '^', '&', '*')
        for(($counter=0); $counter -lt 20; $counter++)
        {
        $randomCharacter = get-random -InputObject $letterNumberArray
        $password += $randomCharacter
        }

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $krbtgt = Get-LocalUser -Name "krbtgt"
        Set-LocalUser -Name $krbtgt -Password $securePassword
        $count++
    }
    
    Write-Host "--------------------------------------------------------------------------------"
    Write-Host "Kerberos account password rotated successfully."
    Write-Host "--------------------------------------------------------------------------------"
} catch {
    Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    Write-Host "An error occurred while rotating Kerberos password: $_"
    Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
}

# Initialize the global jobs array
$global:jobs = @()

function Start-LoggedJob {
    param (
        [string]$JobName,
        [scriptblock]$ScriptBlock
    )
    
    $job = Start-Job -Name $JobName -ScriptBlock $ScriptBlock
    $global:jobs += @($job)  # Ensure the job is added as an array element
    Write-Host "Started job: $JobName"
}

# Disable guest account
Start-LoggedJob -JobName "Disable Guest Account" -ScriptBlock {
    try {
        $guestAccount = Get-LocalUser -Name "Guest"
        if ($guestAccount.Enabled) {
            Disable-LocalUser -Name "Guest"
            Write-Host "--------------------------------------------------------------------------------"
            Write-Host "Guest account has been disabled."
            Write-Host "--------------------------------------------------------------------------------"
        } else {
            Write-Host "--------------------------------------------------------------------------------"
            Write-Host "Guest account is already disabled."
            Write-Host "--------------------------------------------------------------------------------"
        }
    } catch {
        Write-Hos   t "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while disabling the guest account: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

# Enable Windows Defender with real-time protection and PUA protection
Start-LoggedJob -JobName "Enable Windows Defender" -ScriptBlock {
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false
        Set-MpPreference -PUAProtection Enabled
        
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Windows Defender enabled with real-time protection and PUA protection."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while enabling Windows Defender: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

# Configure Remote Desktop settings (disable if not needed)
Start-LoggedJob -JobName "Disable Remote Desktop" -ScriptBlock {
    try {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Remote Desktop Protocol disabled."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
        Write-Host "An error occurred while disabling Remote Desktop: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
    }
}

# Set account lockout policies
Start-LoggedJob -JobName "Set Account Lockout Policies" -ScriptBlock { 
    try {
        net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Account lockout policies set."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
        Write-Host "An error occurred while setting account lockout policies: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
    }
}

#Enable audit policies for key events like login, account management, file system changes, and registry changes
Start-LoggedJob -JobName "Enable Audit Policies" -ScriptBlock {
    try {
        AuditPol.exe /set /subcategory:"Logon" /success:enable /failure:enable
        AuditPol.exe /set /subcategory:"User Account Management" /success:enable /failure:enable
        AuditPol.exe /set /subcategory:"File System" /success:enable /failure:enable
        AuditPol.exe /set /subcategory:"Registry" /success:enable /failure:enable
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Audit policies for login, account management, file system changes, and registry changes enabled."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while enabling audit policies: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}
Start-LoggedJob -JobName "Remove Unnecessary Network Shares" -ScriptBlock {
    try {
        Get-SmbShare | Where-Object { $_.Name -ne "ADMIN$" -and $_.Name -ne "C$" -and $_.Name -ne "IPC$" -and $_.Name -ne "NETLOGON" -and $_.Name -ne "SYSVOL" } | ForEach-Object {
            Write-Host "Removing share: $($_.Name)"
            Remove-SmbShare -Name $_.Name -Force
        }
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Unnecessary network shares removed."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while removing unnecessary network shares: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

# Block credential dumping
Start-LoggedJob -JobName "Block Credential Dumping" -ScriptBlock {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Set-ItemProperty -Path $regPath -Name "NoLmHash" -Value 1
        Set-ItemProperty -Path $regPath -Name "LimitBlankPasswordUse" -Value 1
        Set-ItemProperty -Path $regPath -Name "RestrictAnonymous" -Value 1
        Set-ItemProperty -Path $regPath -Name "RestrictAnonymousSAM" -Value 1
        Set-ItemProperty -Path $regPath -Name "EveryoneIncludesAnonymous" -Value 0
        Set-ItemProperty -Path $regPath -Name "NoDefaultAdminShares" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoLMAuthentication" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoNullSessionShares" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoNullSessionUsername" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoNullSessionPassword" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoSaveSettings" -Value 1
        
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
        Set-ItemProperty -Path $regPath -Name "AutoShareWks" -Value 0
        Set-ItemProperty -Path $regPath -Name "AutoShareServer" -Value 0
        Set-ItemProperty -Path $regPath -Name "RestrictNullSessAccess" -Value 1
        Set-ItemProperty -Path $regPath -Name "NullSessionPipes" -Value ""
        Set-ItemProperty -Path $regPath -Name "NullSessionShares" -Value ""
        Set-ItemProperty -Path $regPath -Name "Samba" -Value 0

        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
        Set-ItemProperty -Path $regPath -Name "EnableSecuritySignature" -Value 1
        Set-ItemProperty -Path $regPath -Name "RequireSecuritySignature" -Value 1
        Set-ItemProperty -Path $regPath -Name "EnablePlainTextPassword" -Value 0
        
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Credential dumping blocked."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
        Write-Host "An error occurred while blocking credential dumping: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
    }
}

# disable remote sign in
Start-LoggedJob -JobName "Disable Remote Sign-in" -ScriptBlock {
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Set-ItemProperty -Path $regPath -Name "EnableLUA" -Value 0
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Remote sign-in disabled."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while disabling remote sign-in: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

# Enable LSA Protection, restrict debug privileges, disable WDigest
Start-LoggedJob -JobName "Enable LSA Protection" -ScriptBlock {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Set-ItemProperty -Path $regPath -Name "LsaCfgFlags" -Value 1
        Set-ItemProperty -Path $regPath -Name "RunAsPPL" -Value 1
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "LSA Protection enabled."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while enabling LSA Protection: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}
Start-LoggedJob -JobName "Restrict Debug Privileges" -ScriptBlock {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        Set-ItemProperty -Path $regPath -Name "RestrictAnonymous" -Value 1
        Set-ItemProperty -Path $regPath -Name "RestrictAnonymousSAM" -Value 1
        Set-ItemProperty -Path $regPath -Name "EveryoneIncludesAnonymous" -Value 0
        Set-ItemProperty -Path $regPath -Name "NoDefaultAdminShares" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoLMAuthentication" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoNullSessionShares" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoNullSessionUsername" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoNullSessionPassword" -Value 1
        Set-ItemProperty -Path $regPath -Name "NoSaveSettings" -Value 1
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Debug privileges restricted."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while restricting debug privileges: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}
Start-LoggedJob -JobName "Disable WDigest" -ScriptBlock {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
        Set-ItemProperty -Path $regPath -Name "UseLogonCredential" -Value 0
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "WDigest disabled."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while disabling WDigest: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

# disable powershell remoting
Start-LoggedJob -JobName "Disable PowerShell Remoting" -ScriptBlock {
    try {
        # Disable PSRemoting
        Disable-PSRemoting -Force
        powershell --Script "Disable-PSRemoting -Force"
        # Delete the listener that accepts requests on any IP address
        winrm delete winrm/config/Listener?Address=*+Transport=HTTP
        winrm delete winrm/config/Listener?Address=*+Transport=HTTPS

        # Stop and disable the WinRM service
        Stop-Service -Name WinRM -Force
        Set-Service -Name WinRM -StartupType Disabled
        # Restore the value of the LocalAccountTokenFilterPolicy to 0
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 0

        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "PowerShell remoting disabled."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while disabling PowerShell remoting: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}


## Reminder to look into theese two later
Start-LoggedJob -JobName "Patch Mimikatz" -ScriptBlock {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "UseLogonCredential" -Value 0
        }
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "Mimikatz patched."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while patching Mimikatz: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

Start-LoggedJob -JobName "Patch DCSync Vulnerability" -ScriptBlock {
    try {
        Import-Module ActiveDirectory
        $permissions = Get-ACL "AD:\$((Get-ADDomain))" | Select-Object -ExpandProperty Access
        $criticalPermissions = $permissions | Where-Object { $_.ObjectType -eq "19195a5b-6da0-11d0-afd3-00c04fd930c9" -or $_.ObjectType -eq "4c164200-20c0-11d0-a768-00aa006e0529" }
        foreach ($permission in $criticalPermissions) {
            if ($permission.ActiveDirectoryRights -match "Replicating Directory Changes") {
                Write-Host "Removing Replicating Directory Changes permission from $($permission.IdentityReference)"
                $permissions.RemoveAccessRule($permission)
            }
        }
        Set-ACL -Path "AD:\$((Get-ADDomain))" -AclObject $permissions
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "DCSync vulnerability patched."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while patching DCSync vulnerability: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

## Make sure the only SMB allowed is SMBv2 (we hate SMBv1)
Start-LoggedJob -JobName "Upgrade SMB" -ScriptBlock {
    try {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
        
        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "SMB upgraded."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An error occurred while upgrading SMB: $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

#this is stuff I added, again, thank you UWStout for the base.

start-loggedjob -JobName "Backup DNS Zones" -ScriptBlock {
    try{

        Export-DnsServerZone -Name 'ccdcteam.com' -FileName "C:\users\Administrator\desktop\dnsccdcteam.dns"

        Write-Host "--------------------------------------------------------------------------------"
        Write-Host "DNS is backupped."
        Write-Host "--------------------------------------------------------------------------------"
    } catch {
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        Write-Host "An Error Occured with DNS $_"
        Write-Host "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    }
}

# Monitor jobs
while ($jobs.Count -gt 0) {
    foreach ($job in $jobs) {
        if ($job.State -eq 'Completed') {
            $job | Receive-Job
            $jobs = $jobs | Where-Object { $gpo.id -ne $job.Id }
        }
    }
    Start-Sleep -Seconds 5
}
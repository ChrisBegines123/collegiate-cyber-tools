# ==============================================================================
# Script Name : archimedes.ps1
# Description : Assistant to running all first 30 scripting and firewall configuration
#               Intended to operate on any of the windows systems in the environment
# Author      : Tyler Olson
# Organization: Missouri State University
# Version     : 1.0 
# ==============================================================================

# Log file setup
$LogDir = "C:\logs\archimedes\"
$LogFile = "$LogDir\archimedes_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$TimeStamp] [$Level] $Message"
    $LogMessage | Out-File -FilePath $LogFile -Append

    # Also output to console with color coding
    switch ($Level) {
        "INFO" { Write-Host $LogMessage -ForegroundColor Gray }
        "WARNING" { Write-Host $LogMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
    }
}

function Test-Environment {
  Write-Log "Validating environment" "INFO"

  # Check if running as administrator
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
      Write-Log "Script must be run as Administrator" "ERROR"
      return $false
    }

  return $true
}

# -- Selection Menu ---------------------------------

# Menu Helpers
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        (_)                                           ║" -ForegroundColor Cyan
    Write-Host "  ║        |=|                  Archimedes               ║" -ForegroundColor Cyan
    Write-Host "  ║        |=|          Windows Hardening Assistant      ║" -ForegroundColor Cyan
    Write-Host "  ║    /|__|_|__|\                                       ║" -ForegroundColor Cyan
    Write-Host "  ║   (    ( )    )            - Installs                ║" -ForegroundColor Cyan
    Write-Host "  ║    \|\/\ /\/|/             - Hardens                 ║" -ForegroundColor Cyan
    Write-Host "  ║      |  Y  |               - Hunts                   ║" -ForegroundColor Cyan
    Write-Host "  ║     _|  |  |                                         ║" -ForegroundColor Cyan
    Write-Host "  ║  __/ |  |  |\                                        ║" -ForegroundColor Cyan
    Write-Host "  ║ /  \ |  |  |  \                                      ║" -ForegroundColor Cyan
    Write-Host "  ║    __|  |  |   |                                     ║" -ForegroundColor Cyan
    Write-Host "  ║ /\/  |  |  |   |\                                    ║" -ForegroundColor Cyan
    Write-Host "  ║  <   +\ |  |\ />  \                                  ║" -ForegroundColor Cyan
    Write-Host "  ║   >   + \  | LJ    |                                 ║" -ForegroundColor Cyan
    Write-Host "  ║         + \|+  \  < \                                ║" -ForegroundColor Cyan
    Write-Host "  ║ ____________)_____)_/                                ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    Show-Banner
    Write-Host "  TOOLS + REPOSITORY" -ForegroundColor Yellow 
    Write-Host "   [1]  Download MSU Cyber Repository to C:\tools" -ForegroundColor White
    Write-Host "   [2]  Install all common windows tools (firefox, zenmap, wireshark, Sysinternals)" -ForegroundColor White
    Write-Host ""
    Write-Host "  ACCOUNT + AD" -ForegroundColor Yellow
    Write-Host "   [3]  Change current user password" -ForegroundColor White
    Write-Host "   [4]  Add GlassBreak User" -ForegroundColor White
    Write-Host "   [5]  Disable Guest Account" -ForegroundColor White
    Write-Host "   [6]  Set Password Policy" -ForegroundColor White
    Write-Host ""
    Write-Host "  FIREWALL" -ForegroundColor Yellow
    Write-Host "   [7]  Firewall - Lite (allow common services)" -ForegroundColor White
    Write-Host "   [8]  Firewall - Aggressive (deny-all + whitelist)" -ForegroundColor White
    Write-Host "   [9]  Firewall - Block IP Address" -ForegroundColor White
    Write-Host ""
    Write-Host "  HARDENING" -ForegroundColor Yellow
    Write-Host "   [10]  Harden SMB" -ForegroundColor White
    Write-Host "   [11] Disable Remote Services" -ForegroundColor White
    Write-Host "   [12] Harden WMI" -ForegroundColor White
    Write-Host "   [13] Harden LSASS" -ForegroundColor White
    Write-Host "   [14] Configure UAC" -ForegroundColor White
    Write-Host "   [15] Hardned Group Policy (DC Only)" -ForegroundColor White
    Write-Host "   [16] Enable ASLR / DEP" -ForegroundColor White
    Write-Host "   [17] Rotate Kerberos Password" -ForegroundColor White
    Write-Host ""
    Write-Host "  DISABLE / CLEAN" -ForegroundColor Yellow
    Write-Host "   [18] Disable Unnecessary Services" -ForegroundColor White
    Write-Host "   [19] Disable Legacy Protocols" -ForegroundColor White
    Write-Host "   [20] Disable NetBIOS" -ForegroundColor White
    Write-Host "   [21] Disable LLMNR" -ForegroundColor White
    Write-Host "   [22] Clear Persistence" -ForegroundColor White
    Write-Host "   [23] Clear Kerberos Tickets" -ForegroundColor White
    Write-Host ""
    Write-Host "  HUNTING" -ForegroundColor Yellow
    Write-Host "   [24] Hunt for potential malicious items" -ForegroundColor White
    Write-Host "   [25] Hunt for weird kerberos tickets" -ForegroundColor White
    Write-Host ""
    Write-Host "  LOGGING + BACKUP" -ForegroundColor Yellow
    Write-Host "   [26] Enable Advanced Audit Logging" -ForegroundColor White
    Write-Host "   [27] Backup Registry" -ForegroundColor White
    Write-Host ""
    Write-Host "   [A]  Run ALL (full hardening sequence)" -ForegroundColor Magenta
    Write-Host "   [Q]  Quit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────────────────" -ForegroundColor DarkGray

function Invoke-DownloadRepository {
    Write-Log "Starting repository download..." "INFO"
    
    $repositoryUrl = "https://github.com/Missouri-State-CCDC-Team/mwccdc.git"
    $repositoryPath = "C:\CCDC-Repo"
    
    Write-Log "Checking to see if git is installed" "INFO"

    $gitInstalled = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitInstalled) {
        Write-Log "Git not found. Installing Git..." "INFO"
        $gitInstallerUrl = "https://github.com/git-for-windows/git/releases/download/v2.45.0.windows.1/Git-2.45.0-64-bit.exe"
        $installerPath = "$env:TEMP\GitInstaller.exe"

        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $installerPath
            Write-Log "Git installer downloaded to $installerPath" "INFO"

            Start-Process -FilePath $installerPath `
                -ArgumentList "/VERYSILENT /NORESTART" `
                -Wait

            Remove-Item $installerPath -Force
            $env:Path += ";C:\Program Files\Git\bin"

            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                Write-Log "Git installation failed." "ERROR"
                return
            }
        }
        catch {
            Write-Log "Error downloading Git: $_" "ERROR"
            return
        }
    }
    else { 
        Write-Log "Git is already installed" "SUCCESS"
    }

    if (-not (Test-Path $repositoryPath)) {
        New-Item -ItemType Directory -Path $repositoryPath | Out-Null
    }

    try {
        Write-Log "Cloning repository..." "INFO"
        git clone --depth 1 $repositoryUrl $repositoryPath
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Repository cloned successfully to $repositoryPath" "SUCCESS"
        }
        else {
            Write-Log "Git clone failed with exit code $LASTEXITCODE" "ERROR"
        }
    }
    catch {
        Write-Log "Error cloning repository: $_" "ERROR"
    }
}

function Invoke-InstallTools {
    $BaseRawGitHubURL = "https://raw.githubusercontent.com/Missouri-State-CCDC-Team/mwccdc/refs/heads/main"
    $zenmapUrl = "https://npcap.com/dist/npcap-1.87.exe"
    $wiresharkUrl = "https://2.na.dl.wireshark.org/win64/Wireshark-4.6.4-x64.exe"
    $malwarebytesUrl = "https://data-cdn.mbamupdates.com/web/mb5-setup-consumer/MBSetup.exe"
    $toolsPath = "C:\tools"

    if (-not (Test-Path $toolsPath)) {
        New-Item -ItemType Directory -Path $toolsPath | Out-Null
    }

    function Download-File {
        param(
            [string]$Url,
            [string]$OutputPath
        )

        Write-Log "[*] Downloading $Url"
        try {
            $ProgressPreference = 'SilentlyContinue' # Hide progress bar to speed up download
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
            Write-Log "[+] Saved to $OutputPath"
        }
        catch {
            Write-Log "[-] Failed to download $Url" "ERROR"
        }
    }

    # --- Raw GitHub Scripts ---
    $firefoxScriptUrl     = "$BaseRawGitHubUrl/Windows/firefox-install.ps1"
    $sysinternalsScriptUrl = "$BaseRawGitHubUrl/Windows/first30/sysinternals.ps1"

    $firefoxScriptPath     = Join-Path $toolsPath "firefox-install.ps1"
    $sysinternalsScriptPath = Join-Path $toolsPath "sysinternals.ps1"

    Download-File -Url $firefoxScriptUrl -OutputPath $firefoxScriptPath
    Download-File -Url $sysinternalsScriptUrl -OutputPath $sysinternalsScriptPath

    # --- Zenmap Installer ---
    $zenmapPath = Join-Path $toolsPath "zenmap-setup.exe"

    Download-File -Url $zenmapUrl -OutputPath $zenmapPath

    # --- Wireshark Installer ---
    $wiresharkPath = Join-Path $toolsPath "wireshark-latest-x64.exe"

    Download-File -Url $wiresharkUrl -OutputPath $wiresharkPath

    # --- MalwareBytes Install ---
    $malwareBytesPath = Join-Path $toolsPath "MBSetup.exe"

    Download-File -Url $malwarebytesUrl -OutputPath 
    # --- Script Execution ---
    
    Write-Log "[*] Executing downloaded PowerShell scripts..."
    if (Test-Path $firefoxScriptPath) {
        & $firefoxScriptPath
    }

    if (Test-Path $sysinternalsScriptPath) {
        & $sysinternalsScriptPath
    }

}


function Invoke-ADPasswordChange {
    Write-Host "Current User Password Change" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    
    # Get current user context
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host "Current user: $currentUser" -ForegroundColor Yellow
    
    # Prompt for new password
    Write-Host "Enter new password for your account:" -ForegroundColor Yellow
    $newPassword = Read-Host -AsSecureString
    Write-Host "Confirm new password:" -ForegroundColor Yellow
    $confirmPassword = Read-Host -AsSecureString
    
    # Verify passwords match
    $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($newPassword))
    $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($confirmPassword))
    
    if ($pwd1_text -ne $pwd2_text) {
        Write-Log "Passwords do not match" "ERROR"
        return
    }
    
    try {
        # Change password using net user command
        $username = $currentUser.Split('\')[1]
        net user $username /active:yes
        
        # Use the built-in Windows mechanism to change password
        Write-Log "Changing password for user: $username" "INFO"
        
        # For domain users, use ADSI
        if ($currentUser -like "*\*") {
            $domain = $currentUser.Split('\')[0]
            $user = $currentUser.Split('\')[1]
            
            try {
                $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry
                $searcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
                $searcher.Filter = "(&(objectClass=user)(sAMAccountName=$user))"
                $result = $searcher.FindOne()
                
                if ($result) {
                    $userEntry = $result.GetDirectoryEntry()
                    $userEntry.Invoke("SetPassword", $pwd1_text)
                    $userEntry.CommitChanges()
                    Write-Log "Password changed successfully for $user" "SUCCESS"
                }
            }
            catch {
                Write-Log "Error changing AD password: $_" "ERROR"
            }
        }
    }
    catch {
        Write-Log "Error during password change: $_" "ERROR"
    }
}


function Invoke-AddGlassBreakUser {
    Write-Log "Adding GlassBreak emergency access user..." "INFO"
    
    $username = "GlassBreak"
    $description = "GlassBreak"
    
    # Check if user already exists
    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
        Write-Log "User $username already exists" "WARNING"
        return
    }
    
    # Prompt for password
    Write-Host "Enter password for GlassBreak account:" -ForegroundColor Yellow
    $password1 = Read-Host -AsSecureString
    Write-Host "Confirm password:" -ForegroundColor Yellow
    $password2 = Read-Host -AsSecureString

    # Compare passwords
    $plainPwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1))
    $plainPwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2))
    
    if ($plainPwd1 -ne $plainPwd2) {
        Write-Log "Passwords do not match." "ERROR"
        Write-Host "ERROR: Passwords do not match. Aborting creation." -ForegroundColor Red
        return
    }

    try {
        # Create the user
        New-LocalUser -Name $username `
            -Password $password1 `
            -Description $description `
            -PasswordNeverExpires `
            -UserMayNotChangePassword | Out-Null
        
        Write-Log "Created user $username" "SUCCESS"
        
        # Add to Administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction SilentlyContinue
        Write-Log "Added $username to Administrators group" "SUCCESS"
        
        Write-Host "IMPORTANT: Store the credentials file securely!" -ForegroundColor Red
    }
    catch {
        Write-Log "Error creating GlassBreak user: $_" "ERROR"
    }
}

function Invoke-DisableGuestAccount {
    Write-Log "Disabling Guest account..." "INFO"
    
    try {
        Disable-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
        Write-Log "Guest account disabled" "SUCCESS"
    }
    catch {
        Write-Log "Error disabling Guest account: $_" "ERROR"
    }
}


function Invoke-SetPasswordPolicy {
    Write-Log "Configuring password policy..." "INFO"
    
    try {
        # Get the current security policy
        $tempFile = "$env:TEMP\secedit_export.txt"
        secedit /export /cfg $tempFile /quiet
        
        # Modify password policy settings
        (Get-Content $tempFile) -replace 'PasswordHistorySize = \d+', 'PasswordHistorySize = 24' |
            Set-Content $tempFile
        
        (Get-Content $tempFile) -replace 'MaxPasswordAge = \d+', 'MaxPasswordAge = 42' |
            Set-Content $tempFile
        
        (Get-Content $tempFile) -replace 'MinPasswordAge = \d+', 'MinPasswordAge = 1' |
            Set-Content $tempFile
        
        (Get-Content $tempFile) -replace 'MinPasswordLength = \d+', 'MinPasswordLength = 14' |
            Set-Content $tempFile
        
        (Get-Content $tempFile) -replace 'PasswordComplexity = \d+', 'PasswordComplexity = 1' |
            Set-Content $tempFile
        
        # Apply the new policy
        secedit /configure /db "$env:TEMP\secedit.sdb" /cfg $tempFile /quiet
        
        Write-Log "Password policy configured: Min 14 chars, complexity required, 24 history, 42 day max age" "SUCCESS"
        
        # Cleanup
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Error setting password policy: $_" "ERROR"
    }
}

# ==============================================================================
# Firewall - Lite Configuration
# ==============================================================================
function Invoke-FirewallLite {
    Write-Log "Configuring Firewall - Lite Mode (allow common services)..." "INFO"
    Write-Log "This will only block inbound and not do a full block." "INFO"

    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableScriptScanning $false -EnableControlledFolderAccess Enabled -EnableNetworkProtection Enabled -SubmitSamplesConsent NeverSend -ErrorAction SilentlyContinue
    } catch {}
    
    try {
        # Enable Windows Firewall
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
        Write-Log "Windows Firewall enabled for all profiles" "INFO"
        
        # Inbound rules - allow essential services
        $allowedPorts = @(,
            @{ Port = 443; Protocol = 'TCP'; Name = 'HTTPS' },
            @{ Port = 80; Protocol = 'TCP'; Name = 'HTTP' },
            @{ Port = 53; Protocol = 'UDP'; Name = 'DNS' },
            @{ Port = 123; Protocol = 'UDP'; Name = 'NTP' }
        )
        
        foreach ($rule in $allowedPorts) {
            $existingRule = Get-NetFirewallRule -DisplayName "Allow $($rule.Name)" -ErrorAction SilentlyContinue
            if (-not $existingRule) {
                New-NetFirewallRule -DisplayName "Allow $($rule.Name)" `
                    -Direction Inbound `
                    -Action Allow `
                    -Protocol $rule.Protocol `
                    -LocalPort $rule.Port | Out-Null
                Write-Log "Added firewall rule for $($rule.Name) (port $($rule.Port)/$($rule.Protocol))" "INFO"
            }
        }
        
        Write-Log "Firewall Lite configuration complete" "SUCCESS"
    }
    catch {
        Write-Log "Error configuring Firewall Lite: $_" "ERROR"
    }
}


function Invoke-FirewallAggressive {
    Write-Log "Configuring Firewall - Aggressive Mode (deny-all + whitelist)..." "INFO"

    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableScriptScanning $false -EnableControlledFolderAccess Enabled -EnableNetworkProtection Enabled -SubmitSamplesConsent NeverSend -ErrorAction SilentlyContinue
    } catch {}
    
    try {
        # Enable Windows Firewall with default deny
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True `
            -DefaultInboundAction Block `
            -DefaultOutboundAction Allow
        
        Write-Log "Firewall set to block all inbound by default" "INFO"
        
        # Define whitelist of allowed services
        $allowedServices = @(
            # HTTP/HTTPS
            @{ Port = 80;        Protocol = 'TCP'; Name = 'HTTP';                    Direction = 'Inbound'  },
            @{ Port = 443;       Protocol = 'TCP'; Name = 'HTTPS';                   Direction = 'Inbound'  },

            # DNS
            @{ Port = 53;        Protocol = 'TCP'; Name = 'DNS TCP Inbound';         Direction = 'Inbound'  },
            @{ Port = 53;        Protocol = 'TCP'; Name = 'DNS TCP Outbound';        Direction = 'Outbound' },
            @{ Port = 53;        Protocol = 'UDP'; Name = 'DNS UDP Inbound';         Direction = 'Inbound'  },
            @{ Port = 53;        Protocol = 'UDP'; Name = 'DNS UDP Outbound';        Direction = 'Outbound' },

            # Kerberos
            @{ Port = 88;        Protocol = 'TCP'; Name = 'Kerberos TCP Inbound';    Direction = 'Inbound'  },
            @{ Port = 88;        Protocol = 'TCP'; Name = 'Kerberos TCP Outbound';   Direction = 'Outbound' },
            @{ Port = 88;        Protocol = 'UDP'; Name = 'Kerberos UDP Inbound';    Direction = 'Inbound'  },
            @{ Port = 88;        Protocol = 'UDP'; Name = 'Kerberos UDP Outbound';   Direction = 'Outbound' },

            # Kerberos Password Change
            @{ Port = 464;       Protocol = 'TCP'; Name = 'KerberosPW TCP Inbound';  Direction = 'Inbound'  },
            @{ Port = 464;       Protocol = 'TCP'; Name = 'KerberosPW TCP Outbound'; Direction = 'Outbound' },
            @{ Port = 464;       Protocol = 'UDP'; Name = 'KerberosPW UDP Inbound';  Direction = 'Inbound'  },
            @{ Port = 464;       Protocol = 'UDP'; Name = 'KerberosPW UDP Outbound'; Direction = 'Outbound' },

            # LDAP
            @{ Port = 389;       Protocol = 'TCP'; Name = 'LDAP TCP Inbound';        Direction = 'Inbound'  },
            @{ Port = 389;       Protocol = 'TCP'; Name = 'LDAP TCP Outbound';       Direction = 'Outbound' },
            @{ Port = 389;       Protocol = 'UDP'; Name = 'LDAP UDP Inbound';        Direction = 'Inbound'  },
            @{ Port = 389;       Protocol = 'UDP'; Name = 'LDAP UDP Outbound';       Direction = 'Outbound' },

            # LDAPS
            @{ Port = 636;       Protocol = 'TCP'; Name = 'LDAPS TCP Inbound';       Direction = 'Inbound'  },
            @{ Port = 636;       Protocol = 'TCP'; Name = 'LDAPS TCP Outbound';      Direction = 'Outbound' },

            # SMB (SYSVOL/NETLOGON)
            @{ Port = 445;       Protocol = 'TCP'; Name = 'SMB TCP Inbound';         Direction = 'Inbound'  },
            @{ Port = 445;       Protocol = 'TCP'; Name = 'SMB TCP Outbound';        Direction = 'Outbound' },

            # RPC Endpoint Mapper
            @{ Port = 135;       Protocol = 'TCP'; Name = 'RPC TCP Inbound';         Direction = 'Inbound'  },
            @{ Port = 135;       Protocol = 'TCP'; Name = 'RPC TCP Outbound';        Direction = 'Outbound' },

            # RPC Dynamic Range (restricted)
            @{ Port = '5000-5100'; Protocol = 'TCP'; Name = 'RPC Dynamic Inbound';  Direction = 'Inbound'  },
            @{ Port = '5000-5100'; Protocol = 'TCP'; Name = 'RPC Dynamic Outbound'; Direction = 'Outbound' },

            # NTP / Time Sync
            @{ Port = 123;       Protocol = 'UDP'; Name = 'NTP UDP Inbound';         Direction = 'Inbound'  },
            @{ Port = 123;       Protocol = 'UDP'; Name = 'NTP UDP Outbound';        Direction = 'Outbound' }
        )

        foreach ($rule in $allowedServices) {
            $existingRule = Get-NetFirewallRule -DisplayName "Aggressive Allow $($rule.Name)" -ErrorAction SilentlyContinue
            if (-not $existingRule) {
                New-NetFirewallRule -DisplayName "Aggressive Allow $($rule.Name)" `
                    -Direction $rule.Direction `
                    -Action Allow `
                    -Protocol $rule.Protocol `
                    -LocalPort $rule.Port | Out-Null
                Write-Log "Added aggressive whitelist rule for $($rule.Name)" "INFO"
            }
        }

        # ── BLOCK RULES ──────────────────────────────────────────────────────
        $blockRules = @(
            @{ Port = 137; Protocol = 'UDP'; Name = 'Block NetBIOS UDP 137' },
            @{ Port = 138; Protocol = 'UDP'; Name = 'Block NetBIOS UDP 138' },
            @{ Port = 139; Protocol = 'TCP'; Name = 'Block NetBIOS TCP 139' }
        )

            foreach ($rule in $blockRules) {
            $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-NetFirewallRule -DisplayName $rule.Name `
                    -Direction Inbound `
                    -Action Block `
                    -Protocol $rule.Protocol `
                    -LocalPort $rule.Port `
                    -Enabled True | Out-Null
                Write-Log "Added block rule: $($rule.Name)" "INFO"
            }
        }

        # ── ICMP ─────────────────────────────────────────────────────────────
        foreach ($direction in @('Inbound', 'Outbound')) {
            $ruleName = "Aggressive Allow ICMPv4 $direction"
            $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-NetFirewallRule -DisplayName $ruleName `
                    -Protocol ICMPv4 `
                    -Direction $direction `
                    -Action Allow `
                    -Enabled True | Out-Null
                Write-Log "Added rule: $ruleName" "INFO"
            }
        }
        
        Write-Log "Firewall Aggressive configuration complete" "SUCCESS"
    }
    catch {
        Write-Log "Error configuring Firewall Aggressive: $_" "ERROR"
    }
}

function Invoke-BlockIP {
    Write-Log "Starting Block IP Menu"
    try {
        $IPAddress = Read-Host " Enter IP Address to Block"
        # Validate IP format
        if (-not [System.Net.IPAddress]::TryParse($IPAddress, [ref]$null)) {
            Write-Log "Invalid IP address format: $IPAddress" "ERROR"
            return
        }

        $ruleName = "BLOCK_INBOUND_$IPAddress"

        # Check if rule already exists
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "Block rule for $IPAddress already exists, skipping" "INFO"
            return
        }

        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction Inbound `
            -Action Block `
            -RemoteAddress $IPAddress `
            -Protocol Any `
            -Enabled True | Out-Null

        Write-Log "Successfully blocked inbound traffic from $IPAddress" "SUCCESS"
    }
    catch {
        Write-Log "Error blocking IP: $_" "ERROR"
    }
}


function Invoke-HardenSMB {
    Write-Log "Hardening SMB protocol..." "INFO"
    try {
        # Disable SMB v1
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue
        Write-Log "Disabled SMB v1" "SUCCESS"

        # Enable SMBv2 with security
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name SMB2 -Type DWORD -Value 1 -Force
        
        # Enable SMB encryption
        Set-SmbServerConfiguration -EncryptData $true -Force
        Write-Log "Enabled SMB encryption" "SUCCESS"
        
        # Require SMB signing for client and server
        Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
        Write-Log "Enabled SMB signing requirement" "SUCCESS"
        
        # Client-side hardening
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
            -Name RequireSecuritySignature -Value 1
        
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
            -Name EnableSecuritySignature -Value 1
        
        Write-Log "SMB hardening complete" "SUCCESS"
    }
    catch {
        Write-Log "Error hardening SMB: $_" "ERROR"
    }
}

# ==============================================================================
# Block Remote Management
# ==============================================================================
function Invoke-DisableRM {
    # 1. Back up current configurations
    try {
        $backupDir = "C:\Backup\SecurityConfig"
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        
        # Backup firewall rules
        $firewallBackup = "$backupDir\FirewallRules_$(Get-Date -Format 'yyyyMMdd_HHmmss').wfw"
        netsh advfirewall export "$firewallBackup"
        Write-Log "Firewall rules backed up to $firewallBackup" "SUCCESS"
        
        # Backup service states
        $serviceBackup = "$backupDir\Services_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        Get-Service | Select-Object Name, Status, StartType | Export-Csv -Path $serviceBackup -NoTypeInformation
        Write-Log "Service states backed up to $serviceBackup" "SUCCESS"
    }
    catch {
        Write-Log "Failed to complete backups: $_" "WARNING"
    }
    # 2. Disable RDP via Registry and servies
    try { 
        Write-Log "Disabling Remote Desktop Protocol (RDP)" "INFO"

        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fDenyTSConnections /t REG_DWORD /d 1 /f

        get-service -Name "TermService" | Stop-Service -Force
        Set-Service -Name "TermService" -StartupType Disabled
    }
    catch {
        Write-Log "Failed to disable RDP: $_" "ERROR"
    }
    # 3. Disable PowerShell Remoting
    try { 
        Write-Log "Disabling PowerShell Remoting" "INFO"
        Disable-PSRemoting -Force -ErrorAction SilentlyContinue
        Write-Log "PowerShell Remoting disabled successfully" "SUCCESS"
    }
    catch { 
        Write-Log "Failed to disable PowerShell Remoting: $_" "ERROR"
    }
    $servicesToDisable = @(
        # Remote Desktop
        "TermService",
        "SessionEnv", 
        "UmRdpService",
        # Remote Management
        "RemoteRegistry",
        "WinRM",
        "RemoteAccess",
        # SSH (Windows 10/Server 2019+)
        "sshd",
        "ssh-agent"
    )

    foreach ($service in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                $status = (Get-Service -Name $service -ErrorAction SilentlyContinue).Status
                Write-Log "Service $service disabled - Status: $status" "SUCCESS"
            }
        }
        catch {
            Write-Log "Error processing service ${service}: $_" "WARNING"
        }
    }

    # Disable remote assistance
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowFullControl" -Value 0 -ErrorAction SilentlyContinue
        Write-Log "Remote Assistance disabled" "SUCCESS"
    }
    catch {
        Write-Log "Failed to disable Remote Assistance: $_" "ERROR"
    }

    # Disable WMI fireall rules 
    try { 
        Write-Log "Disabling WMI firewall rules" "INFO"
        netsh advfirewall firewall set rule group="windows management instrumentation (wmi)" new enable=no
    }
    catch { 
        write-Log "Failed to disable WMI firewall rules: $_" "ERROR"
    }

    # Disable common third-party remote tools
    $remoteTools = @("TeamViewer*", "AnyDesk*", "LogMeIn*", "Chrome Remote*", "VNC*", "Splashtop*")
    foreach ($tool in $remoteTools) {
        Get-Service -Name $tool -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
        Get-Service -Name $tool -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
        Get-Process -Name $tool.Replace("*","") -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Write-Log "All specified remote management services have been disabled." "SUCCESS"
}


# ==============================================================================
# IMPLEMENTATION: Harden WMI
# ==============================================================================
function Invoke-HardenWMI {
    Write-Log "Hardening WMI (Windows Management Instrumentation)..." "INFO"
    try {
        # Disable unnecessary WMI access
        $wmiPath = "HKLM:\System\CurrentControlSet\Services\Winmgmt"
        # Restrict WMI access to administrators
        icacls "$env:SystemRoot\System32\wbem" /inheritance:r /grant:r "BUILTIN\Administrators:(OI)(CI)F" /T /C
        Write-Log "Restricted WMI directory permissions" "SUCCESS"
        # Disable WMI service if not needed (optional - comment out if required)
        # Set-Service -Name Winmgmt -StartupType Disabled   
        Write-Log "WMI hardening complete" "SUCCESS"
    }
    catch {
        Write-Log "Error hardening WMI: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Harden LSASS (Local Security Authority Subsystem Service)
# ==============================================================================
function Invoke-HardenLSASS {
    Write-Log "Hardening LSASS (Credential Guard)..." "INFO"
    
    try {
        # Enable Windows Defender Credential Guard
        $path = "HKLM:\System\CurrentControlSet\Control\Lsa"
        
        Set-ItemProperty -Path $path -Name LsaCfgFlags -Value 1
        Write-Log "Enabled Credential Guard (LSASS Protection)" "SUCCESS"
        
        # Run LSASS as Protected Process
        Set-ItemProperty -Path $path -Name RunAsPPL -Value 1
        Write-Log "Enabled LSASS Protected Process Light" "SUCCESS"
        
        Write-Log "LSASS hardening complete" "SUCCESS"
    }
    catch {
        Write-Log "Error hardening LSASS: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Configure UAC
# ==============================================================================
function Invoke-ConfigureUAC {
    Write-Log "Configuring User Account Control (UAC)..." "INFO"
    
    try {
        $UACPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        
        # Enable UAC
        Set-ItemProperty -Path $UACPath -Name EnableLUA -Value 1
        Write-Log "Enabled UAC" "SUCCESS"
        
        # Set UAC to always prompt (ConsentPromptBehaviorAdmin = 2: Prompt for credentials on secure desktop)
        Set-ItemProperty -Path $UACPath -Name ConsentPromptBehaviorAdmin -Value 2
        Write-Log "Set UAC to always prompt for admin actions" "SUCCESS"
        
        # Require secure desktop for UAC prompts
        Set-ItemProperty -Path $UACPath -Name PromptOnSecureDesktop -Value 1
        Write-Log "Enabled secure desktop for UAC" "SUCCESS"
        
        # Virtualize file and registry failures
        Set-ItemProperty -Path $UACPath -Name EnableVirtualization -Value 1
        Write-Log "Enabled file/registry virtualization" "SUCCESS"
        
        Write-Log "UAC configuration complete" "SUCCESS"
    }
    catch {
        Write-Log "Error configuring UAC: $_" "ERROR"
    }
}


function Invoke-ApplyHardenedGPO {
    Write-Log "Applying hardened Group Policy to domain..." "INFO"

    try {
        # Verify RSAT GroupPolicy module is available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Write-Log "GroupPolicy module not found. Install RSAT: Add-WindowsFeature GPMC" "ERROR"
            return
        }

        Import-Module GroupPolicy

        # Detect domain automatically
        $domain = (Get-ADDomain).DistinguishedName
        $domainFQDN = (Get-ADDomain).DNSRoot
        Write-Log "Targeting domain: $domainFQDN ($domain)" "INFO"

        $gpoName = "Archimedes-Hardening"

        # Check if GPO already exists
        $existingGPO = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if ($existingGPO) {
            Write-Log "GPO '$gpoName' already exists - updating in place" "INFO"
        } else {
            New-GPO -Name $gpoName -Comment "Applied by Archimedes hardening script" | Out-Null
            Write-Log "Created GPO: $gpoName" "SUCCESS"
        }

        # Link GPO to domain root if not already linked
        $existingLink = Get-GPInheritance -Target $domain |
            Select-Object -ExpandProperty GpoLinks |
            Where-Object { $_.DisplayName -eq $gpoName }

        if (-not $existingLink) {
            New-GPLink -Name $gpoName -Target $domain -Enforced Yes | Out-Null
            Write-Log "Linked GPO to domain root (Enforced)" "SUCCESS"
        } else {
            Write-Log "GPO already linked to domain root" "INFO"
        }

        # ── HELPER ───────────────────────────────────────────────────────────
        function Set-GPReg {
            param($Key, $ValueName, $Value, $Type = "DWord")
            Set-GPRegistryValue -Name $gpoName `
                -Key $Key `
                -ValueName $ValueName `
                -Type $Type `
                -Value $Value | Out-Null
        }

        # ════════════════════════════════════════════════════════════════════════
        # DISABLE REMOTE ACCESS
        # ════════════════════════════════════════════════════════════════════════
        Write-Log "Disabling all remote access..." "INFO"
        # RDP
        Set-GPReg "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1
        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" "fDenyTSConnections" 1
        # WinRM
        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowAutoConfig" 0
        # Remote Registry
        Set-GPReg "HKLM\SYSTEM\CurrentControlSet\Services\RemoteRegistry" "Start" 4  # Disabled
        # Remote Assistance
        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" "fAllowToGetHelp"     0
        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" "fAllowUnsolicited"   0
        # SMB 
        Set-GPReg "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "AutoShareWks"    0
        Set-GPReg "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "AutoShareServer" 0
        Write-Log "All remote access disabled" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 1. WINDOWS FIREWALL (CIS 9.1 - 9.3)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Firewall policy..." "INFO"

        foreach ($profile in @("DomainProfile", "PrivateProfile", "PublicProfile")) {
            $key = "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\$profile"
            Set-GPReg $key "EnableFirewall"         1
            Set-GPReg $key "DefaultInboundAction"   1
            Set-GPReg $key "DefaultOutboundAction"  0
        }

        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile" "DisableNotifications" 1
        Write-Log "Firewall policy configured" "SUCCESS"
        # ════════════════════════════════════════════════════════════════════
        # 2. WINDOWS DEFENDER (CIS 18.9.47)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Defender policy..." "INFO"
        $def = "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender"
        Set-GPReg "$def"                                                                        "DisableAntiSpyware"        0
        Set-GPReg "$def"                                                                        "ServiceKeepAlive"          1
        Set-GPReg "$def\Real-Time Protection"                                                   "DisableRealtimeMonitoring" 0
        Set-GPReg "$def\Real-Time Protection"                                                   "DisableBehaviorMonitoring" 0
        Set-GPReg "$def\Real-Time Protection"                                                   "DisableIOAVProtection"     0
        Set-GPReg "$def\Spynet"                                                                 "SpynetReporting"           2
        Set-GPReg "$def\Spynet"                                                                 "SubmitSamplesConsent"      1
        Set-GPReg "$def\MpEngine"                                                               "MpCloudBlockLevel"         2
        Set-GPReg "$def\Windows Defender Exploit Guard\Network Protection"                      "EnableNetworkProtection"   1
        Set-GPReg "$def\UX Configuration"                                                       "UILockdown"                0
        Set-GPReg "$def\UX Configuration"                                                       "Notification_Suppress"     0
        Write-Log "Defender policy configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 3. ACCOUNT / PASSWORD POLICY (CIS 1.1 - 1.2)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Account policy..." "INFO"

        # Account policy lives in the Default Domain Policy per Microsoft spec
        # Set-GPRegistryValue doesn't cover secedit-style settings
        # so we use secedit + a temp INF applied via the GPO's SYSVOL path

        $passwordINF = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 60
MinimumPasswordLength = 14
PasswordComplexity = 1
PasswordHistorySize = 24
LockoutBadCount = 5
ResetLockoutCount = 15
LockoutDuration = 15
"@
        $infPath = "$env:TEMP\archimedes_password.inf"
        $passwordINF | Set-Content -Path $infPath -Encoding Unicode

        $gpoID = (Get-GPO -Name $gpoName).Id.ToString("B").ToUpper()
        $sysvolPath = "\\$domainFQDN\SYSVOL\$domainFQDN\Policies\$gpoID\Machine\Microsoft\Windows NT\SecEdit"

        if (-not (Test-Path $sysvolPath)) {
            New-Item -Path $sysvolPath -ItemType Directory -Force | Out-Null
        }

        Copy-Item $infPath "$sysvolPath\GptTmpl.inf" -Force
        Remove-Item $infPath -Force -ErrorAction SilentlyContinue
        Write-Log "Account/Password policy configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 4. AUDIT POLICY (CIS 17.x)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Audit policy..." "INFO"
        $auditKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\Audit"
        $auditSettings = @{
            "AuditAccountLogon"     = 3  # Success + Failure
            "AuditAccountManage"    = 3
            "AuditLogon"            = 3
            "AuditObjectAccess"     = 2  # Failure only
            "AuditPolicyChange"     = 3
            "AuditPrivilegeUse"     = 2
            "AuditSystemEvents"     = 3
            "AuditDSAccess"         = 3
            "AuditProcessTracking"  = 2
        }
        foreach ($setting in $auditSettings.GetEnumerator()) {
            Set-GPReg $auditKey $setting.Key $setting.Value
        }

        Write-Log "Audit policy configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 5. SECURITY OPTIONS (CIS 2.3)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Security Options..." "INFO"
        $sysKey = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $lsaKey = "HKLM\SYSTEM\CurrentControlSet\Control\Lsa"
        # UAC
        Set-GPReg $sysKey "EnableLUA"                       1
        Set-GPReg $sysKey "ConsentPromptBehaviorAdmin"      2
        Set-GPReg $sysKey "ConsentPromptBehaviorUser"       0
        Set-GPReg $sysKey "EnableVirtualization"            1
        Set-GPReg $sysKey "NoConnectedUser"                 3
        # Interactive Logon
        Set-GPReg $sysKey "DontDisplayLastUserName"         1
        Set-GPReg $sysKey "InactivityTimeoutSecs"           900
        # LSA / NTLM
        Set-GPReg $lsaKey "LmCompatibilityLevel"            5  # NTLMv2 only
        Set-GPReg $lsaKey "NTLMMinClientSec"                537395200
        Set-GPReg $lsaKey "NTLMMinServerSec"                537395200
        Set-GPReg $lsaKey "RestrictAnonymous"               2
        Set-GPReg $lsaKey "RestrictAnonymousSAM"            1
        Set-GPReg $lsaKey "DisableDomainCreds"              1
        Set-GPReg $lsaKey "EveryoneIncludesAnonymous"       0
        Set-GPReg $lsaKey "LimitBlankPasswordUse"           1
        Write-Log "Security Options configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 6. REMOTE ACCESS (CIS 18.9.x)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Remote Access policy..." "INFO"

        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowUnencryptedTraffic" 0
        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowUnencryptedTraffic"  0
        Set-GPReg "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowBasic"               0

        $rdpKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
        Set-GPReg $rdpKey "fEncryptionEnabled"  1
        Set-GPReg $rdpKey "MinEncryptionLevel"  3
        Set-GPReg $rdpKey "fDisableCdm"         1
        Set-GPReg $rdpKey "fPromptForPassword"  1

        Write-Log "Remote Access policy configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 7. ATTACK SURFACE REDUCTION (CIS 18.9.47.4)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring ASR Rules..." "INFO"

        $asrKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"

        $asrRules = @{
            "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550" = 1
            "d4f940ab-401b-4efc-aadc-ad5f3c50688a" = 1
            "3b576869-a4ec-4529-8536-b80a7769e899" = 1
            "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84" = 1
            "d3e037e1-3eb8-44c8-a917-57927947596d" = 1
            "5beb7efe-fd9a-4556-801d-275e5ffc04cc" = 1
            "92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b" = 1
            "01443614-cd74-433a-b99e-2ecdc07bfc25" = 1
            "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b0" = 1
            "e6db77e5-3df2-4cf1-b95a-636979351e5b" = 1
        }

        foreach ($rule in $asrRules.GetEnumerator()) {
            Set-GPReg $asrKey $rule.Key $rule.Value
        }

        Write-Log "ASR Rules configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # 8. WINDOWS UPDATE (CIS 18.9.108)
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Configuring Windows Update policy..." "INFO"

        $wuKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Set-GPReg $wuKey "NoAutoUpdate"             0
        Set-GPReg $wuKey "AUOptions"                4
        Set-GPReg $wuKey "AutoInstallMinorUpdates"  1

        Write-Log "Windows Update policy configured" "SUCCESS"

        # ════════════════════════════════════════════════════════════════════
        # GPUPDATE
        # ════════════════════════════════════════════════════════════════════
        Write-Log "Forcing Group Policy update on local machine..." "INFO"
        gpupdate /force | Out-Null

        Write-Log "Hardened GPO '$gpoName' applied and linked to $domainFQDN" "SUCCESS"
        Write-Log "Remote machines will receive policy at next GP refresh (~90 min) or run 'gpupdate /force' remotely" "INFO"
    }
    catch {
        Write-Log "Error applying hardened GPO: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Enable ASLR and DEP
# ==============================================================================
function Invoke-EnableASLRDEP {
    Write-Log "Enabling ASLR (Address Space Layout Randomization) and DEP..." "INFO"
    
    try {
        # Enable DEP (Data Execution Prevention) for all processes except those listed
        bcdedit /set nx AlwaysOn
        Write-Log "Enabled DEP (Data Execution Prevention)" "SUCCESS"
        
        # Enable ASLR via registry
        $path = "HKLM:\System\CurrentControlSet\Control\Session Manager\Memory Management"
        Set-ItemProperty -Path $path -Name MoveImages -Value 1
        Write-Log "Enabled ASLR via registry" "SUCCESS"
        
        Write-Log "ASLR and DEP configuration complete" "SUCCESS"
    }
    catch {
        Write-Log "Error enabling ASLR/DEP: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Disable Unnecessary Services
# ==============================================================================
function Invoke-DisableServices {
    Write-Log "Disabling unnecessary services..." "INFO"
    
    try {
        $servicesToDisable = @(
            "DiagTrack",           # Connected User Experiences and Telemetry
            "dmwappushservice",    # dmwappushservice
            "HomeGroupListener",   # HomeGroup Listener
            "HomeGroupProvider",   # HomeGroup Provider
            "lmhosts",             # TCP/IP NetBIOS Helper
            "RemoteAccess",        # Routing and Remote Access
            "RemoteRegistry",      # Remote Registry
            "SharedAccess",        # Internet Connection Sharing (ICS)
            "XblAuthManager",      # Xbox Live Auth Manager
            "XblGameSave",         # Xbox Live Game Save
            "xbgm",                # Xbox Game Monitoring
            "MsSecondaryAuthFactor"# Microsoft Account Secondary Authentication Factor
        )
        
        foreach ($service in $servicesToDisable) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc) {
                    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                    Write-Log "Disabled service: $service" "INFO"
                }
            }
            catch {
                Write-Log "Could not disable $service : $_" "WARNING"
            }
        }
        
        Write-Log "Service disabling complete" "SUCCESS"
    }
    catch {
        Write-Log "Error disabling services: $_" "ERROR"
    }
}

function Invoke-DisableLegacyProtocols {
    Write-Log "Disabling legacy protocols..." "INFO"
    
    try {
        # Disable SSL 2.0
        $ssl2Path = "HKLM:\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server"
        if (-not (Test-Path $ssl2Path)) {
            New-Item -Path $ssl2Path -Force | Out-Null
        }
        Set-ItemProperty -Path $ssl2Path -Name Enabled -Value 0
        Write-Log "Disabled SSL 2.0" "SUCCESS"
        
        # Disable SSL 3.0
        $ssl3Path = "HKLM:\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server"
        if (-not (Test-Path $ssl3Path)) {
            New-Item -Path $ssl3Path -Force | Out-Null
        }
        Set-ItemProperty -Path $ssl3Path -Name Enabled -Value 0
        Write-Log "Disabled SSL 3.0" "SUCCESS"
        
        # Disable TLS 1.0 (legacy)
        $tls10Path = "HKLM:\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server"
        if (-not (Test-Path $tls10Path)) {
            New-Item -Path $tls10Path -Force | Out-Null
        }
        Set-ItemProperty -Path $tls10Path -Name Enabled -Value 0
        Write-Log "Disabled TLS 1.0" "SUCCESS"
        
        Write-Log "Legacy protocol disabling complete" "SUCCESS"
    }
    catch {
        Write-Log "Error disabling legacy protocols: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Disable NetBIOS
# ==============================================================================
function Invoke-DisableNetBIOS {
    Write-Log "Disabling NetBIOS over TCP/IP..." "INFO"
    
    try {
        # Get network adapters
        $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
        
        foreach ($adapter in $adapters) {
            # Disable NetBIOS: 2 = Disabled
            $adapter.SetTcpipNetbios(2) | Out-Null
            Write-Log "Disabled NetBIOS on adapter: $($adapter.Description)" "INFO"
        }
        
        Write-Log "NetBIOS disabling complete" "SUCCESS"
    }
    catch {
        Write-Log "Error disabling NetBIOS: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Disable LLMNR
# ==============================================================================
function Invoke-DisableLLMNR {
    Write-Log "Disabling LLMNR (Link-Local Multicast Name Resolution)..." "INFO"
    
    try {
        # Disable LLMNR via registry
        $path = "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient"
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name EnableMulticast -Value 0
        Write-Log "Disabled LLMNR" "SUCCESS"
    }
    catch {
        Write-Log "Error disabling LLMNR: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Clear Persistence
# ==============================================================================
function Invoke-ClearPersistence {
    Write-Log "Clearing persistence mechanisms..." "INFO"
    
    try {
        # Clear Run key
        $runPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
        )
        
        foreach ($path in $runPaths) {
            if (Test-Path $path) {
                (Get-Item -Path $path).Property | 
                    Where-Object { $_.Name -notlike "PS*" } | 
                    ForEach-Object {
                        Remove-ItemProperty -Path $path -Name $_.Name -ErrorAction SilentlyContinue
                        Write-Log "Removed persistence entry: $($_.Name)" "INFO"
                    }
            }
        }
        
        # Clear Startup folder
        $startupPaths = @(
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        )
        
        foreach ($path in $startupPaths) {
            if (Test-Path $path) {
                Get-ChildItem -Path $path -File | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log "Cleared startup folder: $path" "INFO"
            }
        }
        
        Write-Log "Persistence clearing complete" "SUCCESS"
    }
    catch {
        Write-Log "Error clearing persistence: $_" "ERROR"
    }
}

function Invoke-ClearKerberosTickets {
    Write-Log "Clearing Kerberos tickets..." "INFO"

    try {
        $confirm = Read-Host "  Purge ALL Kerberos tickets? This will require re-authentication (y/n)"
        
        if ($confirm -ne "y") {
            Write-Log "Kerberos ticket purge cancelled" "INFO"
            return
        }

        # Capture current tickets for audit log before purging
        $ticketsBefore = klist 2>&1
        $ticketCount = ($ticketsBefore | Select-String "Server:").Count
        Write-Log "Found $ticketCount ticket(s) before purge" "INFO"

        # Purge all tickets for current session
        klist purge | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Log "klist purge returned non-zero exit code" "ERROR"
            return
        }

        # Verify purge was successful
        $ticketsAfter = klist 2>&1
        $remainingCount = ($ticketsAfter | Select-String "Server:").Count

        if ($remainingCount -eq 0) {
            Write-Log "Successfully purged all $ticketCount Kerberos ticket(s)" "SUCCESS"
        } else {
            Write-Log "Purge may be incomplete - $remainingCount ticket(s) still present" "ERROR"
        }

    }
    catch {
        Write-Log "Error clearing Kerberos tickets: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Backdoor Hunt
# ==============================================================================
function Invoke-BackdoorHunt {
    Write-Log "Scanning for common backdoors and indicators..." "INFO"
    
    Write-Host ""
    Write-Host "Backdoor Hunt Results" -ForegroundColor Cyan
    Write-Host "=====================" -ForegroundColor Cyan
    
    try {
        # Check for suspicious services
        Write-Host ""
        Write-Host "Checking for suspicious services..." -ForegroundColor Yellow
        $suspiciousServices = Get-Service | 
            Where-Object { $_.DisplayName -match '(remote|back|rat|shell|reverse|proxy)' -and $_.Status -eq 'Running' }
        
        if ($suspiciousServices) {
            Write-Host "[!] Found potentially suspicious services:" -ForegroundColor Red
            foreach ($svc in $suspiciousServices) {
                Write-Host "  - $($svc.Name): $($svc.DisplayName)" -ForegroundColor Yellow
                Write-Log "Suspicious service found: $($svc.Name)" "WARNING"
            }
        }
        else {
            Write-Host "[+] No obvious suspicious services found" -ForegroundColor Green
        }
        
        # Check running processes
        Write-Host ""
        Write-Host "Checking for suspicious processes..." -ForegroundColor Yellow
        $suspiciousProcesses = Get-Process | 
            Where-Object { $_.ProcessName -match '(cmd|powershell|ncat|nc|reverse)' -and $_.ProcessName -ne 'csrss' }
        
        if ($suspiciousProcesses) {
            Write-Host "[!] Found processes of interest:" -ForegroundColor Yellow
            foreach ($proc in $suspiciousProcesses) {
                Write-Host "  - $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Yellow
            }
        }
        
        # Check scheduled tasks
        Write-Host ""
        Write-Host "Checking for suspicious scheduled tasks..." -ForegroundColor Yellow
        $tasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' }
        $suspiciousTasks = $tasks | Where-Object { 
            $_.TaskName -match '(update|download|sync|backup)' -and 
            $_.Author -notmatch '(Microsoft|Windows)'
        }
        
        if ($suspiciousTasks) {
            Write-Host "[!] Found potentially suspicious tasks:" -ForegroundColor Red
            foreach ($task in $suspiciousTasks) {
                Write-Host "  - $($task.TaskName)" -ForegroundColor Yellow
                Write-Log "Suspicious task found: $($task.TaskName)" "WARNING"
            }
        }
        else {
            Write-Host "[+] No obvious suspicious scheduled tasks found" -ForegroundColor Green
        }
        
        # Check for open ports
        Write-Host ""
        Write-Host "Checking for listening ports..." -ForegroundColor Yellow
        $listeningPorts = Get-NetTCPConnection -State Listen | Select-Object LocalPort, @{Name='ProcessName';Expression={(Get-Process -Id $_.OwningProcess).ProcessName}}
        Write-Host "[*] Listening ports:" -ForegroundColor Cyan
        foreach ($port in $listeningPorts) {
            Write-Host "  - Port $($port.LocalPort): $($port.ProcessName)" -ForegroundColor Gray
        }
        
        Write-Log "Backdoor hunt complete" "SUCCESS"
    }
    catch {
        Write-Log "Error during backdoor hunt: $_" "ERROR"
    }
}

function Invoke-HuntKerberosTickets {
    Write-Log "Hunting for suspicious Kerberos tickets..." "INFO"

    try {
        $tickets = klist 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to retrieve Kerberos tickets" "ERROR"
            return
        }

        $suspiciousFlags = @(
            "forwardable",
            "forwarded",
            "renewable",
            "pre_authent"
        )

        # Golden ticket indicators
        $goldenTicketTTL = 10  # Hours - default golden ticket lifetime is 10+ years, catch abnormally high values
        $suspiciousFound = $false

        $currentTicket = @()
        foreach ($line in $tickets) {
            $currentTicket += $line

            # Parse each ticket block
            if ($line -match "KerbTicket Encryption Type:\s+(.+)") {
                $encType = $matches[1].Trim()

                # RC4 is a golden ticket indicator - modern environments should use AES
                if ($encType -match "RSADSI RC4") {
                    Write-Log "WARNING: RC4 encrypted ticket detected (golden ticket indicator): $encType" "ERROR"
                    $suspiciousFound = $true
                }
            }

            if ($line -match "End Time:\s+(.+)") {
                try {
                    $endTime = [datetime]::Parse($matches[1].Trim())
                    $hoursRemaining = ($endTime - (Get-Date)).TotalHours

                    # Abnormally long ticket lifetime = golden ticket
                    if ($hoursRemaining -gt ($goldenTicketTTL * 24 * 365)) {
                        Write-Log "WARNING: Ticket with abnormally long lifetime detected ($([math]::Round($hoursRemaining / 8760, 1)) years)" "ERROR"
                        $suspiciousFound = $true
                    }
                } catch {}
            }

            if ($line -match "Server:\s+krbtgt/(.+)") {
                $domain = $matches[1].Trim()
                Write-Log "TGT found for domain: $domain" "INFO"
            }

            # Flag suspicious ticket flags
            foreach ($flag in $suspiciousFlags) {
                if ($line -match $flag) {
                    Write-Log "Ticket flag noted: $flag" "INFO"
                }
            }
        }

        # Check for tickets from unexpected domains (cross-realm = potential pass-the-ticket)
        $domains = ($tickets | Select-String "Server:.*@(.+)" | ForEach-Object {
            $_.Matches.Groups[1].Value
        } | Sort-Object -Unique)

        if ($domains.Count -gt 1) {
            Write-Log "WARNING: Tickets from multiple domains detected - possible pass-the-ticket:" "ERROR"
            $domains | ForEach-Object { Write-Log "  Domain: $_" "ERROR" }
            $suspiciousFound = $true
        }

        if ($suspiciousFound) {
            Write-Log "Suspicious Kerberos activity detected - consider running klist purge" "ERROR"
            $purge = Read-Host "  Purge all Kerberos tickets now? (y/n)"
            if ($purge -eq "y") {
                klist purge | Out-Null
                Write-Log "All Kerberos tickets purged" "SUCCESS"
            }
        } else {
            Write-Log "No obvious suspicious Kerberos tickets found" "SUCCESS"
        }

    }
    catch {
        Write-Log "Error hunting Kerberos tickets: $_" "ERROR"
    }
}

function Invoke-EnableAdvancedLogging {
    Write-Log "Enabling Advanced Audit Logging..." "INFO"
    
    try {
        # Export current policy
        $tempFile = "$env:TEMP\audit_policy.txt"
        auditpol /get /category:* /r > $tempFile
        
        # Enable logging for critical categories
        $auditSettings = @(
            "Logon/Logoff",
            "Account Management",
            "Detailed Tracking",
            "Object Access",
            "System",
            "Policy Change"
        )
        
        foreach ($setting in $auditSettings) {
            auditpol /set /category:"$setting" /success:enable /failure:enable | Out-Null
            Write-Log "Enabled audit logging for: $setting" "INFO"
        }
        
        # Configure event log retention
        $logNames = @("Security", "System", "Application")
        foreach ($logName in $logNames) {
            # Set log size to 100MB
            wevtutil sl $logName /ms:104857600 /quiet
            # Set to overwrite as needed
            wevtutil sl $logName /lfn:true /quiet
            Write-Log "Configured $logName event log" "INFO"
        }
        
        Write-Log "Advanced audit logging enabled" "SUCCESS"
        
        # Cleanup
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

        # Powershell ogging
        # ScriptBlock logging
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -Force

        # Module logging (log all modules)
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" -Value 1 -Type DWord -Force
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" -Name "*" -Value "*" -Type String -Force

        # Transcription (registry-based, belt-and-suspenders with profile-based below)
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" -Name "EnableTranscripting" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" -Name "OutputDirectory" -Value "C:\Windows\Logs\PSTranscripts" -Type String -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription" -Name "EnableInvocationHeader" -Value 1 -Type DWord -Force
        New-Item -ItemType Directory -Path "C:\Windows\Logs\PSTranscripts" -Force | Out-Null
    }
    catch {
        Write-Log "Error enabling advanced logging: $_" "ERROR"
    }
}

# ==============================================================================
# IMPLEMENTATION: Backup Registry
# ==============================================================================
function Invoke-BackupRegistry {
    Write-Log "Backing up system registry..." "INFO"
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = "$BackupPath\Registry_Backup_$timestamp"
        
        if (-not (Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath | Out-Null
        }
        
        # Backup HKLM (SYSTEM)
        Write-Log "Backing up HKEY_LOCAL_MACHINE..." "INFO"
        reg export HKLM "$backupPath\HKLM_Backup.reg" /y | Out-Null
        
        # Backup HKCU (CURRENT_USER)
        Write-Log "Backing up HKEY_CURRENT_USER..." "INFO"
        reg export HKCU "$backupPath\HKCU_Backup.reg" /y | Out-Null
        
        Write-Log "Registry backup complete. Files saved to $backupPath" "SUCCESS"
    }
    catch {
        Write-Log "Error backing up registry: $_" "ERROR"
    }
}

# ==============================================================================
# FULL HARDENING SEQUENCE
# ==============================================================================
function Invoke-RunAll {
    Write-Log "Running full hardening sequence..." "INFO"
    
    Write-Host ""
    Write-Host "EXECUTING FULL HARDENING SEQUENCE" -ForegroundColor Magenta
    Write-Host "This will take several minutes..." -ForegroundColor Yellow
    Write-Host ""
    
    Invoke-DownloadRepository
    Start-Sleep -Seconds 2
    
    Invoke-InstallTools
    Start-Sleep -Seconds 2
    
    Invoke-DisableGuestAccount
    Start-Sleep -Seconds 1
    
    Invoke-SetPasswordPolicy
    Start-Sleep -Seconds 1
    
    Invoke-AddGlassBreakUser
    Start-Sleep -Seconds 1
    
    Invoke-ADPasswordChange
    Start-Sleep -Seconds 1
    
    Invoke-BackupRegistry
    Start-Sleep -Seconds 1
    
    Invoke-FirewallLite
    Start-Sleep -Seconds 1
    
    Invoke-HardenSMB
    Start-Sleep -Seconds 1
    
    Invoke-HardenRDP
    Start-Sleep -Seconds 1
    
    Invoke-HardenWMI
    Start-Sleep -Seconds 1
    
    Invoke-HardenLSASS
    Start-Sleep -Seconds 1
    
    Invoke-ConfigureUAC
    Start-Sleep -Seconds 1
    
    Invoke-EnableASLRDEP
    Start-Sleep -Seconds 1
    
    Invoke-DisableServices
    Start-Sleep -Seconds 1
    
    Invoke-DisableLegacyProtocols
    Start-Sleep -Seconds 1
    
    Invoke-DisableNetBIOS
    Start-Sleep -Seconds 1
    
    Invoke-DisableLLMNR
    Start-Sleep -Seconds 1
    
    Invoke-ClearPersistence
    Start-Sleep -Seconds 1
    
    Invoke-BackdoorHunt
    Start-Sleep -Seconds 1
    
    Invoke-EnableAdvancedLogging
    
    Write-Log "Full hardening sequence complete" "SUCCESS"
    Write-Host ""
    Write-Host "Full hardening sequence complete! Check the log file for details." -ForegroundColor Green
    Write-Host "Log file: $LogFile" -ForegroundColor Cyan
}

# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================

$MenuActions = @{
    "1"  = { Invoke-DownloadRepository }
    "2"  = { Invoke-InstallTools }
    "3"  = { Invoke-ADPasswordChange }
    "4"  = { Invoke-AddGlassBreakUser }
    "5"  = { Invoke-DisableGuestAccount }
    "6"  = { Invoke-SetPasswordPolicy }
    "7"  = { Invoke-FirewallLite }
    "8"  = { Invoke-FirewallAggressive }
    "9"  = { Invoke-BlockIP }
    "10" = { Invoke-HardenSMB }
    "11" = { Invoke-DisableRM }
    "12" = { Invoke-HardenWMI }
    "13" = { Invoke-HardenLSASS }
    "14" = { Invoke-ConfigureUAC }
    "15" = { Invoke-EnableASLRDEP }
    "16" = { Invoke-ResetKerberosPass }
    "17" = { Invoke-DisableServices }
    "18" = { Invoke-DisableLegacyProtocols }
    "19" = { Invoke-DisableNetBIOS }
    "20" = { Invoke-DisableLLMNR }
    "21" = { Invoke-ClearPersistence }
    "22" = { Invoke-ClearKerberosTickets }
    "23" = { Invoke-BackdoorHunt }
    "24" = { Invoke-HuntKerberosTickets }
    "25" = { Invoke-EnableAdvancedLogging }
    "26" = { Invoke-BackupRegistry }
    "a"  = { Invoke-RunAll }
}

# --- Main Loop ---

if (-not (Test-Environment)) { exit 1 }

do {
    Show-Menu
    $choice = Read-Host "  Select option"

    if ($MenuActions.ContainsKey($choice)) {
        Write-Host ""
        & $MenuActions[$choice]
        Write-Host ""
        Write-Host "  Press any key to return to menu..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } elseif ($choice -notin @("Q","q")) {
        Write-Host "  Invalid option. Try again." -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

} while ($choice -notin @("Q","q"))

Write-Log "Archimedes script terminated by user" "INFO"
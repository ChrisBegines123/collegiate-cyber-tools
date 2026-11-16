#Check if windows server is modern enough to support Unc mode
function Invoke-DeathStarSuperLaser {
    # willhelm scream noises
    Start-Service sshd
    Set-Service -Name sshd -StartupType 'Automatic'
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    } else {
        Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
    }
    $sshConfigPaths = @(
    "C:\ProgramData\ssh\sshd_config",
    "C:\OpenSSH\sshd_config",
    "$env:ProgramFiles\OpenSSH\sshd_config"
    )

    $sshConfigPath = $sshConfigPaths | Where-Object { Test-Path $_ }
    if ($sshConfigPath) {
        Write-Output "Found OpenSSH config at: $sshConfigPath"
        #whoa, we found the config, maybe we can do something with it, maybe not, maybe this is just a chat box and we are all wasting our time
        foreach ($line in Get-Content $sshConfigPath) {
            # Skip empty lines and comments
            if ($line -match '^\s*$' -or $line -match '^\s*#') {
                continue
            }

            # Write secure sshd config for Kerberos domain admin auth only
            @(
                "Port 22",
                "AddressFamily any",
                "ListenAddress 0.0.0.0",
                "ListenAddress ::",
                "PermitRootLogin no",
                "StrictModes yes",
                "MaxAuthTries 3",
                "MaxSessions 2",
                "PubkeyAuthentication yes",
                "PasswordAuthentication no",
                "PermitEmptyPasswords no",
                "KerberosAuthentication yes",
                "KerberosOrGetTokenPassed yes",
                "GSSAPIAuthentication yes",
                "GSSAPICleanupCredentials yes",
                "DenyUsers *",
                "AllowGroups CCDCTEAM.com\Domain Admins",
                "Protocol 2",
                "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr",
                "MACs hmac-sha2-512,hmac-sha2-256",
                "KexAlgorithms curve25519-sha256,diffie-hellman-group16-sha512",
                "LogLevel VERBOSE",
                "X11Forwarding no",
                "X11UseLocalhost yes",
                "PermitTTY yes",
                "PrintMotd no",
                "AcceptEnv LANG LC_*",
                "UsePAM yes"
            ) | Out-File -FilePath $sshConfigPath -Force -Encoding UTF8          
            Restart-Service sshd  
        }
    } else {
        Write-Output "OpenSSH config not found in standard locations"
    }

}

function Install-NotUncMode {
    Write-Host "chat, were going in, maybe dism smiles upon us"
    # Add your installation commands here
    try{get-windowsfeature -name openssh-server | Install-WindowsFeature -Verbose}
    catch{Write-Host "dism failed"}
}

function Install-UncMode {
    Invoke-WebRequest -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64.zip" -OutFile "OpenSSH-Win64.zip"
    Expand-Archive -Path "OpenSSH-Win64.zip" -DestinationPath "C:\OpenSSH" -Force
    if (Test-Path .\OpenSSH-Win64.zip) {
        Remove-Item .\OpenSSH-Win64.zip -Force
    }
    move-item "C:\OpenSSH\OpenSSH-Win64\*" "C:\OpenSSH" -Force
    rmdir "C:\OpenSSH\OpenSSH-Win64" -Force
    $env:Path += ";C:\OpenSSH"
    cd C:\openssh #chat are we supposed to use CD anymore, honestly I started using it and now im to afraid to ask, I should just install vbasic and live with my decisions
    .\install-sshd.ps1
    try{New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22}catch{
    try{netsh advfirewall firewall add rule name=sshd dir=in action=allow protocol=TCP localport=22}
    catch{Write-Host "firewall rule already exists, moving on"}}
    start-service sshd
    Set-Service sshd -StartupType Automatic
}
function Install-ChatMode{
    Write-Host "Installing Chat Mode... just kidding, maybe one day"
    winget install "openssh preview"
}

function whatsThisOneDo {
    Write-Host 'probably nothing, maybe chat put it here for a reason, maybe not'
    }

function install-goose {
    Write-Host "Installing Goose..., nvm just kidding"    
}


$majorVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
if($majorVersion.CurrentMajorVersionNumber -lt 10) {
    Write-Host "new ssh install is not supported on this version of Windows Server. we gotta go unc chat"
    Install-UncMode
    Invoke-DeathStarSuperLaser
}elseif ($majorVersion.productName -contains '2025') {
    Write-Host "Windows Server 2025 detected. ITS ZOOMER TIME"
    try {
        Invoke-DeathStarSuperLaser
    }
    catch {
        Write-Host "something went wrong with the super laser, maybe we are all out of kyber? trying unc mode"
        try{
            Install-UncMode
            Invoke-DeathStarSuperLaser
        }catch{
            Write-Host "unc mode failed, maybe this is a chat box, trying chat mode"
            Install-ChatMode
            Invoke-DeathStarSuperLaser
        }
    }
}elseif ($majorVersion.productName -contains 'Windows 10' -or $majorVersion.productName -contains 'Windows 11') {
    Write-Host "Wait, this windows box is chat coded, maybe I can just win."
    try{
        winget install "openssh preview"
        Invoke-DeathStarSuperLaser
    }catch{
        Write-Host "winget failed, something wrong, I can feel it. trying unc mode"
        Install-UncMode
        Invoke-DeathStarSuperLaser
    }
}elseif ($majorVersion -ge 10 -and $majorVersion.productName -notcontains "2016") {
    Write-Host "Windows Server 2016 or later detected. Unc mode is not needed."
    try{
        Install-NotUncMode
        Invoke-DeathStarSuperLaser 
    }catch{
        Write-Host "something went wrong with the normal install, maybe we are all out of kyber? trying unc mode"
        try{
            Install-UncMode
            Invoke-DeathStarSuperLaser
        }catch{
            Write-Host "unc mode failed, maybe this is a chat box, trying chat mode"
            Install-ChatMode
            Invoke-DeathStarSuperLaser
        }
    }
}


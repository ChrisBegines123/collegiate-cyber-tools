# CCDC26 Windows Toolkit - Password Generation (Zulu-style)
# Deterministic passphrase generation using salt + username
# Enables consistent passwords across team without sharing plaintext

#=============================================================================
# WORDLIST
#=============================================================================
$script:WordList = @(
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
    "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa",
    "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey", "xray",
    "yankee", "zulu", "apple", "banana", "cherry", "dragon", "eagle", "falcon",
    "glacier", "harbor", "island", "jungle", "kayak", "lemon", "mango", "neptune",
    "orange", "piano", "quartz", "river", "sunset", "tiger", "umbrella", "violet",
    "walrus", "xenon", "yellow", "zebra", "anchor", "beacon", "castle", "dolphin",
    "ember", "flame", "granite", "horizon", "ivory", "jasper", "kingdom", "lantern",
    "marble", "nebula", "oasis", "phoenix", "quantum", "raven", "sapphire", "thunder",
    "unicorn", "vortex", "willow", "xylo", "yonder", "zenith", "arctic", "blazer",
    "cosmic", "dagger", "eclipse", "frost", "galaxy", "hunter", "inferno", "jewel",
    "kraken", "lotus", "mystic", "ninja", "obsidian", "prism", "quest", "rocket",
    "shadow", "tempest", "ultra", "valiant", "warrior", "xeno", "yeoman", "zodiac",
    "atlas", "blade", "cipher", "dynamo", "enigma", "fury", "ghost", "havoc"
)

#=============================================================================
# CORE FUNCTIONS
#=============================================================================
function Get-DeterministicPassword {
    <#
    .SYNOPSIS
        Generates a deterministic passphrase based on salt and username.
    
    .DESCRIPTION
        Uses MD5 hash of (salt + username) to select words from wordlist.
        Same inputs always produce same output - enables team coordination.
    
    .PARAMETER Username
        The username to generate password for.
    
    .PARAMETER Salt
        Secret salt known only to the team. Should be set at competition start.
    
    .PARAMETER WordCount
        Number of words in passphrase (default: 5).
    
    .EXAMPLE
        Get-DeterministicPassword -Username "admin" -Salt "ccdc2026secret"
        # Returns something like: "dragon-falcon-sunset-prism-echo1"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$Salt,
        
        [int]$WordCount = 5
    )
    
    # Combine salt and username
    $combined = "$Salt$Username"
    
    # Generate MD5 hash
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $hashBytes = $md5.ComputeHash($bytes)
    
    # Convert hash to hex string
    $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''
    
    # Select words based on hash segments
    $words = @()
    $wordListCount = $script:WordList.Count
    
    for ($i = 0; $i -lt $WordCount; $i++) {
        # Take 4 hex chars (2 bytes) per word selection
        $startIndex = ($i * 4) % $hashString.Length
        $segment = $hashString.Substring($startIndex, [Math]::Min(4, $hashString.Length - $startIndex))
        
        # Convert to integer and map to wordlist
        $value = [Convert]::ToInt32($segment, 16)
        $wordIndex = $value % $wordListCount
        $words += $script:WordList[$wordIndex]
    }
    
    # Build passphrase: word1-word2-word3-word4-word5 + digit
    $passphrase = ($words -join "-") + "1"
    
    return $passphrase
}

function Generate-TeamPasswords {
    <#
    .SYNOPSIS
        Generates passwords for multiple users and exports to file.
    
    .PARAMETER Users
        Array of usernames or path to file containing usernames.
    
    .PARAMETER Salt
        Team salt for password generation.
    
    .PARAMETER OutputPath
        Path to save password list (default: passwords.txt in current directory).
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Users,
        
        [Parameter(Mandatory=$true)]
        [string]$Salt,
        
        [string]$OutputPath = ".\passwords.txt"
    )
    
    # Handle file input
    if ($Users -is [string] -and (Test-Path $Users)) {
        $Users = Get-Content $Users | Where-Object { $_ -ne "" }
    }
    
    $results = @()
    
    foreach ($user in $Users) {
        $password = Get-DeterministicPassword -Username $user -Salt $Salt
        $results += [PSCustomObject]@{
            Username = $user
            Password = $password
        }
    }
    
    # Display results
    Write-Host "`n=== Generated Passwords ===" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    
    # Save to file
    $results | ForEach-Object {
        "$($_.Username):$($_.Password)"
    } | Out-File -FilePath $OutputPath -Encoding UTF8
    
    Write-Host "Passwords saved to: $OutputPath" -ForegroundColor Green
    Write-Host "WARNING: Delete this file after use!" -ForegroundColor Yellow
    
    return $results
}

function Set-UserPassword {
    <#
    .SYNOPSIS
        Sets a local user's password using deterministic generation.
    
    .PARAMETER Username
        The username to set password for.
    
    .PARAMETER Salt
        Team salt for password generation.
    
    .PARAMETER Apply
        If true, actually applies the password. Otherwise just shows what would be set.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$Salt,
        
        [switch]$Apply
    )
    
    $password = Get-DeterministicPassword -Username $Username -Salt $Salt
    
    if ($Apply) {
        try {
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
            Set-LocalUser -Name $Username -Password $securePassword -ErrorAction Stop
            Write-Host "[OK] Set password for $Username" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "[ERROR] Failed to set password for $Username : $_" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "[DRY-RUN] Would set password for $Username to: $password" -ForegroundColor Yellow
        return $password
    }
}

function Set-ADUserPassword {
    <#
    .SYNOPSIS
        Sets an AD user's password using deterministic generation.
    
    .PARAMETER Username
        The AD username (SamAccountName) to set password for.
    
    .PARAMETER Salt
        Team salt for password generation.
    
    .PARAMETER Apply
        If true, actually applies the password.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$true)]
        [string]$Salt,
        
        [switch]$Apply
    )
    
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host "[ERROR] ActiveDirectory module not available" -ForegroundColor Red
        return $false
    }
    
    Import-Module ActiveDirectory
    
    $password = Get-DeterministicPassword -Username $Username -Salt $Salt
    
    if ($Apply) {
        try {
            $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
            Set-ADAccountPassword -Identity $Username -NewPassword $securePassword -Reset -ErrorAction Stop
            Write-Host "[OK] Set AD password for $Username" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "[ERROR] Failed to set AD password for $Username : $_" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "[DRY-RUN] Would set AD password for $Username to: $password" -ForegroundColor Yellow
        return $password
    }
}

#=============================================================================
# INTERACTIVE MODE
#=============================================================================
function Start-PasswordGenerator {
    <#
    .SYNOPSIS
        Interactive password generator interface.
    #>
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  CCDC26 Password Generator (Zulu)     " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Get salt
    $salt = Read-Host "Enter team salt (secret phrase)"
    if ([string]::IsNullOrEmpty($salt)) {
        Write-Host "[ERROR] Salt cannot be empty" -ForegroundColor Red
        return
    }
    
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "1) Generate password for single user"
    Write-Host "2) Generate passwords for multiple users (interactive)"
    Write-Host "3) Generate passwords from file"
    Write-Host "4) Set local user password"
    Write-Host "5) Set AD user password"
    Write-Host ""
    
    $choice = Read-Host "Select option [1-5]"
    
    switch ($choice) {
        "1" {
            $username = Read-Host "Enter username"
            $password = Get-DeterministicPassword -Username $username -Salt $salt
            Write-Host "`nGenerated password for '$username':" -ForegroundColor Cyan
            Write-Host $password -ForegroundColor Green
        }
        "2" {
            $users = @()
            Write-Host "Enter usernames (empty line to finish):" -ForegroundColor Yellow
            while ($true) {
                $input = Read-Host
                if ([string]::IsNullOrEmpty($input)) { break }
                $users += $input
            }
            if ($users.Count -gt 0) {
                Generate-TeamPasswords -Users $users -Salt $salt
            }
        }
        "3" {
            $filePath = Read-Host "Enter path to user list file"
            if (Test-Path $filePath) {
                Generate-TeamPasswords -Users $filePath -Salt $salt
            }
            else {
                Write-Host "[ERROR] File not found: $filePath" -ForegroundColor Red
            }
        }
        "4" {
            $username = Read-Host "Enter local username"
            $confirm = Read-Host "Apply password change? (y/n)"
            if ($confirm -ieq 'y') {
                Set-UserPassword -Username $username -Salt $salt -Apply
            }
            else {
                Set-UserPassword -Username $username -Salt $salt
            }
        }
        "5" {
            $username = Read-Host "Enter AD username (SamAccountName)"
            $confirm = Read-Host "Apply password change? (y/n)"
            if ($confirm -ieq 'y') {
                Set-ADUserPassword -Username $username -Salt $salt -Apply
            }
            else {
                Set-ADUserPassword -Username $username -Salt $salt
            }
        }
        default {
            Write-Host "[ERROR] Invalid option" -ForegroundColor Red
        }
    }
}

# If run directly, start interactive mode
if ($MyInvocation.InvocationName -ne '.') {
    Start-PasswordGenerator
}

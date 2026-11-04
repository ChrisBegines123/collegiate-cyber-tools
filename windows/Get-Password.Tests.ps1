#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Get-Password.ps1. Run entirely on any platform
    (including non-Windows) with:

        pwsh -NoProfile -Command "Invoke-Pester -Path ./Get-Password.Tests.ps1 -Output Detailed"

.DESCRIPTION
    Get-Password.ps1 has no AD dependency, so these tests exercise it
    against real files written under Pester's TestDrive (auto-cleaned
    after each test) and only mock the master-password prompt and the
    error/host output streams.
#>

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/Get-Password.ps1"
    $script:masterPassword = 'correct horse battery'

    function New-PasswordsFile {
        param(
            [string]$Path,
            [string]$Master = $script:masterPassword,
            [hashtable]$Users = @{ alice = 'Sup3rSecret!!'; bob = 'AnotherOne99$' }
        )
        $salt = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($salt)
        $rng.Dispose()
        $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
            $Master, $salt, 600000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $key = $kdf.GetBytes(32)
        $kdf.Dispose()

        Set-Content $Path "salt,$([Convert]::ToBase64String($salt))"
        Add-Content $Path "username,password"
        foreach ($name in $Users.Keys) {
            $secure = ConvertTo-SecureString $Users[$name] -AsPlainText -Force
            Add-Content $Path "$name,$(ConvertFrom-SecureString -SecureString $secure -Key $key)"
        }
    }
}

Describe 'Get-Password.ps1' {

    BeforeEach {
        $global:GetPasswordTest = @{ Master = $script:masterPassword }
        Mock Read-Host { ConvertTo-SecureString $global:GetPasswordTest.Master -AsPlainText -Force }
        Mock Write-Error { }
        Mock Write-Host { }
    }

    AfterEach {
        Remove-Variable -Name GetPasswordTest -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'locating the passwords file' {

        It 'uses the -File path when one is given' {
            $path = "$TestDrive/custom.csv"
            New-PasswordsFile -Path $path -Users @{ alice = 'Sup3rSecret!!' }

            $result = & $script:scriptPath -File $path

            $result.Username | Should -Be 'alice'
        }

        It 'picks the newest passwords_*.csv in the current directory when -File is omitted' {
            $dir = "$TestDrive/cwd"
            New-Item -ItemType Directory -Path $dir | Out-Null
            $older = Join-Path $dir 'passwords_20200101_000000.csv'
            $newer = Join-Path $dir 'passwords_20300101_000000.csv'
            New-PasswordsFile -Path $older -Users @{ alice = 'OldPassword1!' }
            New-PasswordsFile -Path $newer -Users @{ alice = 'NewPassword1!' }
            (Get-Item $older).LastWriteTime = (Get-Date).AddDays(-1)
            (Get-Item $newer).LastWriteTime = Get-Date

            Push-Location $dir
            try {
                $result = & $script:scriptPath
            } finally {
                Pop-Location
            }

            $result.Password | Should -Be 'NewPassword1!'
        }

        It 'errors when no passwords_*.csv exists and no -File is given' {
            $dir = "$TestDrive/empty"
            New-Item -ItemType Directory -Path $dir | Out-Null

            Push-Location $dir
            try {
                & $script:scriptPath
            } finally {
                Pop-Location
            }

            Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                $Message -like '*Could not find a passwords_*.csv file*'
            }
        }

        It 'errors when the given -File path does not exist' {
            & $script:scriptPath -File "$TestDrive/missing.csv"

            Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                $Message -like '*Could not find*'
            }
        }

        It 'errors when the file is missing the salt line' {
            $path = "$TestDrive/malformed.csv"
            Set-Content $path "username,password"
            Add-Content $path "alice,notarealcipher"

            & $script:scriptPath -File $path

            Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                $Message -like '*missing salt line*'
            }
        }
    }

    Context 'decrypting with the correct master password' {

        It 'returns every user with their decrypted password' {
            $path = "$TestDrive/all.csv"
            New-PasswordsFile -Path $path -Users @{ alice = 'Sup3rSecret!!'; bob = 'AnotherOne99$' }

            $result = & $script:scriptPath -File $path

            ($result | Where-Object Username -eq 'alice').Password | Should -Be 'Sup3rSecret!!'
            ($result | Where-Object Username -eq 'bob').Password | Should -Be 'AnotherOne99$'
            @($result).Count | Should -Be 2
        }

        It 'filters to the requested -User' {
            $path = "$TestDrive/filtered.csv"
            New-PasswordsFile -Path $path -Users @{ alice = 'Sup3rSecret!!'; bob = 'AnotherOne99$' }

            $result = & $script:scriptPath -File $path -User alice

            @($result).Count | Should -Be 1
            $result.Username | Should -Be 'alice'
            $result.Password | Should -Be 'Sup3rSecret!!'
        }

        It 'errors when the requested -User has no entry' {
            $path = "$TestDrive/filtered2.csv"
            New-PasswordsFile -Path $path -Users @{ alice = 'Sup3rSecret!!' }

            & $script:scriptPath -File $path -User nobody

            Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter {
                $Message -like "*No entry for user 'nobody'*"
            }
        }
    }

    Context 'decrypting with the wrong master password' {

        It 'emits a per-entry error and no password for a user it fails to decrypt' {
            $path = "$TestDrive/wrong.csv"
            New-PasswordsFile -Path $path -Users @{ alice = 'Sup3rSecret!!'; bob = 'AnotherOne99$' }
            $global:GetPasswordTest.Master = 'wrong password'

            $result = & $script:scriptPath -File $path

            $result | Should -BeNullOrEmpty
            Should -Invoke Write-Error -Times 2 -Exactly -ParameterFilter {
                $Message -like '*wrong master password, or the file is corrupt*'
            }
        }
    }

    Context 'the master password prompt' {

        It 'is read as a SecureString, so it is not echoed' {
            $path = "$TestDrive/prompt.csv"
            New-PasswordsFile -Path $path -Users @{ alice = 'Sup3rSecret!!' }

            & $script:scriptPath -File $path

            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter { $AsSecureString }
        }
    }
}

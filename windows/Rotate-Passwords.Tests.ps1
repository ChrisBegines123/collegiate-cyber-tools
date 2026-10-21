#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Rotate-Passwords.ps1. Run entirely on any platform
    (including non-Windows) with:

        pwsh -NoProfile -Command "Invoke-Pester -Path ./Rotate-Passwords.Tests.ps1 -Output Detailed"

.DESCRIPTION
    Rotate-Passwords.ps1 is a top-level script, so each test runs the whole
    thing with every external dependency mocked: the ActiveDirectory cmdlets,
    the master-password prompt, and the output file writes (captured in memory
    so nothing is ever written to disk or changed in a real directory).

    [System.Web.Security.Membership] only exists on .NET Framework (Windows
    PowerShell 5.1). Static .NET methods can't be mocked, so where the type
    is missing a small stand-in is compiled for the test run. On Windows
    PowerShell 5.1 the real type is used and the few tests that need to
    script its output are skipped.
#>

BeforeAll {
    # AD cmdlets don't exist here, and Pester can only mock commands that
    # already exist, so define permissive stubs first.
    foreach ($stub in @(
        @{ Name = 'Get-ADUser'; Params = '[CmdletBinding()] param($Filter, $Properties)' }
        @{ Name = 'Set-ADAccountPassword'; Params = '[CmdletBinding()] param($Identity, $NewPassword, [switch]$Reset)' }
    )) {
        if (-not (Get-Command $stub.Name -ErrorAction SilentlyContinue)) {
            Set-Item -Path "function:script:$($stub.Name)" -Value ([scriptblock]::Create($stub.Params))
        }
    }

    if (-not ('System.Web.Security.Membership' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Collections.Generic;
namespace System.Web.Security {
    public static class Membership {
        // Tests enqueue passwords here to script what GeneratePassword "returns".
        public static readonly Queue<string> Queue = new Queue<string>();
        private static int counter = 0;
        public static string GeneratePassword(int length, int minNonAlnum) {
            if (Queue.Count > 0) return Queue.Dequeue();
            counter++;
            return ("Aa" + counter.ToString("D4") + "!").PadRight(length, 'x');
        }
    }
}
'@
    }
    $script:canScriptGenerator = $null -ne [System.Web.Security.Membership].GetField('Queue')

    $script:masterPassword = 'correct horse battery'
    $script:scriptPath = "$PSScriptRoot/Rotate-Passwords.ps1"

    function Get-Plaintext([securestring]$Secure) {
        [System.Net.NetworkCredential]::new('', $Secure).Password
    }
    function New-FakeUser { param([string]$SamAccountName) [PSCustomObject]@{ SamAccountName = $SamAccountName } }
}

Describe 'Rotate-Passwords.ps1 (mocked AD, in-memory output file)' {

    BeforeEach {
        $script:resets = [System.Collections.Generic.List[object]]::new()   # one entry per Set-ADAccountPassword call
        $script:fileLines = [System.Collections.Generic.List[string]]::new() # everything written to the output file
        $script:savedUsername = $env:USERNAME
        $env:USERNAME = 'operator'
        if ($script:canScriptGenerator) { [System.Web.Security.Membership]::Queue.Clear() }

        Mock Import-Module { } -ParameterFilter { $Name -eq 'ActiveDirectory' }
        Mock Add-Type { } -ParameterFilter { $AssemblyName -eq 'System.Web' }
        # Mock bodies can't see $script: variables (and a closure would hide the
        # mock's own parameters), so share state with them through one global
        # object that AfterEach removes.
        $global:RotateTest = @{ Master = $script:masterPassword; Resets = $script:resets; Lines = $script:fileLines }
        Mock Read-Host { ConvertTo-SecureString $global:RotateTest.Master -AsPlainText -Force }
        Mock Write-Host { }
        Mock Write-Error { }

        Mock Get-ADUser {
            @(
                New-FakeUser 'alice'
                New-FakeUser 'bob'
                New-FakeUser 'Administrator'
                New-FakeUser 'krbtgt'
                New-FakeUser 'Guest'
                New-FakeUser 'operator'      # whoever is running the script
            )
        }
        Mock Set-ADAccountPassword {
            $global:RotateTest.Resets.Add([PSCustomObject]@{ Identity = $Identity; Password = [System.Net.NetworkCredential]::new('', $NewPassword).Password; Secure = $NewPassword })
        }

        Mock Set-Content { $global:RotateTest.Lines.Clear(); $global:RotateTest.Lines.Add([string]$Value) }
        Mock Add-Content { $global:RotateTest.Lines.Add([string]$Value) }
    }

    AfterEach {
        $env:USERNAME = $script:savedUsername
        Remove-Variable -Name RotateTest -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'which accounts are reset' {

        It 'queries only enabled users' {
            & $script:scriptPath
            Should -Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter { $Filter -eq 'Enabled -eq $true' }
        }

        It 'resets ordinary users' {
            & $script:scriptPath
            $script:resets.Identity | Should -Contain 'alice'
            $script:resets.Identity | Should -Contain 'bob'
        }

        It 'never resets Administrator, krbtgt, Guest, or the account running the script' {
            & $script:scriptPath
            $script:resets.Identity | Should -Not -Contain 'Administrator'
            $script:resets.Identity | Should -Not -Contain 'krbtgt'
            $script:resets.Identity | Should -Not -Contain 'Guest'
            $script:resets.Identity | Should -Not -Contain 'operator'
        }

        It 'resets nobody when only protected accounts exist' {
            Mock Get-ADUser { @(New-FakeUser 'Administrator'; New-FakeUser 'krbtgt'; New-FakeUser 'operator') }
            & $script:scriptPath
            Should -Invoke Set-ADAccountPassword -Times 0
        }

        It 'resets each user exactly once, with -Reset' {
            & $script:scriptPath
            Should -Invoke Set-ADAccountPassword -Times 2 -Exactly
            Should -Invoke Set-ADAccountPassword -Times 2 -Exactly -ParameterFilter { $Reset }
        }
    }

    Context 'the generated passwords' {

        It 'passes a SecureString to Set-ADAccountPassword' {
            & $script:scriptPath
            $script:resets | ForEach-Object { $_.Secure | Should -BeOfType [securestring] }
        }

        It 'generates 16-character passwords with lowercase, uppercase and a digit' {
            & $script:scriptPath
            foreach ($r in $script:resets) {
                $r.Password.Length | Should -Be 16
                $r.Password | Should -MatchExactly '[a-z]'
                $r.Password | Should -MatchExactly '[A-Z]'
                $r.Password | Should -Match '\d'
            }
        }

        It 'gives every user a different password' {
            & $script:scriptPath
            ($script:resets.Password | Select-Object -Unique).Count | Should -Be $script:resets.Count
        }

        It 'retries until the generator returns an acceptable password' {
            if (-not $script:canScriptGenerator) {
                Set-ItResult -Skipped -Because 'the real Membership.GeneratePassword cannot be scripted'
                return
            }
            # Each of these breaks one rule (no uppercase, no lowercase, no digit, disallowed characters),
            # so each must be rejected and regenerated.
            foreach ($bad in @('alllowercase1!', 'ALLUPPERCASE1!', 'NoDigitsHere!!!', 'Has;Bad|Chars1a')) {
                [System.Web.Security.Membership]::Queue.Enqueue($bad)
            }
            [System.Web.Security.Membership]::Queue.Enqueue('Good1Password!xyz')
            Mock Get-ADUser { @(New-FakeUser 'alice') }

            & $script:scriptPath

            $script:resets.Count | Should -Be 1
            $script:resets[0].Password | Should -BeExactly 'Good1Password!xyz'
        }
    }

    Context 'the output file' {

        It 'starts with a salt line holding 16 bytes of base64' {
            & $script:scriptPath
            $script:fileLines[0] | Should -Match '^salt,'
            $salt = [Convert]::FromBase64String(($script:fileLines[0] -split ',')[1])
            $salt.Length | Should -Be 16
        }

        It 'has a header line, then one record per reset user' {
            & $script:scriptPath
            $script:fileLines[1] | Should -Match '^username,'
            $records = $script:fileLines | Select-Object -Skip 2
            @($records).Count | Should -Be 2
            ($records | ForEach-Object { ($_ -split ',')[0] }) | Should -Be @('alice', 'bob')
        }

        It 'never writes a plaintext password to the file' {
            & $script:scriptPath
            $fileText = $script:fileLines -join "`n"
            foreach ($r in $script:resets) {
                $fileText | Should -Not -BeLike "*$($r.Password)*"
            }
            $fileText | Should -Not -BeLike "*$($script:masterPassword)*"
        }

        It 'uses a fresh salt on every run' {
            & $script:scriptPath
            $first = $script:fileLines[0]
            $script:resets.Clear()
            & $script:scriptPath
            $script:fileLines[0] | Should -Not -Be $first
        }

        It 'can be decrypted with the master password and the saved salt' {
            & $script:scriptPath

            $salt = [Convert]::FromBase64String(($script:fileLines[0] -split ',')[1])
            $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
                $script:masterPassword, $salt, 600000,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $key = $kdf.GetBytes(32)
            $kdf.Dispose()

            foreach ($line in ($script:fileLines | Select-Object -Skip 2)) {
                $user, $cipher = $line -split ',', 2
                $decrypted = Get-Plaintext (ConvertTo-SecureString -String $cipher -Key $key)
                $decrypted | Should -BeExactly ($script:resets | Where-Object Identity -eq $user).Password
            }
        }

        It 'cannot be decrypted with a wrong master password' {
            & $script:scriptPath

            $salt = [Convert]::FromBase64String(($script:fileLines[0] -split ',')[1])
            $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
                'wrong password', $salt, 600000,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $wrongKey = $kdf.GetBytes(32)
            $kdf.Dispose()

            $cipher = ($script:fileLines[2] -split ',', 2)[1]
            { ConvertTo-SecureString -String $cipher -Key $wrongKey -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'the master password prompt' {

        It 'is read as a SecureString, so it is not echoed' {
            & $script:scriptPath
            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter { $AsSecureString }
        }
    }

    Context 'failures' {

        It 'keeps going after one reset fails, and records only the successes' {
            Mock Set-ADAccountPassword {
                if ($Identity -eq 'alice') { throw 'password does not meet policy' }
                $global:RotateTest.Resets.Add([PSCustomObject]@{ Identity = $Identity; Password = [System.Net.NetworkCredential]::new('', $NewPassword).Password; Secure = $NewPassword })
            }

            & $script:scriptPath

            Should -Invoke Write-Error -Times 1 -Exactly
            $script:resets.Identity | Should -Be @('bob')
            $records = @($script:fileLines | Select-Object -Skip 2)
            $records.Count | Should -Be 1
            $records[0] | Should -BeLike 'bob,*'
        }

        It 'stops before changing anything if the ActiveDirectory module cannot be loaded' {
            Mock Import-Module { throw 'module not found' } -ParameterFilter { $Name -eq 'ActiveDirectory' }

            { & $script:scriptPath } | Should -Throw -ExpectedMessage '*module not found*'
            Should -Invoke Set-ADAccountPassword -Times 0
            Should -Invoke Read-Host -Times 0
        }
    }
}

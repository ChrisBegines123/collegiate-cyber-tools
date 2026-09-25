#Requires -Module Pester

<#
.SYNOPSIS
    Pester tests for Check-ADUsers.ps1. Run entirely on any platform
    (including non-Windows) with:

        pwsh -NoProfile -Command "Invoke-Pester -Path ./Check-ADUsers.Tests.ps1 -Output Detailed"

.DESCRIPTION
    Two layers:
      1. Get-ReconciliationPlan is pure logic (no AD/event log dependency) --
         tested directly with plain objects.
      2. Invoke-CheckADUsers is the full orchestration -- tested by mocking
         every ActiveDirectory and event log cmdlet it calls, so the real
         Windows-only APIs are never touched.
#>

BeforeAll {
    # The ActiveDirectory module isn't installed in this environment (and
    # Write-EventLog/New-EventLog are Windows-only), so Get-ADUser etc. don't
    # exist as commands at all. Pester can only mock a command that already
    # exists, so define permissive stubs first -- Mock then replaces these.
    foreach ($stub in @(
        @{ Name = 'Get-ADUser'; Params = 'param($Filter, $Properties)' }
        @{ Name = 'Get-ADGroupMember'; Params = 'param($Identity, [switch]$Recursive)' }
        @{ Name = 'Disable-ADAccount'; Params = 'param($Identity)' }
        @{ Name = 'Remove-ADGroupMember'; Params = 'param($Identity, $Members, [switch]$Confirm)' }
        @{ Name = 'New-EventLog'; Params = 'param($LogName, $Source)' }
        @{ Name = 'Write-EventLog'; Params = 'param($LogName, $Source, $EntryType, $EventId, $Message)' }
    )) {
        if (-not (Get-Command $stub.Name -ErrorAction SilentlyContinue)) {
            Set-Item -Path "function:script:$($stub.Name)" -Value ([scriptblock]::Create($stub.Params))
        }
    }

    . "$PSScriptRoot/Check-ADUsers.ps1"

    function New-FakeUser { param([string]$SamAccountName) [PSCustomObject]@{ SamAccountName = $SamAccountName } }
}

Describe 'Get-ReconciliationPlan' {

    It 'disables users not on the authorized list' {
        $allUsers = @(New-FakeUser 'alice'; New-FakeUser 'bob'; New-FakeUser 'eve')
        $plan = Get-ReconciliationPlan -AllUsers $allUsers -DomainAdmins @() `
            -AuthorizedUsers @('alice', 'bob') -AuthorizedAdmins @() -SafeAccounts @()

        $plan.UsersToDisable.SamAccountName | Should -Be @('eve')
    }

    It 'does not touch users who are on the authorized list' {
        $allUsers = @(New-FakeUser 'alice'; New-FakeUser 'bob')
        $plan = Get-ReconciliationPlan -AllUsers $allUsers -DomainAdmins @() `
            -AuthorizedUsers @('alice', 'bob') -AuthorizedAdmins @() -SafeAccounts @()

        $plan.UsersToDisable | Should -BeNullOrEmpty
    }

    It 'is case-insensitive when matching usernames' {
        $allUsers = @(New-FakeUser 'Alice')
        $plan = Get-ReconciliationPlan -AllUsers $allUsers -DomainAdmins @() `
            -AuthorizedUsers @('alice') -AuthorizedAdmins @() -SafeAccounts @()

        $plan.UsersToDisable | Should -BeNullOrEmpty
    }

    It 'never marks a safe account for disabling, even if not authorized' {
        $allUsers = @(New-FakeUser 'krbtgt'; New-FakeUser 'Administrator'; New-FakeUser 'eve')
        $plan = Get-ReconciliationPlan -AllUsers $allUsers -DomainAdmins @() `
            -AuthorizedUsers @() -AuthorizedAdmins @() -SafeAccounts @('krbtgt', 'Administrator')

        $plan.UsersToDisable.SamAccountName | Should -Be @('eve')
    }

    It 'revokes admin rights from Domain Admins members not on the authorized admins list' {
        $domainAdmins = @(New-FakeUser 'alice'; New-FakeUser 'mallory')
        $plan = Get-ReconciliationPlan -AllUsers @() -DomainAdmins $domainAdmins `
            -AuthorizedUsers @() -AuthorizedAdmins @('alice') -SafeAccounts @()

        $plan.AdminsToDemote.SamAccountName | Should -Be @('mallory')
    }

    It 'never demotes a safe account' {
        $domainAdmins = @(New-FakeUser 'Administrator'; New-FakeUser 'mallory')
        $plan = Get-ReconciliationPlan -AllUsers @() -DomainAdmins $domainAdmins `
            -AuthorizedUsers @() -AuthorizedAdmins @() -SafeAccounts @('Administrator')

        $plan.AdminsToDemote.SamAccountName | Should -Be @('mallory')
    }

    It 'returns empty (not null) collections when there is nothing to do' {
        $plan = Get-ReconciliationPlan -AllUsers @() -DomainAdmins @() `
            -AuthorizedUsers @('alice') -AuthorizedAdmins @('alice') -SafeAccounts @()

        $plan.UsersToDisable.Count | Should -Be 0
        $plan.AdminsToDemote.Count | Should -Be 0
    }
}

Describe 'Test-InList' {
    It 'matches regardless of case' {
        Test-InList -Name 'ALICE' -List @('alice') | Should -BeTrue
    }

    It 'returns false for no match' {
        Test-InList -Name 'eve' -List @('alice', 'bob') | Should -BeFalse
    }
}

Describe 'Invoke-CheckADUsers (unattended, mocked AD/event log)' {

    BeforeEach {
        $script:usersFile = New-TemporaryFile
        $script:adminsFile = New-TemporaryFile
        Set-Content -Path $script:usersFile -Value @('alice', 'bob')
        Set-Content -Path $script:adminsFile -Value @('alice')

        Mock Get-Module { $true } -ParameterFilter { $Name -eq 'ActiveDirectory' }
        Mock Import-Module { } -ParameterFilter { $Name -eq 'ActiveDirectory' }

        Mock Get-ADUser {
            @(
                [PSCustomObject]@{ SamAccountName = 'alice' }
                [PSCustomObject]@{ SamAccountName = 'bob' }
                [PSCustomObject]@{ SamAccountName = 'eve' }   # not authorized -> should be disabled
            )
        }
        Mock Get-ADGroupMember {
            @(
                [PSCustomObject]@{ SamAccountName = 'alice'; objectClass = 'user' }
                [PSCustomObject]@{ SamAccountName = 'mallory'; objectClass = 'user' }  # not authorized admin -> should be demoted
            )
        }
        Mock Disable-ADAccount { }
        Mock Remove-ADGroupMember { }

        # Event log APIs don't exist on non-Windows PowerShell; mocking them
        # also means no real event log is touched even on Windows.
        Mock New-EventLog { }
        Mock Write-EventLog { }
    }

    AfterEach {
        Remove-Item -Path $script:usersFile, $script:adminsFile -ErrorAction SilentlyContinue
    }

    It 'disables exactly the unauthorized enabled user and no one else' {
        & "$PSScriptRoot/Check-ADUsers.ps1" -UsersFile $script:usersFile -AdminsFile $script:adminsFile

        Should -Invoke Disable-ADAccount -Times 1 -Exactly -ParameterFilter { $Identity -eq 'eve' }
        Should -Invoke Disable-ADAccount -Times 0 -ParameterFilter { $Identity -eq 'alice' -or $Identity -eq 'bob' }
    }

    It 'revokes Domain Admins only from the unauthorized admin' {
        & "$PSScriptRoot/Check-ADUsers.ps1" -UsersFile $script:usersFile -AdminsFile $script:adminsFile

        Should -Invoke Remove-ADGroupMember -Times 1 -Exactly -ParameterFilter { $Members -eq 'mallory' }
        Should -Invoke Remove-ADGroupMember -Times 0 -ParameterFilter { $Members -eq 'alice' }
    }

    It 'makes no changes when everyone is already authorized' {
        Mock Get-ADUser {
            @(
                [PSCustomObject]@{ SamAccountName = 'alice' }
                [PSCustomObject]@{ SamAccountName = 'bob' }
            )
        }
        Mock Get-ADGroupMember {
            @([PSCustomObject]@{ SamAccountName = 'alice'; objectClass = 'user' })
        }

        & "$PSScriptRoot/Check-ADUsers.ps1" -UsersFile $script:usersFile -AdminsFile $script:adminsFile

        Should -Invoke Disable-ADAccount -Times 0
        Should -Invoke Remove-ADGroupMember -Times 0
    }

    It 'aborts safely when the users list file is empty' {
        Set-Content -Path $script:usersFile -Value @()

        & "$PSScriptRoot/Check-ADUsers.ps1" -UsersFile $script:usersFile -AdminsFile $script:adminsFile
        # `exit` inside a script invoked with `&` ends that script (not the
        # whole process) and surfaces as $LASTEXITCODE, not a thrown exception.
        $LASTEXITCODE | Should -Be 1

        Should -Invoke Disable-ADAccount -Times 0
        Should -Invoke Remove-ADGroupMember -Times 0
    }
}

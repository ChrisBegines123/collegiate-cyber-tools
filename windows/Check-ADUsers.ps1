<#
.SYNOPSIS
    Reconciles Active Directory users and Domain Admins membership against
    an authorized users list and an authorized admins list, and logs every
    run to the Windows Event Log.

.DESCRIPTION
    Any enabled AD user not on the authorized users list is disabled. Any
    member of the Domain Admins group not on the authorized admins list has
    their membership revoked.

    Built-in/safety accounts (krbtgt, Administrator, Guest) and the account
    currently running the script are never touched, to avoid breaking AD or
    locking out the operator.

    Two input modes:
      - Interactive (default): prompts on the console for each list. Requires
        typing YES to confirm before anything is changed.
      - Automated: pass -UsersFile and -AdminsFile (plain text, one
        SamAccountName per line). No console prompts are shown, and changes
        are applied immediately -- this mode is meant to be run unattended
        from Task Scheduler. Every run, in either mode, writes an entry to
        the "AD Account Reconciliation" event log so runs are auditable.

.PARAMETER UsersFile
    Path to a text file listing authorized usernames, one per line. Supplying
    this (together with -AdminsFile) switches the script to unattended mode.

.PARAMETER AdminsFile
    Path to a text file listing authorized Domain Admins usernames, one per line.

.PARAMETER Force
    In interactive mode, skip the "type YES" confirmation prompt.

.PARAMETER LogName
    Name of the event log to write to. Defaults to "AD Account Reconciliation".
    The log (and its source) is created automatically on first run if missing --
    this requires the account running the script to be a local administrator
    on the machine, which it needs to be anyway to modify AD.

.PARAMETER Source
    Event source name to log under. Defaults to "Check-ADUsers".

.EXAMPLE
    .\Check-ADUsers.ps1
    Interactive run: prompts for both lists, shows the plan, asks for YES.

.EXAMPLE
    .\Check-ADUsers.ps1 -UsersFile C:\ADReconciliation\users.txt -AdminsFile C:\ADReconciliation\admins.txt
    Unattended run suitable for a Scheduled Task: no prompts, applies changes,
    logs everything to the event log.

.NOTES
    Requires the ActiveDirectory PowerShell module (RSAT) and permissions to
    disable users / modify Domain Admins membership.

    To automate: save the authorized lists as text files and register a
    Scheduled Task (running as an account with the necessary AD rights) that
    runs, e.g.:
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ADReconciliation\Check-ADUsers.ps1" -UsersFile "C:\ADReconciliation\users.txt" -AdminsFile "C:\ADReconciliation\admins.txt"

    Testing: this file can be dot-sourced (". .\Check-ADUsers.ps1") to load
    its functions without running anything -- see Check-ADUsers.Tests.ps1 for
    Pester tests that exercise Get-ReconciliationPlan directly and mock the
    ActiveDirectory / event log cmdlets to test Invoke-CheckADUsers end to end
    on any platform, including non-Windows.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console tool; colored Write-Host output and Read-Host prompts are intentional.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogName', Justification = 'Read via script scope inside nested functions.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Source', Justification = 'Read via script scope inside nested functions.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Force', Justification = 'Read via script scope inside Invoke-CheckADUsers.')]
param(
    [string]$UsersFile,
    [string]$AdminsFile,

    # Interactive mode only: skip the final "type YES to apply" prompt.
    [switch]$Force,

    [string]$LogName = 'AD Account Reconciliation',
    [string]$Source = 'Check-ADUsers'
)

$ErrorActionPreference = 'Stop'

# Accounts that must never be disabled or stripped of admin rights.
$SafeAccounts = @('krbtgt', 'Administrator', 'Guest', $env:USERNAME) | Where-Object { $_ }

$Unattended = [bool]$UsersFile -and [bool]$AdminsFile

$script:EventLogAvailable = $false

function Initialize-EventLog {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) {
            New-EventLog -LogName $LogName -Source $Source
        }
        $script:EventLogAvailable = $true
    } catch {
        Write-Warning "Could not initialize event log '$LogName' (source '$Source'): $_. Continuing with console output only."
    }
}

function Write-ReconciliationLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Information', 'Warning', 'Error')][string]$EntryType = 'Information',
        [int]$EventId = 1000
    )

    $color = switch ($EntryType) {
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Gray' }
    }
    Write-Host $Message -ForegroundColor $color

    if ($script:EventLogAvailable) {
        try {
            Write-EventLog -LogName $LogName -Source $Source -EntryType $EntryType -EventId $EventId -Message $Message
        } catch {
            Write-Warning "Failed to write to event log: $_"
        }
    }
}

function Import-ADModuleOrExit {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-ReconciliationLog -Message "ActiveDirectory module not available. Install RSAT: Active Directory Domain Services and try again." -EntryType Error -EventId 1008
        exit 1
    }
    Import-Module ActiveDirectory
}

function Read-NameListFromConsole {
    param([Parameter(Mandatory)][string]$Prompt)

    Write-Host ""
    Write-Host $Prompt -ForegroundColor Cyan
    Write-Host "Enter one username per line. Submit an empty line when finished." -ForegroundColor DarkGray

    $names = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $names.Add($line.Trim())
    }

    return $names | Select-Object -Unique
}

function Read-NameListFromFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        Write-ReconciliationLog -Message "List file not found: $Path" -EntryType Error -EventId 1008
        exit 1
    }

    return Get-Content -Path $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        Select-Object -Unique
}

function Test-InList {
    param([string]$Name, [string[]]$List)
    return [bool]($List | Where-Object { $_ -ieq $Name })
}

function Get-ReconciliationPlan {
    <#
    .SYNOPSIS
        Pure decision logic: given the current AD state and the two
        authorized lists, returns who should be disabled and who should be
        demoted. Takes no dependency on AD or the event log, so it can be
        unit tested with plain objects on any platform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllUsers,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DomainAdmins,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AuthorizedUsers,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AuthorizedAdmins,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SafeAccounts
    )

    $usersToDisable = @($AllUsers | Where-Object {
        -not (Test-InList -Name $_.SamAccountName -List $AuthorizedUsers) -and
        -not (Test-InList -Name $_.SamAccountName -List $SafeAccounts)
    })

    $adminsToDemote = @($DomainAdmins | Where-Object {
        -not (Test-InList -Name $_.SamAccountName -List $AuthorizedAdmins) -and
        -not (Test-InList -Name $_.SamAccountName -List $SafeAccounts)
    })

    [PSCustomObject]@{
        UsersToDisable = $usersToDisable
        AdminsToDemote = $adminsToDemote
    }
}

function Invoke-CheckADUsers {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Name matches the script file, Check-ADUsers.ps1.')]
    param()

    Initialize-EventLog
    Write-ReconciliationLog -Message "Run started by $env:USERNAME on $env:COMPUTERNAME (mode: $(if ($Unattended) { 'unattended' } else { 'interactive'}))." -EventId 1000

    Import-ADModuleOrExit

    if ($Unattended) {
        $authorizedUsers  = Read-NameListFromFile -Path $UsersFile
        $authorizedAdmins = Read-NameListFromFile -Path $AdminsFile
    } else {
        $authorizedUsers  = Read-NameListFromConsole -Prompt "AUTHORIZED USERS - everyone allowed to have an active account:"
        $authorizedAdmins = Read-NameListFromConsole -Prompt "AUTHORIZED ADMINS - everyone allowed to remain in Domain Admins:"
    }

    if ($authorizedUsers.Count -eq 0) {
        Write-ReconciliationLog -Message "No authorized users supplied. Aborting to avoid disabling every account." -EntryType Error -EventId 1008
        exit 1
    }

    $allUsers = Get-ADUser -Filter { Enabled -eq $true } -Properties SamAccountName

    $domainAdmins = Get-ADGroupMember -Identity 'Domain Admins' -Recursive |
        Where-Object { $_.objectClass -eq 'user' }

    $plan = Get-ReconciliationPlan -AllUsers $allUsers -DomainAdmins $domainAdmins `
        -AuthorizedUsers $authorizedUsers -AuthorizedAdmins $authorizedAdmins -SafeAccounts $SafeAccounts

    $usersToDisable = $plan.UsersToDisable
    $adminsToDemote = $plan.AdminsToDemote

    Write-ReconciliationLog -Message "Plan: disable $($usersToDisable.Count) user(s) [$($usersToDisable.SamAccountName -join ', ')]; revoke Domain Admins from $($adminsToDemote.Count) account(s) [$($adminsToDemote.SamAccountName -join ', ')]." -EventId 1001

    if ($usersToDisable.Count -eq 0 -and $adminsToDemote.Count -eq 0) {
        Write-ReconciliationLog -Message "Nothing to do." -EventId 1007
        return
    }

    if (-not $Unattended -and -not $Force) {
        Write-Host ""
        $answer = Read-Host "Type YES to apply the changes above, anything else to abort"
        if ($answer -ne 'YES') {
            Write-ReconciliationLog -Message "Run aborted by operator; no changes made." -EntryType Warning -EventId 1006
            return
        }
    }

    $disabledCount = 0
    $revokedCount = 0

    foreach ($user in $usersToDisable) {
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Disable-ADAccount")) {
            try {
                Disable-ADAccount -Identity $user.SamAccountName
                Write-ReconciliationLog -Message "Disabled user: $($user.SamAccountName)" -EventId 1002
                $disabledCount++
            } catch {
                Write-ReconciliationLog -Message "Failed to disable $($user.SamAccountName): $_" -EntryType Error -EventId 1003
            }
        }
    }

    foreach ($admin in $adminsToDemote) {
        if ($PSCmdlet.ShouldProcess($admin.SamAccountName, "Remove-ADGroupMember -Identity 'Domain Admins'")) {
            try {
                Remove-ADGroupMember -Identity 'Domain Admins' -Members $admin.SamAccountName -Confirm:$false
                Write-ReconciliationLog -Message "Revoked Domain Admins from: $($admin.SamAccountName)" -EventId 1004
                $revokedCount++
            } catch {
                Write-ReconciliationLog -Message "Failed to remove $($admin.SamAccountName) from Domain Admins: $_" -EntryType Error -EventId 1005
            }
        }
    }

    Write-ReconciliationLog -Message "Run complete. Disabled $disabledCount user(s), revoked admin rights from $revokedCount account(s)." -EventId 1007
}

# Only run when executed directly (e.g. `pwsh -File` or `.\Check-ADUsers.ps1`).
# Dot-sourcing (". .\Check-ADUsers.ps1") loads the functions above without
# running anything, which is what the Pester tests rely on.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-CheckADUsers
}

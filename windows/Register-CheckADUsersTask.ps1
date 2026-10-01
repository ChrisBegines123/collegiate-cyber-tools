<#
.SYNOPSIS
    Registers a Scheduled Task that runs Check-ADUsers.ps1 on a recurring
    interval, unattended - the Windows equivalent of the systemd timer used
    for the Linux user_priv_audit.sh script.

.DESCRIPTION
    Creates (or replaces) a Scheduled Task that invokes Check-ADUsers.ps1 in
    unattended mode (-UsersFile/-AdminsFile) every IntervalMinutes, starting
    immediately and repeating indefinitely. Check-ADUsers.ps1 itself writes
    every run's plan/actions to the "AD Account Reconciliation" event log;
    Task Scheduler's own history additionally records run times and exit
    codes.

.PARAMETER ScriptPath
    Path to Check-ADUsers.ps1 on the machine the task will run on.

.PARAMETER UsersFile
    Path to the authorized-users list, passed through to Check-ADUsers.ps1.

.PARAMETER AdminsFile
    Path to the authorized-admins list, passed through to Check-ADUsers.ps1.

.PARAMETER IntervalMinutes
    How often to run. Default 5.

.PARAMETER TaskName
    Name of the Scheduled Task. Default "Check-ADUsers".

.PARAMETER Credential
    Account to run the task as. It needs rights to disable AD accounts and
    modify Domain Admins membership. If omitted, the task runs as SYSTEM,
    which only has those rights when run on a Domain Controller itself -
    on a member server, pass a delegated service account's credentials
    instead.

.EXAMPLE
    .\Register-CheckADUsersTask.ps1 -ScriptPath C:\ADReconciliation\Check-ADUsers.ps1 -UsersFile C:\ADReconciliation\users.txt -AdminsFile C:\ADReconciliation\admins.txt

    Registers the task to run as SYSTEM every 5 minutes. Only appropriate
    when run on a Domain Controller.

.EXAMPLE
    .\Register-CheckADUsersTask.ps1 -ScriptPath C:\ADReconciliation\Check-ADUsers.ps1 -UsersFile C:\ADReconciliation\users.txt -AdminsFile C:\ADReconciliation\admins.txt -Credential (Get-Credential) -IntervalMinutes 10

    Registers the task to run as a delegated service account every 10 minutes.

.NOTES
    Must be run elevated (as Administrator) on the machine hosting the task.
    Requires the ScheduledTasks PowerShell module (built into Windows).

    Start Check-ADUsers.ps1 itself pointed at a deliberately-empty or
    obviously-wrong list first (or just run it by hand once) to confirm the
    plan looks right before trusting a 5-minute unattended loop with it - a
    stale authorized-users file will otherwise disable a legitimate
    teammate's account on the next run.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [Parameter(Mandatory)][string]$UsersFile,
    [Parameter(Mandatory)][string]$AdminsFile,
    [int]$IntervalMinutes = 5,
    [string]$TaskName = 'Check-ADUsers',
    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $ScriptPath)) {
    throw "ScriptPath not found: $ScriptPath"
}
if (-not (Test-Path -Path $UsersFile)) {
    throw "UsersFile not found: $UsersFile"
}
if (-not (Test-Path -Path $AdminsFile)) {
    throw "AdminsFile not found: $AdminsFile"
}

$argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -UsersFile `"$UsersFile`" -AdminsFile `"$AdminsFile`""

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentList
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew

if ($Credential) {
    $principal = New-ScheduledTaskPrincipal -UserId $Credential.UserName -LogonType Password -RunLevel Highest
} else {
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister existing scheduled task')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
}

if ($PSCmdlet.ShouldProcess($TaskName, "Register scheduled task (every $IntervalMinutes minute(s))")) {
    if ($Credential) {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -User $Credential.UserName -Password $Credential.GetNetworkCredential().Password -RunLevel Highest | Out-Null
    } else {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
            -Principal $principal | Out-Null
    }
    Write-Host "Registered scheduled task '$TaskName' to run every $IntervalMinutes minute(s)." -ForegroundColor Green
}

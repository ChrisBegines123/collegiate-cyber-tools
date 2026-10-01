This is for common Windows/Active Directory scripts.

Check-ADUsers.ps1
-------------------
Reconciles AD users and Domain Admins membership against an authorized
users list and an authorized admins list: disables any enabled user not on
the authorized list, and revokes Domain Admins from anyone not on the
authorized admins list. Interactive by default (prompts, requires typing
YES); pass -UsersFile/-AdminsFile for unattended mode. Every run logs to
the "AD Account Reconciliation" event log. Full parameter/example docs are
in the script's own comment-based help:
    Get-Help ./Check-ADUsers.ps1 -Full
See Check-ADUsers.Tests.ps1 for its Pester test suite (runs on any platform
via mocked AD/event log cmdlets).

Register-CheckADUsersTask.ps1
-------------------
Registers a Scheduled Task that runs Check-ADUsers.ps1 unattended on a
recurring interval - the Windows equivalent of the systemd timer used for
the Linux user_priv_audit.sh script. Must be run elevated (as
Administrator). Safe to re-run: it unregisters and replaces any existing
task of the same name. Full parameter docs:
    Get-Help ./Register-CheckADUsersTask.ps1 -Full

Usage:
    .\Register-CheckADUsersTask.ps1 -ScriptPath <path> -UsersFile <path> -AdminsFile <path> `
        [-IntervalMinutes 5] [-TaskName Check-ADUsers] [-Credential <PSCredential>]

  -ScriptPath       path to Check-ADUsers.ps1 on the machine the task runs on
  -UsersFile        authorized-users list, passed through to Check-ADUsers.ps1
  -AdminsFile       authorized-admins list, passed through to Check-ADUsers.ps1
  -IntervalMinutes  how often to run (default 5)
  -TaskName         Scheduled Task name (default "Check-ADUsers")
  -Credential       account to run the task as. Needs rights to disable AD
                    accounts and modify Domain Admins. Omit to run as SYSTEM,
                    which only has those rights when run directly on a
                    Domain Controller - on a member server, pass a delegated
                    service account's credentials instead.

Before registering the task, dry-run Check-ADUsers.ps1 itself against your
real lists with -WhatIf (works even in unattended mode - it previews the
plan and logs it, but disables/revokes no one):
    .\Check-ADUsers.ps1 -UsersFile C:\ADReconciliation\users.txt -AdminsFile C:\ADReconciliation\admins.txt -WhatIf
Once the plan it prints looks right, register the task for real:
    .\Register-CheckADUsersTask.ps1 -ScriptPath C:\ADReconciliation\Check-ADUsers.ps1 `
        -UsersFile C:\ADReconciliation\users.txt -AdminsFile C:\ADReconciliation\admins.txt

After registering:
    Get-ScheduledTask -TaskName Check-ADUsers | Get-ScheduledTaskInfo
    Get-EventLog -LogName "AD Account Reconciliation" -Newest 20
    # or: Event Viewer > Windows Logs > AD Account Reconciliation

To uninstall: Unregister-ScheduledTask -TaskName Check-ADUsers -Confirm:$false

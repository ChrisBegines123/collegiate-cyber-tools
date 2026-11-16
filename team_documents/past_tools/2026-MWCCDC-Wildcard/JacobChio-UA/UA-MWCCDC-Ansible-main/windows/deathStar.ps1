function deathStar() {
    try {
        # Disable Local Guest User
        $guest = Get-LocalUser -Name "Guest" -ErrorAction Stop
        if ($guest.Enabled) {
            Disable-LocalUser -Name "Guest"
            Write-Output "Local Guest Account has been disabled."
        }
        else {
            Write-Output "Local Guest Account is already disabled."
        }
    }
    catch {
        Write-Verbose "Error disabling local guest account: $_"
    }

    try {
        # Remove All Non Administrators from Local Groups      
        $groups = Get-LocalGroup
        foreach ($group in $groups) {
            $members = Get-LocalGroupMember -Group $group.Name -ErrorAction Stop 
            foreach ($member in $members) {
                if ($member.Name -ne "Administrator" -and $member.Name -ne "ccdcteam.com\Administrator") {
                    Remove-LocalGroupMember -Group $group.Name -Member $member.Name -ErrorAction Stop
                    Write-Output "Removed $($member.Name) from $($group.Name)"
                    $remainingMembers = Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue # Print remaining members in each group
                    Write-Verbose "Remaining members in $($group.Name):"
                    foreach ($remainingMember in $remainingMembers) {
                        Write-Verbose "  $($remainingMember.Name)"
                    }
                }
            }
        }
        Write-Output "All non-administrators have been removed from local groups."
    }
    catch {
        Write-Verbose "Error removing non-administrators from local groups: $_"
    }
}

deathStar

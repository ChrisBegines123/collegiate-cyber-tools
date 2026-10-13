# Gather the command line arguments for the script
param(
    [string]$Username,
    [string]$NewPassword
)

# Import active directory module as we will likely be working in AD
Import-Module ActiveDirectory

# Try to reset the password for the specified user
try {
    # Create a SecureString object from the new password as that is what the Set-ADAccountPassword cmdlet expects
    # -AsPlainText is to say "we know its plain text, do it anyways" with the force
    $SecurePassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
    # Identity finds the user, Newpassword sets the new password, and reset actually resets it
    Set-ADAccountPassword `
        -Identity $Username `
        -NewPassword $SecurePassword `
        -Reset

    Write-Host "Password successfully reset for $Username"
}
catch {
    Write-Host "Failed to reset password: $($_.Exception.Message)"
}
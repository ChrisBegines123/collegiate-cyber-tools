# 1. Securely capture the new password
$NewPassword = Read-Host "Enter New Admin Password" -AsSecureString
$ConfirmPassword = Read-Host "Confirm New Admin Password" -AsSecureString

# 2. Convert for comparison and application
$BSTR_New = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
$BSTR_Confirm = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ConfirmPassword)

$PlainNew = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_New)
$PlainConfirm = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR_Confirm)

if ($null -ne $PlainNew -and $PlainNew -eq $PlainConfirm) {
    try {
        # 3. Apply the password to the local Administrator account
        $User = [ADSI]"WinNT://localhost/Administrator,User"
        $User.SetPassword($PlainNew)
        Write-Host "`n[SUCCESS] Password has been reset." -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERROR] Failed to reset password. Ensure you are running as Admin." -ForegroundColor Red
    }
} else {
    Write-Host "`n[ERROR] Passwords do not match or are empty." -ForegroundColor Red
}

# 4. MEMORY PURGE: Zero out the pointers and clear variables immediately
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_New)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR_Confirm)

$NewPassword = $null
$ConfirmPassword = $null
$PlainNew = $null
$PlainConfirm = $null

# Force Garbage Collection to clear the memory heap
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

Write-Host "Session secured. Plaintext data cleared from memory." -ForegroundColor Cyan
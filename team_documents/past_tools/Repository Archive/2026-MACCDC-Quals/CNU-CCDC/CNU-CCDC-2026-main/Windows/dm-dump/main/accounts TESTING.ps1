# Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

   
function WIN-localAccounts() {

    Write-Warning "localAccounts STARTING"
    Write-Host

    # Define Paths
    $localaccountpath = echo C:\Users\$env:UserName\Desktop\users.txt
    $READMEaccounts = echo C:\Users\$env:UserName\Desktop\READMEaccounts.txt
    $localaccountadd = echo C:\Users\$env:UserName\Desktop\localaccountadd.txt
    $localaccountremove = echo C:\Users\$env:UserName\Desktop\localaccountremove.txt

    # Add Accounts from README
    New-Item $READMEaccounts
    Write-Host "Paste accounts into READMEaccounts.txt in Desktop. Make sure it is only accounts and 1 account per line."
    pause

    # Get Local Accounts
    New-Item $localaccountpath
    $accounts = Get-Wmiobject Win32_UserAccount -filter 'LocalAccount=TRUE' | select-object -expandproperty Name
    $accounts | Out-File -FilePath $localaccountpath

    # Filter Local Accounts
    (Get-Content -path $localaccountpath -Raw) -replace 'WDAGUtilityAccount','' | Set-Content -Path $localaccountpath
    (Get-Content -path $localaccountpath -Raw) -replace 'accountforguest','' | Set-Content -Path $localaccountpath
    (Get-Content -path $localaccountpath -Raw) -replace 'accountforadmin','' | Set-Content -Path $localaccountpath
    (Get-Content -path $localaccountpath -Raw) -replace 'DefaultAccount','' | Set-Content -Path $localaccountpath
    (gc $localaccountpath) | ? {$_.trim() -ne "" } | Set-Content $localaccountpath
    
    # Read Defenitions
    $localaccountobject = Get-Content $localaccountpath
    $readmeaccountobject = Get-Content $READMEaccounts

    # Compare Accounts
    New-Item $localaccountadd
    New-Item $localaccountremove
    Compare-Object $localaccountobject $readmeaccountobject | Where-Object {$_.SideIndicator -eq "<="} | Set-Content -Path $localaccountremove
    Compare-Object $localaccountobject $readmeaccountobject | Where-Object {$_.SideIndicator -eq "=>"} | Set-Content -Path $localaccountadd
    (Get-Content -path $localaccountadd -Raw) -replace '@{InputObject=','' | Set-Content -Path $localaccountadd
    (Get-Content -path $localaccountadd -Raw) -replace '; SideIndicator==>}','' | Set-Content -Path $localaccountadd
    (Get-Content -path $localaccountremove -Raw) -replace '@{InputObject=','' | Set-Content -Path $localaccountremove
    (Get-Content -path $localaccountremove -Raw) -replace '; SideIndicator=<=}','' | Set-Content -Path $localaccountremove


    # Add New Accounts
    foreach($line in Get-Content $localaccountadd) {
        
        New-LocalUser -Name $line -NoPassword

    }

    # Remove Old Accounts

    foreach($line in Get-Content $localaccountremove) {
        
        Remove-LocalUser -Name $line

    }

    # Remove Files

    Remove-Item $localaccountpath
    Remove-Item $localaccountadd
    Remove-Item $localaccountremove
    Remove-Item $READMEaccounts

    Write-Host "localAccounts DONE" -ForegroundColor blue -BackgroundColor green
    Write-Host

}

WIN-localAccounts

pause
## Get-AdminMembers.ps1


## Clean up broken administrators

$administrators = @(
([ADSI] "WinNT://./Administrators").psbase.Invoke('Members') |
%  {
  $_.GetType().InvokeMember('AdsPath','GetProperty',$null,$($_),$null)
}
) -match '^WinNT';

$administrators = $administrators -replace "WinNT://",""

$administrators

foreach ($administrator in $administrators)
{

if ($administrator -like "$env:COMPUTERNAME/*" -or $administrator -like "AzureAd/")
{
    continue;
}

Remove-LocalGroupMember -group "administrators" -member $administrator
}

## Get domain admins
Get-ADGroupMember 'Domain Admins' | Select-Object Name, SamAccountName
Get-ADGroupMember 'Enterprise Admins' | Select-Object Name, SamAccountName
Get-LocalGroupMember 'Administrators' | Select-Object Name, SamAccountName
pause

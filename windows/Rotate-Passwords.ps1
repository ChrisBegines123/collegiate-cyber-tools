<#
.SYNOPSIS
    Rotates the password of every enabled AD user, or rolls users back to
    the passwords recorded in an earlier file.

.DESCRIPTION
    With no parameters, every enabled user except Administrator, krbtgt,
    Guest and the account running the script gets a new random password.
    The new passwords are written, encrypted with a key derived from the
    master password, to passwords_<timestamp>.csv next to this script.
    Read them back with Get-Password.ps1.

    With -RollbackFile, no passwords are generated. Each user listed in the
    file is reset to the password recorded there instead. The same accounts
    are protected, and users not listed in the file are left alone. A
    rollback also writes a new passwords_<timestamp>.csv, so the newest file
    always holds the passwords this script set last.

.PARAMETER RollbackFile
    The file to roll back to. Either:
      - a passwords_*.csv written by an earlier run of this script (enter
        the master password that was used for that run), or
      - a plaintext CSV with a header row naming a username column
        (username, user, samaccountname, account or login) and a password
        column (password, pass or pw), such as the account list handed out
        at the start of a competition.
    The whole file is read and decrypted before any password is changed, so
    a wrong master password or a malformed file changes nothing.

.EXAMPLE
    .\Rotate-Passwords.ps1

.EXAMPLE
    .\Rotate-Passwords.ps1 -RollbackFile .\passwords_20261114_093000.csv

.EXAMPLE
    .\Rotate-Passwords.ps1 -RollbackFile C:\initial_accounts.csv
#>
param(
	[string]$RollbackFile
)

Import-Module ActiveDirectory -ErrorAction Stop
Add-Type -AssemblyName System.Web

$protected = @('Administrator', 'krbtgt', 'Guest', $env:USERNAME)

$rollbackLines = $null
$rollbackIsEncrypted = $false
if ($RollbackFile) {
	$rollbackLines = @(Get-Content -LiteralPath $RollbackFile -ErrorAction Stop | Where-Object { $_ })
	if ($rollbackLines.Count -eq 0) {
		Write-Error "$RollbackFile is empty. No passwords were changed."
		return
	}
	$rollbackIsEncrypted = $rollbackLines[0] -match '^salt,'
}

function Get-DerivedKey {
	param([string]$Master, [byte[]]$Salt)
	$kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
		$Master,
		$Salt,
		600000,
		[System.Security.Cryptography.HashAlgorithmName]::SHA256
	)
	try {
		, $kdf.GetBytes(32)
	} finally {
		$kdf.Dispose()
	}
}

$outFile = Join-Path $PSScriptRoot ("passwords_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
	$(Read-Host "Enter master password" -AsSecureString)
)
try {
	$master = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
	[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
	Remove-Variable bstr
}
$salt = New-Object byte[] 16
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($salt)
$rng.Dispose()
Remove-Variable rng
$key = Get-DerivedKey -Master $master -Salt $salt
if ($rollbackIsEncrypted) {
	# The old file has its own salt, so it needs its own key.
	$rollbackSalt = [Convert]::FromBase64String(($rollbackLines[0] -split ',', 2)[1])
	$rollbackKey = Get-DerivedKey -Master $master -Salt $rollbackSalt
}
Remove-Variable master

function New-RandomPassword {
	param([int]$Length = 20)
	do {
		$pw = [System.Web.Security.Membership]::GeneratePassword($Length, 4)
	} until (
		$pw -cmatch '[a-z]' -and $pw -cmatch '[A-Z]' -and $pw -match '\d' -and
		$pw -match '^[A-Za-z0-9!@#$%^*()_+=?.,:-]+$'
	)
	$pw
}

# Work out every (user, password) pair before touching AD.
$targets = New-Object System.Collections.Generic.List[object]
if (-not $RollbackFile) {
	$action = 'changed'
	Get-ADUser -Filter 'Enabled -eq $true' |
	ForEach-Object {
		$targets.Add([PSCustomObject]@{
			User     = $_.SamAccountName
			Password = ConvertTo-SecureString $(New-RandomPassword -Length 16) -AsPlainText -Force
		})
	}
} elseif ($rollbackIsEncrypted) {
	$action = 'rolled back'
	foreach ($line in ($rollbackLines | Select-Object -Skip 2)) {
		$user, $cipher = $line -split ',', 2
		try {
			$secure = ConvertTo-SecureString -String $cipher -Key $rollbackKey -ErrorAction Stop
		} catch {
			Write-Error "Failed to decrypt the entry for ${user} in ${RollbackFile}: wrong master password, or the file is corrupt. No passwords were changed."
			return
		}
		$targets.Add([PSCustomObject]@{ User = $user; Password = $secure })
	}
	Remove-Variable rollbackKey
} else {
	$action = 'rolled back'
	$rows = @($rollbackLines | ConvertFrom-Csv)
	if ($rows.Count -eq 0) {
		Write-Error "$RollbackFile has a header row but no users. No passwords were changed."
		return
	}
	$columns = $rows[0].PSObject.Properties.Name
	$userColumn = $columns | Where-Object { $_ -match '^\s*(user(name)?|samaccountname|account|login)\s*$' } | Select-Object -First 1
	$passwordColumn = $columns | Where-Object { $_ -match '^\s*(pass(word)?|pw)\s*$' } | Select-Object -First 1
	if (-not $userColumn -or -not $passwordColumn) {
		Write-Error "$RollbackFile needs a header row with a username column and a password column (found: $($columns -join ', ')). No passwords were changed."
		return
	}
	foreach ($row in $rows) {
		$user = "$($row.$userColumn)".Trim()
		$plain = $row.$passwordColumn
		if (-not $user -or -not $plain) {
			Write-Error "$RollbackFile has a row with a missing username or password. No passwords were changed."
			return
		}
		$targets.Add([PSCustomObject]@{
			User     = $user
			Password = ConvertTo-SecureString $plain -AsPlainText -Force
		})
	}
	Remove-Variable rows, row, plain
}

Set-Content $outFile "salt,$([Convert]::ToBase64String($salt))"
Add-Content $outFile "username,password"

$targets |
Where-Object { $_.User -notin $protected } |
ForEach-Object {
	$user = $_.User
	$pw = $_.Password
	try {
		Set-ADAccountPassword -Identity $user `
			-NewPassword $pw `
			-Reset -ErrorAction Stop
		Add-Content $outfile "$user,$(ConvertFrom-SecureString -SecureString $pw -Key $key)"
		Write-Host "Password $action for $user"
	} catch {
		Write-Error "Something went wrong when attempting to change the password for ${user}: $($_.Exception.Message)"
	}
}

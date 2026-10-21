Import-Module ActiveDirectory -ErrorAction Stop
Add-Type -AssemblyName System.Web

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
Set-Content $outFile "salt,$([Convert]::ToBase64String($salt))"
Add-Content $outFile "username,password"
$kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
	$master,
	$salt,
	600000,
	[System.Security.Cryptography.HashAlgorithmName]::SHA256
)
$key = $kdf.GetBytes(32)
$kdf.Dispose()
Remove-Variable kdf
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

Get-ADUser -Filter 'Enabled -eq $true' |
Where-Object { $_.SamAccountName -notin @('Administrator', 'krbtgt', 'Guest', $env:USERNAME) } |
ForEach-Object {
	$user = $_.SamAccountName
	$pw = ConvertTo-SecureString $(New-RandomPassword -Length 16) -AsPlainText -Force
	try {
		Set-ADAccountPassword -Identity $user `
			-NewPassword $pw `
			-Reset -ErrorAction Stop
		Add-Content $outfile "$user,$(ConvertFrom-SecureString -SecureString $pw -Key $key)"
		Write-Host "Password changed for $user"
	} catch {
		Write-Error "Something went wrong when attempting to change the password for ${user}: $($_.Exception.Message)"
	}
}

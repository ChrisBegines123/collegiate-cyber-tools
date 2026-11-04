param(
	[String]$User,
	[String]$File
)

if (-not $File) {
	$File = Get-ChildItem -Path . -Filter 'passwords_*.csv' |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1 -ExpandProperty FullName
}
if (-not $File -or -not (Test-Path $File)) {
	Write-Error "Could not find a passwords_*.csv file in the current directory, use -File to look somewhere else"
	return
}

$lines = Get-Content $File
$saltLine, $headerLine = $lines[0], $lines[1]
if ($saltLine -notmatch '^salt,') {
	Write-Error "$File does not look like a valid passwords file (missing salt line)"
	return
}
$salt = [Convert]::FromBase64String(($saltLine -split ',', 2)[1])

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
	$(Read-Host "Enter master password" -AsSecureString)
)
try {
	$master = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
	[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
	Remove-Variable bstr
}
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

function ConvertTo-Plaintext([securestring]$Secure) {
	[System.Net.NetworkCredential]::new('', $Secure).Password
}

$records = $lines | Select-Object -Skip 2 | Where-Object { $_ }
if ($User) {
	$records = $records | Where-Object { ($_ -split ',', 2)[0] -eq $User }
	if (-not $records) {
		Write-Error "No entry for user '$User' in $File"
		return
	}
}

foreach ($line in $records) {
	$username, $cipher = $line -split ',', 2
	try {
		$secure = ConvertTo-SecureString -String $cipher -Key $key -ErrorAction Stop
		[PSCustomObject]@{
			Username = $username
			Password = ConvertTo-Plaintext $secure
		}
	} catch {
		Write-Error "Failed to decrypt entry for ${username}: wrong master password, or the file is corrupt"
	}
}
Remove-Variable key

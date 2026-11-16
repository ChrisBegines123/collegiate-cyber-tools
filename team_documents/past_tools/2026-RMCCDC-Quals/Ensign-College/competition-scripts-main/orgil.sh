# Define the mapping of users to their specific 16-character passwords
$UserPasswords = @{
  "Paul.Pride"      = "P@u1!Prid3#2026$"
  "Joseph.Flaco"    = "J0s3ph!F1@c0#V7*"
  "Charles.Labelle" = "Ch@r13s!L@b3ll3^"
  "Denise.Colon"    = "D3n1s3!C010n&99"
  "Marie.C.Valez"   = "M@r13!V@13z*88#"
  "Major.Taung"     = "M@j0r!T@ung#X77"
  "Tyler.A.Rock"    = "Ty13r!R0ck#Z123"
}
 
# Loop through the table and apply the changes
foreach ($User in $UserPasswords.Keys) {
   $SecurePassword = ConvertTo-SecureString $UserPasswords[$User] -AsPlainText -Force
   try {
      Set-ADAccountPassword -Identity $User -Reset -NewPassword $SecurePassword
       Write-Host "SUCCESS: Password updated for $User" -ForegroundColor Green
   }
   catch {
       Write-Host "ERROR: Could not update $User. Ensure account exists on DC." -ForegroundColor Red
   }
}
 
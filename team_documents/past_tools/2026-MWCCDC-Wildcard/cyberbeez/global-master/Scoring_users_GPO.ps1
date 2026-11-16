Write-Host "Hey Cam Lets get this dub, got a few questions for us to answer"

$ou = Read-Host -Prompt 'Enter the comp users OU name'
$DomainName = Read-Host 'Enter the domain name'
$com = Read-Host 'Enter the extension (.com, .net, .local, etc.)'

New-GPO -Name 'Comp Users' -Comment 'For Stupid Scoring Users' | New-GPLink -Target "OU=$ou,DC=$DomainName,DC=$com" -Enforced Yes
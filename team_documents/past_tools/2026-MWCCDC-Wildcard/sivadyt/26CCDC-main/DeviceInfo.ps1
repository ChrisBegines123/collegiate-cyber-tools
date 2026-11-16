$ipconfig = ipconfig /all | Select-String -Pattern 'Host Name|Physical Address|IPv4 Address'
#$osVersion = (ver) -replace -replace '$$|$$', ''
#$osVersion = $osVersion.Trim()

$device = [ordered]@{
    Name       = ($ipconfig | Where-Object {$_.Line -match 'Host Name'}).Line.Split(':')[1].Trim()
    IPAddress  = ($ipconfig | Where-Object {$_.Line -match 'IPv4 Address'}).Line.Split(':')[1].Trim().Split('(')[0]
    MAC        = ($ipconfig | Where-Object {$_.Line -match 'Physical Address'}).Line.Split(':')[1].Trim()
    #OS Version = $osVersion
}
$device | Format-List

while ($true) {
Get-NetTCPConnection -State Established |
Select LocalAddress,LocalPort, RemoteAddress,RemotePort,OwningProcess,@{Name="cmdline";Expression={(Get-WmiObject Win32_Process -filter "ProcessId" = $($_.OwningProcess):).commandline}} | 
Where-Object {$_.RemoteAddress -NE "127.0.0.1" -AND $_.RemoteAddress -NE "127.0.0.0" -AND $_.RemoteAddress -NE "::" -AND $_.RemoteAddress -NE "::1" -AND $_.RemotePort -NE "80" -AND $_.RemotePort -NE "443"};
Start-Sleep 5;
clear;
}
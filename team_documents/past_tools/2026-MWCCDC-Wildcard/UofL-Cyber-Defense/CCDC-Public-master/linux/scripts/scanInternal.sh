#!/bin/sh

#Internal
echo "Iternal Network scan" > Output.txt
nmap 172.20.240.10 >> Output.txt 
nmap 172.20.240.20 >> Output.txt 

#Public
echo "Public Network Scan" >> Output.txt
nmap 172.20.241.20 >> Output.txt
nmap 172.20.242.30 >> Output.txt
nmap 172.20.241.40 >> Output.txt

#User
echo "user network scan" >> Output.txt
nmap 172.20.242.10 >> Output.txt
nmap 172.20.242.200 >> Output.txt 

exit 0
# Check Bind Configuration
sudo named-checkconf

# Check Zone Files
sudo named-checkzone ccdcteam01.internal /etc/bind/db.ccdcteam01.internal
sudo named-checkzone ccdcteam01.user /etc/bind/db.ccdcteam01.user
sudo named-checkzone ccdcteam01.public /etc/bind/db.ccdcteam01.public

sudo named-checkzone 240.20.172.in-addr.arpa /etc/bind/db.172.20.240
sudo named-checkzone 242.20.172.in-addr.arpa /etc/bind/db.172.20.242
sudo named-checkzone 241.20.172.in-addr.arpa /etc/bind/db.172.20.241

# restart Bind Service
sudo systemctl restart bind9

# Test DNS Forward Lookup
dig_ @localhost ns1.ccdcteam01.internal
dig_ @localhost ad-server.ccdcteam01.user
dig_ @localhost webmail.ccdcteam01.public

# Test Reverse DNS Lookup
dig_ @localhost -x 172.20.240.10
dig_ @localhost -x 172.20.242.200
dig_ @localhost -x 172.20.241.40

#!/bin/bash

function startup() {
    service="bind9"
    variables=${1-DEFAULT};
    serv="service $service status ";
    $serv  > fuckshit.txt ;
    stat="grep dead fuckshit.txt";
    $stat;
    match="grep --only-matching dead fuckshit.txt";
   
    if [[ "$match"=="true" ]]
    then
        service $service start
        sleep 1
        service $service status
    fi;

}

#startup

function backup(){
    mkdir -p /etc/restore-bind
    cp -rp --no-clobber /etc/bind /etc/restore-bind;
}


backup


function make_configs(){

    file_records="/etc/bind/db.records"
    file_zones="/etc/bind/named.conf.local"
    file_security="/etc/bind/named.conf.options"
    TTL="\$TTL"

    
    read -p 'what is your host name: ' primary_host_name;
    read -p 'what is your domain: ' domain_name;
    read -p 'what is your IP ADDR: ' local_ip;
    read -p 'what is secondary host name: ' secondary_host_name;
    read -p 'what is secondary IP ADDR: ' secondary_ip;
    read -p 'what is mail host name: ' mail_host_name;
    read -p 'what is mail IP ADDR: ' mail_ip;
    rev_local_ip=$(printf "$local_ip" | awk -F '.' '{print $3,$2,$1}' OFS='.');
    rev_secondary_ip=$(printf "$secondary_ip" | awk -F '.' '{print $3,$2,$1}' OFS='.');
    rev_mail_ip=$(printf "$mail_ip" | awk -F '.' '{print $3,$2,$1}' OFS='.');



    echo "$TTL  3600
@	IN 	SOA	 $primary_host_name.$domain_name.local. $secondaryhostname.$domain_name.local. (
			      2     ; Serial
			 604800     ; Refresh 
			  86400		; Retry
			2419200     ; Expire
			 604800 )   ; Negative Cache TTL

@	IN 	NS	$primary_host_name.$domain_name.local.
@	IN 	NS	$secondary_host_name.$domain_name.local.
@	IN 	MX	10	$mail_host_name.$domain_name.local.
$primary_host_name	IN 	A	$local_ip
$secondary_host_name	IN	A	$secondary_ip
$mail_host_name	IN	A	$mail_ip
www	IN	CNAME	@
10	IN	PTR	$primary_host_name.$domain_name.local.
20	IN	PTR	$secondary_host_name.$domain_name.local.
30	IN	PTR	$mail_host_name.$domain_name.local." > $file_records;




echo "zone \"$domain_name.local\" {
	type master;
	file \"/etc/bind/db.records\";
	allow-transfer {\"none\";};
};

zone \"$rev_local_ip.in-addr.arpa\" {
	type master;
file \"/etc/bind/db.records\";
allow-transfer{\"none\";};
};

zone \"$rev_secondary_ip.in-addr.arpa\" {
	type master;
file \"/etc/bind/db.records\";
allow-transfer{\"none\";};
};

zone \"$rev_mail_ip.in-addr.arpa\" {
	type master;
file \"/etc/bind/db.records\";
allow-transfer{\"none\";};
};

logging {
	channel query.log {
	file \"/var/lib/bind/query.log\" size 40m;
	severity debug 3;
	};
	category queries {query.log;};
};" > $file_zones;



echo "acl \"allow\"	{
	$local_ip;
    127.0.0.1;
	$secondary_ip;
};

options	{
directory \"/var/cache/bind\";

version none;
	server-id none;
	empty-zones-enable no;
	allow-recursion {allow;};
	allow-query-cache {any;};
	allow-transfer {none;};
	
	forwarders {
		8.8.8.8;
		8.8.4.4;
};
	dnssec-enable yes;
	dnssec-validation yes;
	
	auth-nxdomain no; 	#conform to RFC1035
	listen-on port 53 {allow;};
	listen-on-v6 {none;};
};
" > $file_security;




touch /var/lib/bind/query.log
chown bind:bind /var/lib/bind/query.log
chmod 750 /var/lib/bind/query.log
chown root:bind $file_records;
chown root:bind $file_zones;
chown root:bind $file_security;
chmod 750 $file_records
chmod 750 $file_zones
chmod 750 $file_security


}   


make_configs


echo "The configs have been made and default configs have been backed up to /etc/restore_bind";
echo "Checks have not been made look at after configuration in dooms day on what to do";
echo "if everything returns no errors bind needs restart";


exit 0

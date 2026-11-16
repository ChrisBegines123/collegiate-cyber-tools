#!/bin/bash
# finish forensics questions before running this. REMEMBER WHAT HAPPENED IN ROUND 2 of CP XII.

user="turbo"
echo "Starting ..."

echo "Updating Apache..."
sudo apt-get install apache2

echo "Backing up files..."
sudo cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
sudo cp /etc/apache2/conf-enabled/security.conf /etc/apache2/conf-enabled/security.conf.bak

echo "Installing security modules..."
sudo apt-get install libapache2-modsecurity
sudo apt-get install libapache2-mod-evasive
sudo a2enmod headers
sudo service apache2 restart

echo 'Rememeber to set the following:
    /etc/apache2/apache2.conf
        KeepAlive On
        KeepAliveTimeout 5
        HostnameLookups On
        LogLevel error
        FileETag None
        TraceEnable off
        MaxRequestPerChild 10000

        <IfModule mod_headers.c>
            Header always append X-FRAME-OPTIONS DENY
        </IfModule>

        <Directory /path/to/htdocs>
            Options -Indexes -Includes -ExecCGI
            Order allow,deny
            Allow from all
        </Directory>
    /etc/apache2/conf-enabled/security.conf
        ServerTokens Prod
        ServerSignature Off
        Header set X-Content-Type-Options: "nosniff"
    /etc/apache2/modsecurity/modsecurity.conf
        SecRuleEngine On
    /etc/apache2/mods-enabled/security2.conf
        IncludeOptional "/usr/share/modsecurity-crs/*.conf"
        ​IncludeOptional "/usr/share/modsecurity-crs/base_rules/*.conf
'
sleep 10
sudo nano /etc/apache2/apache2.conf
sleep 10
sudo nano /etc/apache2/conf-enabled/security.conf
sudo mv /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf.
sleep 10
sudo nano /etc/apache2/modsecurity/modsecurity.conf
sleep 10
sudo nano /etc/apahce2/mods-enabled/security2.conf
sudo apt-get install git
sudo git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git
cd owasp-modsecurity-crs
sudo mv crs-setup.conf.example /etc/modsecurity/crs-setup.conf

if [ "$true" ]; then
    # Control will enter here if $DIRECTORY exists.
    echo e
else
    sudo mkdir /etc/modsecurity/rules
    cd rules 
    sudo cp -- *glob* /etc/modsecurity/rules
fi

echo 'Remember to add the following:
    IncludeOptional /etc/modsecurity/*.conf
    Include /etc/modsecurity/rules/*.conf
'
sleep 5
sudo nano /etc/apache2/mods-enabled/security2.conf

sudo chown -R 750 /etc/apache2/bin /etc/apache2/conf
sudo chmod 511 /usr/sbin/apache2
sudo chmod 750 /var/log/apache2/
sudo chmod 750 /etc/apache2/conf/
sudo chmod 640 /etc/apache2/conf/*
sudo chgrp -R $user /etc/apache2/conf

sudo a2dismod userdir
sudo a2dismod suexec
sudo a2dismod cgi
sudo a2dismod cgid
sudo a2dismod include


sudo service apache2 restart

echo "... script has finished."

# https://stigviewer.com/stig/apache_server_2.0unix/
# https://www.acunetix.com/blog/articles/10-tips-secure-apache-installation/
# https://www.techrepublic.com/article/how-to-secure-your-apache-2-server-in-four-steps/
# https://phoenixnap.com/kb/setup-configure-modsecurity-on-apache
# http://bookofzeus.com/harden-ubuntu/hardening/apache/
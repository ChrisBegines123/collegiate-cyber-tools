#!/bin/bash
# finish forensics questions before running this. REMEMBER WHAT HAPPENED IN ROUND 2 of CP XII.
# DO NOT INSTALL MODSECURITY. IT DOES NOT WORK!!!

echo "Starting..."

echo "Updating nginx..."
sudo service apache2 stop
sudo apt-get install nginx
sudo service apache2 start

echo "Backing up files..."
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

echo "Remember to set:
    ssl_protocols TLSv1.2 TLSv1.3
    ServerTokens off
    add_header X-XSS-Protection \"1; mode=block\";
    add_header X-Frame-Options \"SAMEORIGIN\"
    add_header X-Content-Type-Options nosniff
    add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://ssl.google-analytics.com https://assets.zendesk.com https://connect.facebook.net; img-src 'self' https://ssl.google-analytics.com https://s-static.ak.facebook.com https://assets.zendesk.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://assets.zendesk.com; font-src 'self' https://themes.googleusercontent.com; frame-src https://assets.zendesk.com https://www.facebook.com https://s-static.ak.facebook.com https://tautt.zendesk.com; object-src 'none'\";
"
sleep 5
sudo nano /etc/nginx/nginx.conf

sudo service restart nginx.service

echo "... script has finished."

# https://www.acunetix.com/blog/web-security-zone/hardening-nginx/
# https://docs.nginx.com/nginx/admin-guide/security-controls/
# https://geekflare.com/nginx-webserver-security-hardening-guide/ 
# https://gist.github.com/plentz/6737338#file-nginx-conf-L33
# https://www.upguard.com/blog/10-tips-for-securing-your-nginx-deployment
SDP=("/etc/postfix")
DDP=("/mnt/backup/postfixB")
Dir=("/mnt/backup")
SYD=("/etc/sysconfig")
DOV=("/etc/dovecot")
SCB=("/mnt/backup/sysconfigB")
DOVB=("/mnt/backup/dovecotB")
#making a the directory and doing the stuff ig
if [ ! -d "$Dir" ]; then    
    mkdir -p "$Dir"
fi
cp -r "$SDP" "$DDP"
cp -r "$SYD" "$SCB"
cp -r "$DOV" "$DOVB"



crontab -r
#because I can. 
if systemctl list-units --type=service | grep -q crond; then
    CRON_SERVICE="crond"
else
    CRON_SERVICE="cron"
fi

# Again. because I can.
sudo systemctl stop "$CRON_SERVICE".service
echo "The $CRON_SERVICE service has been stopped, 6 7 ."

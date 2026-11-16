read -p "Enter User:" user
if [ "$user" == "" ]; then
  echo "No user entered. Exiting."
  exit 1
fi
if ! id -u "$user" >/dev/null 2>&1; then
  echo "User '$user' does not exist. Exiting."
  exit 1
else 
  echo "User '$user' exists."
fi
gpasswd -d "$user" wheel


#removing from wheel.
if [ $? -eq 0 ]; then
  echo "User '$user' hasthd been oblitorated."
else
  echo "Failed to remove user '$user' from wheel group. Exiting."
  exit 1
fi
#verify user does not have sudo access 
if id -nG "$user" | grep -qw wheel; then
  echo "User '$user' guess it didn't work still has sudo."
  exit 1
else
  echo "User '$user' L + ratio the job is done."
fi


#lock account
read -p "do you want to remove login for $user y/n: " wack
if [ "$wack" == "y" ]; then
  usermod -L "$user"
  if [ $? -eq 0 ]; then
    echo "User '$user' has been locked."
  else
    echo "Failed to lock user '$user'. Exiting."
  fi
else
  echo "User '$user' I see how it is."
fi


#kill sessions
read -p "blow up sessions y/n: " esplode
if [ "$esplode" == "y" ]; then
  pkill -u "$user"
  if [ $? -eq 0 ]; then
    echo "All sessions for user '$user' have been terminated."
  else
    echo "Failed to terminate sessions for user '$user'. Exiting."
  fi
else
  echo "User '$user' is still chilling."
  
fi


#esplode cronjobs or smthn probs wont work
crontab -u "$user" -l
read -p "do you want to remove cron jobs for $user y/n: " cron
if [ "$cron" == "y" ]; then
    crontab -u "$user" -r
    if [ $? -eq 0 ]; then
        echo "Cron jobs for user '$user' have been removed."
    else
        echo "Failed to remove cron jobs for user '$user'."
    fi
else
    echo "didn't do anythin."
fi
echo "things im probably missing but cant care enough to add: "
echo "groups"

groups "$user"

echo "checking lingering"
ls /var/lib/systemd/linger

echo "checking sudoers files"
grep -r "$user" /etc/sudoers /etc/sudoers.d 

echo "checking for processes"
ps -u "$user"


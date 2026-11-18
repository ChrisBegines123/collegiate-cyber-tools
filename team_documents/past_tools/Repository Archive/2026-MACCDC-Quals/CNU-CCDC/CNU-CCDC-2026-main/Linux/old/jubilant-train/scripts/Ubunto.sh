clear
echo "  _________________________________________________________________________________________________  "
echo " |OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO| "
echo " |O                                                                                               O| " 
echo " |O                 _______ ______          __  __    ____  ______ _______                        O| "
echo " |O                |__   __|  ____|   /\   |  \/  |  |  _ \|  ____|__   __|/\                     O| "
echo " |O                   | |  | |__     /  \  | \  / |  | |_) | |__     | |  /  \                    O| "
echo " |O                   | |  |  __|   / /\ \ | |\/| |  |  _ <|  __|    | | / /\ \                   O| "
echo " |O                   | |  | |____ / ____ \| |  | |  | |_) | |____   | |/ ____ \                  O| "
echo " |O                   |_|  |______/_/    \_\_|  |_|  |____/|______|  |_/_/    \_\                 O| "          
echo " |O                                                                                               O| "  
echo " |O                                                                                               O| " 
echo " |OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO| "
echo " |O                                                                                               O| "
echo " |O                                                                                               O| "            
echo " |O                                        'Linux Mode'                                           O| "                                    
echo " |O                                                                                               O| "
echo " |O                                                                                               O| "
echo " |OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO| "

# Delete prohibited files

#cd / --Uncomment on actual script run
find . -name "*.mp3" -type f -delete
find . -name "*.mp4" -type f -delete
find . -name "*.jpeg" -type f -delete
find . -name "*.png" -type f -delete
find . -name "*.dds" -type f -delete
find . -name "*.jpg" -type f -delete
find . -name "*.poop" -type f -delete
if ! command -v nmap &> /dev/null
then
    echo "Nmap not found, moving on..."
else
    sudo apt remove nmap
    echo "Nmap removed"
fi

if ! command -v hydra &> /dev/null
then
    echo "Hydra not found, moving on..."
else
    sudo apt remove hydra
    echo "Hydra removed"
fi

sudo apt update
sudo apt update firefox

# https://github.com/BiermanM/CyberPatriot-Scripts/blob/master/UbuntuScript.sh
# https://gist.github.com/bobpaw/a0b6828a5cfa31cfe9007b711a36082f
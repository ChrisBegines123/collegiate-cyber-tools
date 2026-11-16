## Ubuntu Checklist
Do forensics questions  

Run script
- what the script accomplishes:
  - Update
    - Updates the OS
    - Updates the kernel
    - Updates firefox
    - Updates libreoffice
    - Installs clamtk
  - Auto Update
    - Asks daily to update the machine
  - Finds all prohibited files and deletes them
    - Searches for mov, mp4,mp3,wav,jpg,jpeg,tar.gx,php,backdoor.
    - Stores them to pFiles.log
  - Configure Firewall
    - Installs and enables ufw
  - Login Conf
    - Uses lightdm and edits varius commands 

## Linux commands
- `apt-get [Option] [Command]`: Essentially the same as `apt`
- `killall`: Cancels all processes in a program (ex:killall firefox).  Use the `-u <user>` option to have it kill all processes owned by a user (useful for killing malicious jobs)
- `sed [options] [script] [file]`: "Stream EDit".  Helpful for editing text files line by line.  EX: `sed 's/hello/hi' file.txt` outputs the contents of file.txt but replaces every instance of "hello" with "hi".
- `cat`: Reads data from the file and gives the content as a output.
import cpusers
import os, subprocess
from pathlib import Path

password = "Sigma23*"

# for running powershell scripts
def run_ps(cmd):
    subprocess.run(["powershell", "-Command", cmd], capture_output=True)

# creates a list of all users (on the current Windows machine)
os.system('net user > users.txt')
users = Path('./users.txt').read_text()
users = users[users.index("-----\n")+6:users.index("The command completed successfully.")].split()

# creates a list of all administrators (on the current Windows machine)
run_ps("Get-LocalGroupMember -Group 'Administrators' > administrators.txt")
admins = Path("./administrators.txt").read_text("utf-16-le")
admins = admins[admins.index("-----\n")+6:].strip().split()
admins = [x[x.find("\\")+1:] for x in admins if x not in ("Local", "User")]

# creates a list of all non-administrators (on the current Windows machine)
non_admins = []
for user in users[:]:
    if user not in admins:
        non_admins.append(user)

# user permissions
for cp_user in cpusers.cp_users[:]:
    if cp_user not in users: # add user if they should exist
        os.system(f"net user {cp_user} {password} /add")

for user in users:
    if user not in cpusers.cp_users[:]: # remove user if they should't exist
        os.system(f"net user {user} /delete")
    if user in cpusers.cp_admins[:] and user not in admins: # make user admin if they should admin
        os.system(f"net localgroup administrators {user} /add")
    if user in cpusers.cp_non_admins and user in admins: # make admin user if they shouldn't be admin
        os.system(f"net localgroup administrators {user} /delete")

# updates windows
os.system("UsoClient ScanInstallWait")

# imports custom .inf file (Local Security Policy)

# disables guest account
#run_ps("Disable-LocalUser -Name 'Guest'")

# gets current user
os.system('whoami > whoami.txt')
current_user = Path("./whoami.txt").read_text()
current_user = current_user.split("\\", 1)[1]

# changes all users password to have secure password (except current user)
'''
for user in users[:]:
    if user.lower() != current_user:
        os.system(f"net user {i} {password}}")
'''

# turns on firewall for the current user
os.system("netsh advfirewall set allprofiles state on")

# removes file sharing on C:\ drive
os.system("net share C$ /delete")

# turns off remote desktop
os.system("reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' /v fDenyTSConnections /t REG_DWORD /d 1 /f")
os.system("netsh advfirewall firewall set rule group='remote desktop' new enable=No")


print(users)
print(admins)
print(non_admins)

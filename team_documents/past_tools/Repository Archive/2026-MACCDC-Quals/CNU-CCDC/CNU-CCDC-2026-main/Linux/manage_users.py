import subprocess
import getpass

password = "p@ssw0rd"

# Checking if the program is being executed under the root user
if getpass.getuser() == "root":
    print("\nWARNING: Run this script as root! Exiting...\n")
    exit()

def set_all_passwords():
    """
    Sets the password for every user on the system to the same password.
    """

    # Getting the password to use
    password = find_password()

    # Dumping /etc/passwd into a list
    with open("/etc/passwd", "r") as file:
        users = file.readlines()
        
    # Getting just the username from each /etc/passwd entry
    users = [user.split(":")[0] for user in users]

    # Looping over each user to change their passwords
    for user in users:
        if not set_password(user, password):
            print(f"Something went wrong setting {user}'s password.  Exiting program")
            exit()
    
    print("Set all user passwords")

def find_password() -> str:
    """
    Verifies the executed password with the executor.  
    Supports the "<user>" placeholder, allowing usernames to be included in passwords
    
    Returns:
        str: The password that the executor has selected
    """

    # Copying the global password to a local config
    pwd = password

    # Telling the executor about the placeholder
    print("\"<user>\" can be included in the password to have the password contain the username of the user.")

    accepted_password = False
    while not accepted_password:
        sel = input(f"The password that will be used is \"{pwd}\".  Continue? [Y/n]")
        if sel.lower() == "n":
            pwd = input("Please enter a new password: ")
        else:
            accepted_password = True

    return pwd

def set_password(user: str, password: str) -> bool:
    """
    Sets the password for a user

    Args:
        user (str): The user to change the password of
        password (str): The new password for the user

    Returns:
        bool: Whether or not the process completed successfully
    """
    password = password.replace("<user>", user)

    process = subprocess.run(f"echo {user}:{password} | chpasswd", shell=True)

    return process.returncode == 0

def add_user(user: str) -> bool:
    """
    Adds a user to the system
    
    Args:
        user (str): The user to create
    Returns:
        bool: Whether or not the user was added successfully
    """
    process = subprocess.run(f"adduser {user}")

    return process.returncode == 0

if __name__ == "main":
    print("CCDC 2026 CNU User Management Script")
    while True:
        # Listing options
        print("1) Set all users passwords")
        print("2) Set individual user's password")
        print("3) Add user")
        print("4) (NOT IMPLEMENTED) Remove user")
        print("5) (NOT IMPLEMENTED) Add admin")
        print("6) (NOT IMPLEMENTED) Remove admin")
        print("7) (NOT IMPLEMENTED) Remove users from ./users.txt and add users missing from it. (Requires ./users.txt)")
        print("8) (NOT IMPLEMENTED) Remove admin from people not in ./admins.txt and give it to people in that file. (Requires ./admins.txt)")
        print("9) Exit program")

        # Getting the input from the user and validating it
        selection = input("Select an option: ")

        match selection:
            case "1":
                set_all_passwords()
            case "2":
                user = input("Enter the user to change the password of: ")
                set_password(user, find_password())
            case "3":
                user = input("Enter the user to add: ")
                if not add_user(user):
                    print(f"Failed to create user {user}")
                else:
                    print(f"Created new user {user}")
            case "4":
                # TODO: Implement remove_user
                pass
            case "5":
                # TODO: Implement add_admin
                pass
            case "6":
                # TODO: Implement remove_admin
                pass
            case "7":
                # TODO: auto_filter_users
                pass
            case "8":
                # TODO: auto_filer_admins
                pass
            case "9":
                print("Exiting...")
                exit()
            case _:
                print("Invalid selection.  Please enter a number from 1-8.\n")
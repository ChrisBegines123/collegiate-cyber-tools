#!/bin/bash
# This will create an IR account with a pre-hashed password (CHANGE on next login) and prepare for ansible playbooks to be put onto the machine.

if [ "$EUID" -ne 0 ]; then 
    echo "This script needs to be run as sudo"
    exit 1
fi

USERNAME="CCDCIR"
PASSWORD='$6$BcYgtsE4/DaFDYRG$smzaU3PCbYSZlVu7dseVcOoyTUmqh71/dG04JLTw7DYvszm5aNiqGyXJemlOVCJ8WiDlqi7GY/2/wTyqhtCrI0'
PUBLIC_KEY="./pubkey"
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"

read -p "enter the ssh port number: " port

if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid port number"
    exit 1
fi

create_user() {
    # This will create the IR user with the provided password
    useradd -m -s /bin/bash "$USERNAME"
    usermod -p "$PASSWORD" "$USERNAME"
    echo "Created a user with a hashed password"

    # Check for success
    if ! id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME does not exist."
        exit 1
    fi  
}

add_to_sudo() {
    usermod -aG sudo $USERNAME
    echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers.d/$USERNAME
    chmod 440 "$SUDOERS_FILE"

    if ! [ -f "$SUDOERS_FILE" ]; then
        echo "Error: Failed to create sudoers file"
        exit 1
    fi
}

add_ssh_key() {
    local ssh_dir="/home/$USERNAME/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    mkdir -p "$ssh_dir"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
    chmod 700 "$ssh_dir"

    if [[ -n "$PUBLIC_KEY" ]]; then
        cat "$PUBKEY_KEY" > "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$USERNAME:$USERNAME" "$auth_keys"
        echo "Added SSH public key"
    else
        echo "Warning: No SSH public key provided"
    fi
}

fix_sshd_config() {
    echo  "Configuring SSH daemon..."

    local SSHD_CONFIG_DIR="/etc/ssh/"
    local SSHD_CONFIG="/etc/ssh/sshd_config"
    
    # Ensure sshd_config.d directory exists
    mkdir -p "$SSHD_CONFIG_DIR"
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup"
    #Set permissions
    chmod 444 "$SSHD_CONFIG"

    sed -i \
      -e "s/^[# ]*Port.*/Port $port/" \
      -e 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication no/' \
      -e 's/^[# ]*PermitRootLogin.*/PermitRootLogin no/' \
      -e 's/^[# ]*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
      "$SSHD_CONFIG"

    # Test configuration
    if ! sshd -t ; then
        echo "Error: Invalid SSHD configuration"
        echo "Rolling back changes..."
        if [ -f "${SSHD_CONFIG}.backup" ]; then
            mv "${SSHD_CONFIG}.backup" "$SSHD_CONFIG"
        fi
        rm -f "$SSHD_CUSTOM_CONFIG"
        exit 1
    fi
    
    echo "SSH daemon configuration updated and verified"
}

main() {
    create_user || exit 1
    add_to_sudo || exit 1
    add_ssh_key || exit 1
    fix_sshd_config || exit 1
}

main

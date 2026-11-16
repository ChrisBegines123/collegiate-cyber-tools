#!/usr/bin/env bash

if (( EUID != 0 )); then
    echo "Script must be ran as root!"
    exit 1
fi

source main/bak_usr_and_pass_update.sh 
source main/check_package_manager.sh
source main/disable_cockpit.sh
source main/get_os_name_ver.sh 
source main/install_package.sh
source main/interface_down.sh 
source main/interface_up.sh 
source main/nuke_cron.sh 
source main/remove_package.sh
source main/update_user_pass.sh 
source main/configure_sshd.sh
source other/fix_package_manager.sh

modify_iface=true
config_sshd=false

while getopts ":i:s" opt; do
    case "$opt" in
        i) 
            modify_iface=false
            ;;
        s)
            config_sshd=true
            ;;
        \?) 
            echo "Unknown option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

shift $((OPTIND-1))

export modify_iface config_sshd

# Track how many backups are made for versioning
acct_bak_count=0 
etc_bak_count=0

export acct_bak_count etc_bak_count

# Make array containing network interfaces
mapfile -t interfaces < <(ip -o link show | awk -F': ' '{print $2}')
export interfaces

# Get os name and version
get_os_name_ver
echo "OS=$OS VER=$VER" > /dev/null 2>&1 

# Clean things up
OS="${OS,,}"

if [ "$OS" = "ubuntu" ]; then
    # Fix version to work with integer comparison
    VER="${VER::-3}"
elif [[ "$OS" =~ "fedora" ]]; then
    # Shorten Fedora Linux to fedora
    OS="fedora"
fi

export OS VER

package_manager=$(check_package_manager)

function backup_group_passwd_shadow() {
    tar -cJf /root/group_passwd_shadow_bak_"$acct_bak_count".tar.xz /etc/group /etc/passwd /etc/shadow
    ((acct_bak_count++))
}

function backup_etc() {
    tar -cJf /root/etc_bak_"$etc_bak_count".tar.xz /etc 
    ((etc_bak_count++))
}

function service_backup() {
    mkdir /root/b
    chmod 600 /root/b

    tar -cJf /root/b/etc_bak.tar.xz /etc
    ((etc_bak_count++))

    tar -cJf /root/b/web_bak.tar.xz /var/www/html

    if [ $(ss -autpn | grep splunk) ]; then
        tar -cJf /root/b/splunk_bak.tar.xz /opt
    fi

    tar -cJf /root/b/binary_bak.tar.xz /usr/bin/python3
}

function check_tmux() {
    which tmux > /dev/null 2>&1
    
    tmux_status=$?

    if [ "$tmux_status" -ne "0" ]; then
        echo "tmux not detected, installing now..."
        install_package "$package_manager" "tmux"

        install_status=$?

        if [ "$install_status" -ne "0" ]; then
            echo "Default install did not work, attempting with pre-supplied archive..."
            
            case "$OS" in
                ubuntu|debian)
                    install_package "$package_manager" "binaries/tmux_ubuntu_22.04.deb"
                    ;;
                centos|rocky|almalinux|fedora)
                    install_package"$package_manager" "binaries/tmux_fedora_42.rpm"
                    ;;
            esac
        fi 

        install_status=$?

        if [ "$install_status" -ne "0" ]; then
            echo "Pre-supplied archive install did not work, attempting to manually add binary to path..."
            case "$OS" in
                ubuntu|debian)
                    ar x binaries/tmux/tmux_ubuntu_22.04.deb

                    tar xf binaries/tmux/data.tar.zst

                    ln -sf binaries/tmux/usr/bin/tmux /usr/bin/tmux
                    ;;
                centos|rocky|almalinux|fedora)
                    rpm2cpio tmux_fedora_42.rpm | cpio -idmv

                    ln -sf binaries/tmux/usr/bin/tmux /usr/bin/tmux
                    ;;
            esac
        fi
    else
        echo "tmux found, skipping install"
    fi
}

function package_management() {
    which nano > /dev/null 2>&1

    nano_status=$?

    which vim > /dev/null 2>&1

    vim_status=$?

    if [ "$nano_status" -eq "0" ]; then
        remove_package "$package_manager" "nano"
    fi

    if [ "$vim_status" -ne "0" ]; then
        install_package "$package_manager" "vim"
    fi
}

# Backup acct things
export -f backup_group_passwd_shadow
export -f backup_etc
export -f service_backup
export -f create_backup_usr
# Updates root and backup user password
export -f second_pass_update
export -f check_package_manager
export -f install_package
export -f interface_down
export -f interface_up
export -f nuke_cron
export -f remove_package
# Updates all user passwords to a random string
export -f update_user_pass
export -f disable_cockpit
export -f configure_sshd

function setup_tmux() {
    # 1) Create session if missing (detached)
    if ! tmux has-session -t start 2>/dev/null; then
        tmux new-session -d -s start -n user
    fi

    # 2) Build layout (idempotent)
    tmux select-window -t start:0
    tmux kill-pane    -a -t start:0 2>/dev/null
    tmux split-window -h -t start:0

    tmux new-window   -t start:1 -n banner 2>/dev/null || true
    tmux kill-pane    -a -t start:1 2>/dev/null
    tmux split-window    -t start:1
    tmux split-window    -t start:1

    tmux setw -t start:0 remain-on-exit on
    tmux setw -t start:1 remain-on-exit on

    # 3) Land on main pane
    tmux select-window -t start:0
    tmux select-pane   -t start:0.0

    # 4) Start tasks automatically *after* attach
    if [ -t 0 ] && [ -t 1 ]; then
        # Real TTY: queue the commands to run shortly after attach.
        (
            sleep 0.3
            tmux send-keys -t start:0.1 "bash -c 'service_backup && interface_down $modify_iface ${interfaces[*]}'" C-m
            tmux send-keys -t start:0.0 'bash -c "update_user_pass && create_backup_usr && second_pass_update; tmux wait-for -S usr_ready"' C-m
            tmux wait-for usr_ready
            tmux send-keys -t start:0.1 "bash -c 'nuke_cron && configure_ssh $config_sshd && disable_cockpit && backup_group_passwd_shadow && backup_etc && interface_up $modify_iface ${interfaces[*]}'" C-m
            tmux send-keys -t start:1.0 'vim /etc/ssh/sshd_config' C-m
            tmux send-keys -t start:1.1 'vim /etc/issue.net' C-m
            tmux send-keys -t start:1.2 'echo "Banner /etc/issue.net in config and write issue"' C-m
        ) &

        # Attach in the foreground; no hooks, no background attach → no TTY errors.
        : "${TERM:=xterm-256color}"
            exec tmux attach -t start
        else
            # No interactive TTY (cron/systemd). Don’t attach; also don’t start tasks.
            echo "Created tmux session 'start' but no interactive TTY detected."
            echo "Attach from a terminal: tmux attach -t start"
        fi

}

fix_package_manager

check_tmux

backup_group_passwd_shadow

backup_etc

setup_tmux

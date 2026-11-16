#!/usr/bin/env bash

if (( EUID != 0 )); then
    echo Must be run as root!
    exit 1
fi

source ./main/bak_usr_and_pass_update.sh
source ./main/configure_sshd.sh
source ./main/disable_cockpit.sh
source ./main/interface_down.sh
source ./main/interface_up.sh
source ./main/nuke_cron.sh
source ./main/update_user_pass.sh
source ./first30.sh

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

backup_group_passwd_shadow

backup_etc

update_user_pass; service_backup; interface_down "$modify_iface" "${interfaces[*]}"; create_backup_usr; second_pass_update; nuke_cron; configure_ssh $config_sshd; disable_cockpit; backup_group_passwd_shadow; backup_etc; interface_up "$modify_iface" "${interfaces[*]}"

echo COMPLETE


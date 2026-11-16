#!/usr/bin/env bash

function update_user_pass() {
    if [ -f /root/passupdate ]; then
        echo "Passwords have been updated. Skipping..."
        return 0
    else 
        mapfile -t users < <(awk -F':' '{print $1}' /etc/passwd)

        for user in "${users[@]}"; do
            if [ "$user" = "root" ]; then
                echo "Don't nuke the root user :)"
            else
                pass=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13)
                echo "$user:$pass" | chpasswd &>/dev/null

                printf "\n%s\t\t\t%s" "$user" "$pass"
            fi
        done
        touch /root/passupdate
    fi

    while :; do

        read -rp "Have you written all this down? (y/n): " pass_check

        case "${pass_check,,}" in
            y)
                echo "Don't forget"
                break
                ;;
            n)
                echo "Go write that down"
                break
                ;;
            *)
                echo "Response must be 'y' or 'n'"
                ;;
        esac
    done
}

What order do things need to go in?

1. backup account things (group_passwd_shadow), outisde tmux

2. backup etc, outside tmux

3. update all user passwd (update_user_pass), requires user input

4. backup services

5. bring interfaces down 

6. create backup user, require user input

7. update root and backup user passwd, require user input

8. update sshd config, require user input

9. detect and stop cockpit

10. nuke cron

11. backup again

12. bring interfaces up

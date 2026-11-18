# Ubuntu Checklist

## Managed By Script (Linux/old/literate-eureka/scripts/7-script.sh)

- [x] Run updates
- [x] Enable & configure UFW
- [x] Configure services
  - sshd
  - Samba
  - FTP
- [x] Remove unauthorized users
- [x] Add missing users
- [x] Add/remove users from sudo group
- [x] Change all passwords
- [x] Lock root account
- [x] Add missing groups
- [x] Disable guest account
- [x] Configure password expiry
- [x] Enable automatic updates through APT
- [x] Remove prohibited/unwanted software  
       **You should still check for suspicious software yourself**
- [x] Clear `/etc/rc.local` (startup file)
- [x] Find files on system with high permissions (eg. 700+)
- [x] Run rkhunter
- [x] Run clamav
- [x] Find media files (videos, audio, images)
- [x] List running services

## Not Managed By Script

- [ ] Lock down browser  
       If the browser is Firefox, basically just set every setting
      to the most strict in the security settings
- [ ] Install recommended programs
- [ ] Configure PAM settings
  - Set minimum password length
  - Enforce password complexity
  - Configure account lockout
  - All done through `/etc/pam.d/common-password` or `/etc/pam.d/common-auth`
This is for common linux scripts that will work on any distro.

user_priv_audit.sh
-------------------
Audits local accounts/privileges and, with -a, remediates what it finds
(locks unauthorized/UID-0-clone/empty-password accounts, strips privileges
not in an expected-privileges file). See the script's own header comment
for flags, and test/ for its bats test suite.

install.sh
-------------------
Deploys user_priv_audit.sh onto a box and schedules it via systemd: copies
the script, sets up (or preserves) the expected-users/privs config, writes
the .service/.timer units, and enables the timer. Must be run as root, and
only supports systemd (checks for systemctl up front and exits if missing).
Safe to re-run - it won't overwrite an expected-users/privs file that's
already there unless you pass -u/-p again to explicitly replace it.

Usage:
    sudo ./install.sh [-d install_dir] [-c config_dir] [-o logfile]
                       [-n interval_minutes] [-u users_file] [-p privs_file] [-a]

  -d DIR   where to install the script (default /opt/nccdc-tools)
  -c DIR   where expected-users/privs config lives (default /etc/nccdc-tools)
  -o FILE  action logfile (default /var/log/user_priv_audit.log)
  -n MIN   minutes between runs (default 5)
  -u FILE  your expected-users list, copied into the config dir. If omitted
           and none is installed yet, an empty template is created for you
           to fill in (see user_priv_audit.sh's header for the format).
  -p FILE  your expected-privileges list, same rules as -u.
  -a       enable remediation (-a) in the installed service. Default is
           report-only/dry-run - the safe choice until you've confirmed the
           expected-users/privs config is accurate for this box, since a
           stale list will otherwise lock out a legitimate teammate.

Typical flow on a target box:
    sudo ./install.sh -u ./our_users.txt -p ./our_privs.txt
    # ... watch a few dry-run cycles, confirm the plan looks right ...
    sudo ./install.sh -u ./our_users.txt -p ./our_privs.txt -a

After installing:
    systemctl status user_priv_audit.timer     # confirm it's scheduled
    journalctl -u user_priv_audit.service -f   # watch runs live
    cat /var/log/user_priv_audit.log           # (or your -o path) action log

To uninstall: systemctl disable --now user_priv_audit.timer, then remove
/etc/systemd/system/user_priv_audit.{service,timer}, the install dir, and
the config dir.

Prefer to do it by hand instead? systemd/user_priv_audit.service and .timer
in this directory are the same units install.sh generates, kept here as a
plain reference/starting point - copy them to /etc/systemd/system/ yourself,
edit the paths/flags in the .service file, then `systemctl daemon-reload`
and `systemctl enable --now user_priv_audit.timer`.

#!/bin/sh
# install.sh
# Deploys user_priv_audit.sh onto this box and schedules it via systemd:
# copies the script, sets up (or preserves) expected-users/privs config,
# generates the .service/.timer units, and enables the timer.
#
# Usage: install.sh [-d install_dir] [-c config_dir] [-o logfile]
#                    [-n interval_minutes] [-u users_file] [-p privs_file] [-a]
#   -d DIR    where to install the script (default /opt/nccdc-tools)
#   -c DIR    where expected-users/privs config lives (default /etc/nccdc-tools)
#   -o FILE   action logfile (default /var/log/user_priv_audit.log)
#   -n MIN    minutes between runs (default 5)
#   -u FILE   expected-users list to install (copied into config dir).
#             If omitted and none exists yet, an empty template is created.
#   -p FILE   expected-privileges list to install, same rules as -u.
#   -a        enable remediation (-a) in the installed service. Default is
#             report-only/dry-run - safest until you've verified the
#             expected-users/privs config is accurate for this box.
#
# Must be run as root. Re-running is safe: it won't overwrite an
# already-installed expected-users/privs file unless you pass -u/-p again.

set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT_SRC="$SELF_DIR/user_priv_audit.sh"

INSTALL_DIR="/opt/nccdc-tools"
CONF_DIR="/etc/nccdc-tools"
LOGFILE="/var/log/user_priv_audit.log"
INTERVAL=5
USERS_FILE_SRC=""
PRIVS_FILE_SRC=""
APPLY=0

usage() {
    echo "Usage: $0 [-d install_dir] [-c config_dir] [-o logfile] [-n interval_minutes] [-u users_file] [-p privs_file] [-a]" >&2
    exit 1
}

while getopts "d:c:o:n:u:p:ah" opt; do
    case "$opt" in
        d) INSTALL_DIR="$OPTARG" ;;
        c) CONF_DIR="$OPTARG" ;;
        o) LOGFILE="$OPTARG" ;;
        n) INTERVAL="$OPTARG" ;;
        u) USERS_FILE_SRC="$OPTARG" ;;
        p) PRIVS_FILE_SRC="$OPTARG" ;;
        a) APPLY=1 ;;
        h|*) usage ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh must be run as root (it writes to $INSTALL_DIR, $CONF_DIR, and /etc/systemd/system)." >&2
    exit 1
fi

[ -r "$SCRIPT_SRC" ] || { echo "Cannot find user_priv_audit.sh next to install.sh (looked in $SELF_DIR)" >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "systemctl not found; this installer only supports systemd." >&2; exit 1; }

USERS_FILE="$CONF_DIR/expected_users.txt"
PRIVS_FILE="$CONF_DIR/expected_privs.txt"

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"
mkdir -p "$(dirname "$LOGFILE")"

cp "$SCRIPT_SRC" "$INSTALL_DIR/user_priv_audit.sh"
chmod 750 "$INSTALL_DIR/user_priv_audit.sh"
echo "Installed $INSTALL_DIR/user_priv_audit.sh"

if [ -n "$USERS_FILE_SRC" ]; then
    [ -r "$USERS_FILE_SRC" ] || { echo "Cannot read -u file: $USERS_FILE_SRC" >&2; exit 1; }
    cp "$USERS_FILE_SRC" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
    echo "Installed expected-users list: $USERS_FILE"
elif [ ! -e "$USERS_FILE" ]; then
    printf '# One authorized username per line. # comments and blank lines OK.\n' > "$USERS_FILE"
    chmod 600 "$USERS_FILE"
    echo "Created empty template: $USERS_FILE (fill this in!)"
else
    echo "Keeping existing $USERS_FILE"
fi

if [ -n "$PRIVS_FILE_SRC" ]; then
    [ -r "$PRIVS_FILE_SRC" ] || { echo "Cannot read -p file: $PRIVS_FILE_SRC" >&2; exit 1; }
    cp "$PRIVS_FILE_SRC" "$PRIVS_FILE"
    chmod 600 "$PRIVS_FILE"
    echo "Installed expected-privileges list: $PRIVS_FILE"
elif [ ! -e "$PRIVS_FILE" ]; then
    printf '# username:comma,separated,allowed,privileged,groups (subset of wheel/sudo/admin)\n' > "$PRIVS_FILE"
    chmod 600 "$PRIVS_FILE"
    echo "Created empty template: $PRIVS_FILE (fill this in!)"
else
    echo "Keeping existing $PRIVS_FILE"
fi

EXEC_LINE="$INSTALL_DIR/user_priv_audit.sh -l $USERS_FILE -p $PRIVS_FILE -o $LOGFILE"
if [ "$APPLY" -eq 1 ]; then
    EXEC_LINE="$EXEC_LINE -a"
fi

cat > /etc/systemd/system/user_priv_audit.service <<EOF
[Unit]
Description=Local account privilege audit (user_priv_audit.sh)
ConditionPathExists=$INSTALL_DIR/user_priv_audit.sh

[Service]
Type=oneshot
User=root
ExecStart=$EXEC_LINE
TimeoutStartSec=60
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/user_priv_audit.timer <<EOF
[Unit]
Description=Run user_priv_audit.sh on a schedule

[Timer]
OnBootSec=2min
OnUnitActiveSec=${INTERVAL}min
Persistent=true
Unit=user_priv_audit.service

[Install]
WantedBy=timers.target
EOF

echo "Wrote /etc/systemd/system/user_priv_audit.service and .timer"

systemctl daemon-reload
systemctl enable --now user_priv_audit.timer

echo
echo "=== Installed and running every ${INTERVAL} minute(s) ==="
if [ "$APPLY" -eq 1 ]; then
    echo "Mode: REMEDIATION ENABLED (-a) - flagged accounts will actually be locked/modified."
else
    echo "Mode: report-only (dry-run) - nothing will actually be locked/modified yet."
    echo "Once $USERS_FILE and $PRIVS_FILE are accurate for this box, re-run with -a"
    echo "(or edit ExecStart= in /etc/systemd/system/user_priv_audit.service and 'systemctl daemon-reload')."
fi
echo
echo "Check status:  systemctl status user_priv_audit.timer"
echo "Watch runs:    journalctl -u user_priv_audit.service -f"
echo "Action log:    $LOGFILE"

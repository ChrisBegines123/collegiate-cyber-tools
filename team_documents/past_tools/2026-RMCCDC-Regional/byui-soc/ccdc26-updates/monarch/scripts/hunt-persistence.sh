#!/bin/bash
# CCDC26 Monarch - Consolidated Persistence Hunter
# Combines: cron, services, users, binaries, startup, PAM, LD_PRELOAD
# SELF-CONTAINED -- no external dependencies

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()      { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
finding() { echo -e "${RED}[FINDING]${NC} $1"; }
phase()   { echo -e "\n${BOLD}${PURPLE}========================================${NC}"; echo -e "${BOLD}${PURPLE}[PHASE] $1${NC}"; echo -e "${BOLD}${PURPLE}========================================${NC}\n"; }

if [ "$EUID" -ne 0 ]; then error "Must be run as root"; exit 1; fi

# Distro detection
PKG_MGR="unknown"; INIT_SYSTEM="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian|kali|mint|pop) PKG_MGR="apt" ;;
        rhel|centos|fedora|rocky|alma|oracle)
            command -v dnf &>/dev/null && PKG_MGR="dnf" || PKG_MGR="yum"
            ;;
    esac
fi
[ -d /run/systemd/system ] && INIT_SYSTEM="systemd"

hash_file() {
    local f="$1"
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
}

FINDINGS=0
log_find() {
    finding "$1"
    FINDINGS=$((FINDINGS + 1))
}

START_TIME=$(date +%s)
echo -e "\n${BOLD}${GREEN}CCDC26 Monarch - Persistence Hunter${NC}\n"

#=============================================================================
phase "1 - Cron Job Audit"
#=============================================================================

info "System crontab:"
[ -f /etc/crontab ] && grep -v "^#" /etc/crontab | grep -v "^$" || true

info "Cron directories:"
for dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
    if [ -d "$dir" ]; then
        for f in "$dir"/*; do
            [ -f "$f" ] || continue
            info "  $f"
        done
    fi
done

info "User crontabs:"
for user in $(cut -d: -f1 /etc/passwd); do
    ct=$(crontab -l -u "$user" 2>/dev/null)
    if [ -n "$ct" ]; then
        warn "Crontab for $user:"
        echo "$ct"
    fi
done

info "Crontab spool directories:"
for spool in /var/spool/cron/crontabs /var/spool/cron; do
    [ -d "$spool" ] && ls -la "$spool" 2>/dev/null
done

info "Scanning for suspicious cron entries..."
SUSPICIOUS_PATTERNS="curl|wget|nc |ncat|netcat|/tmp/|/dev/shm/|/var/tmp/|base64|python.*-c|perl.*-e|bash.*-i|mkfifo|/dev/tcp|/dev/udp|reverse|payload|meterpreter"

for f in /etc/crontab /etc/cron.d/* /var/spool/cron/crontabs/* /var/spool/cron/*; do
    [ -f "$f" ] || continue
    if grep -qE "$SUSPICIOUS_PATTERNS" "$f" 2>/dev/null; then
        log_find "Suspicious pattern in cron file: $f"
        grep -nE "$SUSPICIOUS_PATTERNS" "$f"
    fi
done

for user in $(cut -d: -f1 /etc/passwd); do
    ct=$(crontab -l -u "$user" 2>/dev/null)
    [ -z "$ct" ] && continue
    if echo "$ct" | grep -qE "$SUSPICIOUS_PATTERNS"; then
        log_find "Suspicious crontab entry for: $user"
    fi
done

info "AT jobs:"
if command -v atq &>/dev/null; then
    atq 2>/dev/null
    for job in $(atq 2>/dev/null | awk '{print $1}'); do
        at -c "$job" 2>/dev/null | tail -5
    done
fi

info "Anacron:"
[ -f /etc/anacrontab ] && cat /etc/anacrontab || echo "  (not present)"

info "Systemd timers:"
if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl list-timers --all --no-pager 2>/dev/null
    for timer in /etc/systemd/system/*.timer; do
        [ -f "$timer" ] || continue
        log_find "Custom systemd timer: $timer"
    done
fi

ok "Cron audit complete"

#=============================================================================
phase "2 - Service Audit"
#=============================================================================

if [ "$INIT_SYSTEM" = "systemd" ]; then
    info "Checking for suspicious systemd units..."
    for f in /etc/systemd/system/*.service; do
        [ -f "$f" ] || continue
        if grep -qE 'ExecStart=.*(nc |ncat |netcat |/tmp/|/dev/shm/|curl.*\||wget.*\||bash.*-i|python.*-c)' "$f" 2>/dev/null; then
            log_find "Suspicious ExecStart in: $f"
            grep 'ExecStart' "$f"
        fi
        # Check if not from package
        if ! dpkg -S "$f" &>/dev/null 2>&1 && ! rpm -qf "$f" &>/dev/null 2>&1; then
            warn "Custom (non-package) service: $f"
        fi
    done

    info "Checking for suspiciously named services..."
    systemctl list-units --all --no-pager 2>/dev/null | grep -iE '(backdoor|shell|reverse|bind|payload|meterpreter|beacon)' && \
        log_find "Suspiciously named systemd unit found"

    info "Recently modified service files (last 7 days):"
    find /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system -name "*.service" -mtime -7 2>/dev/null | while read -r f; do
        warn "Modified: $f ($(stat -c %y "$f" 2>/dev/null))"
    done
fi

info "Init scripts:"
for f in /etc/init.d/*; do
    [ -f "$f" ] || continue
    if grep -qE "$SUSPICIOUS_PATTERNS" "$f" 2>/dev/null; then
        log_find "Suspicious init script: $f"
    fi
done

info "Xinetd services:"
if [ -d /etc/xinetd.d ]; then
    for f in /etc/xinetd.d/*; do
        [ -f "$f" ] || continue
        warn "Xinetd service: $f"
    done
fi

ok "Service audit complete"

#=============================================================================
phase "3 - User Account Audit"
#=============================================================================

info "UID 0 accounts:"
while IFS=: read -r user _ uid _; do
    if [ "$uid" -eq 0 ]; then
        if [ "$user" = "root" ]; then
            ok "root (UID 0) -- expected"
        else
            log_find "Non-root UID 0 account: $user"
        fi
    fi
done < /etc/passwd

info "Sudo/wheel group members:"
getent group sudo 2>/dev/null || true
getent group wheel 2>/dev/null || true

info "Sudoers.d entries:"
if [ -d /etc/sudoers.d ]; then
    for f in /etc/sudoers.d/*; do
        [ -f "$f" ] || continue
        info "  $f:"
        cat "$f"
    done
fi

info "SSH authorized_keys:"
for home in /home/* /root; do
    [ -d "$home" ] || continue
    ak="$home/.ssh/authorized_keys"
    if [ -f "$ak" ]; then
        count=$(wc -l < "$ak")
        user=$(basename "$home")
        [ "$home" = "/root" ] && user="root"
        warn "$user has $count SSH key(s) in $ak"
    fi
done

info "Authorized keys in unusual locations:"
find / -name "authorized_keys" -o -name "authorized_keys2" 2>/dev/null | while read -r kf; do
    case "$kf" in
        /home/*/.ssh/authorized_keys|/root/.ssh/authorized_keys) ;;
        *) log_find "Unusual authorized_keys: $kf" ;;
    esac
done

info "Users with login shells:"
while IFS=: read -r user _ uid _ _ _ shell; do
    if [ "$uid" -ge 1000 ] || [ "$uid" -eq 0 ]; then
        case "$shell" in
            */nologin|*/false|"") ;;
            *) info "  $user (UID $uid): $shell" ;;
        esac
    fi
done < /etc/passwd

info "Service accounts with shells:"
while IFS=: read -r user _ uid _ _ _ shell; do
    if [ "$uid" -lt 1000 ] && [ "$uid" -ne 0 ]; then
        case "$shell" in
            */nologin|*/false|/sbin/nologin|"") ;;
            *) log_find "Service account with shell: $user ($shell)" ;;
        esac
    fi
done < /etc/passwd

info "Empty password hashes:"
while IFS=: read -r user pw _; do
    if [ -z "$pw" ]; then
        log_find "Empty password hash: $user"
    fi
done < /etc/shadow 2>/dev/null

ok "User audit complete"

#=============================================================================
phase "4 - Binary Audit (SUID/SGID/Capabilities)"
#=============================================================================

# Curated GTFOBins list
GTFOBINS="awk base64 bash busybox cat chmod cp csh curl cut dash dd diff ed env find gawk gdb git grep head hexdump install ionice ip jq less lua make more mv nano nice nl node nohup od openssl perl php python readelf rev rlwrap rpm rsync ruby sed sh socat sort split sqlite3 ssh-agent strace strings sysctl tac tail tar taskset tee time timeout vi vim watch wget xargs xxd zip zsh"

is_gtfobins() {
    local name=$(basename "$1")
    echo " $GTFOBINS " | grep -q " $name " && return 0
    return 1
}

info "SUID binaries:"
find / -xdev -type f -perm -4000 2>/dev/null | sort | while read -r bin; do
    if is_gtfobins "$bin"; then
        log_find "GTFOBins SUID: $bin"
    else
        info "  $bin"
    fi
done

info "SUID/SGID in unusual locations:"
for dir in /tmp /var/tmp /dev/shm /home /opt /var/www /srv; do
    [ -d "$dir" ] || continue
    find "$dir" -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | while read -r bin; do
        log_find "SUID/SGID in unusual location: $bin"
        ls -la "$bin"
    done
done

info "File capabilities:"
if command -v getcap &>/dev/null; then
    getcap -r / 2>/dev/null | while read -r line; do
        file=$(echo "$line" | awk '{print $1}')
        caps=$(echo "$line" | cut -d'=' -f2)
        if echo "$caps" | grep -qiE '(cap_sys_admin|cap_setuid|cap_setgid|cap_sys_ptrace|cap_sys_module|cap_dac_override|cap_net_raw)'; then
            log_find "Dangerous capability: $line"
        else
            info "  $line"
        fi
    done

    for dir in /tmp /var/tmp /dev/shm /home; do
        [ -d "$dir" ] || continue
        find "$dir" -type f 2>/dev/null | while read -r f; do
            cap=$(getcap "$f" 2>/dev/null)
            [ -n "$cap" ] && log_find "Capability in unusual location: $cap"
        done
    done
fi

info "Suspicious executables in temp dirs:"
for dir in /tmp /var/tmp /dev/shm; do
    [ -d "$dir" ] || continue
    find "$dir" -type f -executable 2>/dev/null | while read -r f; do
        log_find "Executable in $dir: $f"
    done
done

info "Hidden executables:"
find /tmp /var/tmp /dev/shm /home /opt -name ".*" -type f -executable 2>/dev/null | while read -r f; do
    log_find "Hidden executable: $f"
done

info "Recently created executables (7 days) in system dirs:"
find /usr/bin /usr/sbin /usr/local/bin /opt -type f -executable -mtime -7 2>/dev/null | while read -r f; do
    warn "Recent: $f ($(stat -c %y "$f" 2>/dev/null))"
done

ok "Binary audit complete"

#=============================================================================
phase "5 - Startup Persistence Audit"
#=============================================================================

info "Profile files:"
for f in /etc/profile /etc/profile.d/*.sh /etc/bash.bashrc /etc/bashrc; do
    [ -f "$f" ] || continue
    if grep -qE "$SUSPICIOUS_PATTERNS" "$f" 2>/dev/null; then
        log_find "Suspicious content in profile: $f"
    fi
done

for home in /home/* /root; do
    for rc in .bashrc .bash_profile .profile .bash_login .bash_logout .zshrc; do
        f="$home/$rc"
        [ -f "$f" ] || continue
        if grep -qE "$SUSPICIOUS_PATTERNS" "$f" 2>/dev/null; then
            log_find "Suspicious content in $f"
        fi
    done
done

info "rc.local:"
for f in /etc/rc.local /etc/rc.d/rc.local; do
    if [ -f "$f" ]; then
        warn "rc.local exists: $f"
        grep -v "^#" "$f" | grep -v "^$" | head -20
        if grep -qE "$SUSPICIOUS_PATTERNS" "$f" 2>/dev/null; then
            log_find "Suspicious content in $f"
        fi
    fi
done

info "MOTD scripts:"
for d in /etc/update-motd.d /etc/motd.d; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] || continue
        if grep -qE "$SUSPICIOUS_PATTERNS" "$f" 2>/dev/null; then
            log_find "Suspicious MOTD script: $f"
        fi
    done
done

info "Inittab:"
[ -f /etc/inittab ] && grep -v "^#" /etc/inittab | grep -v "^$"

info "Systemd generators:"
for d in /etc/systemd/system-generators /usr/lib/systemd/system-generators /usr/local/lib/systemd/system-generators; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        [ -f "$f" ] || continue
        warn "Systemd generator: $f"
    done
done

info "Udev rules:"
for f in /etc/udev/rules.d/*; do
    [ -f "$f" ] || continue
    if grep -qE "(RUN|PROGRAM).*($SUSPICIOUS_PATTERNS)" "$f" 2>/dev/null; then
        log_find "Suspicious udev rule: $f"
    fi
done

ok "Startup audit complete"

#=============================================================================
phase "6 - PAM Audit"
#=============================================================================

PAM_DIR="/etc/pam.d"

info "Checking pam_exec.so entries..."
for conf in "$PAM_DIR"/*; do
    [ -f "$conf" ] || continue
    if grep -qE '^\s*[^#].*pam_exec\.so' "$conf" 2>/dev/null; then
        log_find "pam_exec.so in $conf (arbitrary command execution)"
        grep -n 'pam_exec\.so' "$conf"
    fi
done

info "Checking nullok entries..."
for conf in "$PAM_DIR"/*; do
    [ -f "$conf" ] || continue
    if grep -qE '^\s*[^#].*nullok' "$conf" 2>/dev/null; then
        log_find "nullok in $conf (blank passwords allowed)"
    fi
done

info "Verifying pam_deny/pam_permit integrity..."
PAM_LIB_DIR=""
for d in /lib/x86_64-linux-gnu/security /lib64/security /usr/lib64/security /lib/security /usr/lib/security; do
    [ -f "$d/pam_unix.so" ] && PAM_LIB_DIR="$d" && break
done

if [ -n "$PAM_LIB_DIR" ]; then
    deny_hash=$(hash_file "$PAM_LIB_DIR/pam_deny.so")
    permit_hash=$(hash_file "$PAM_LIB_DIR/pam_permit.so")
    if [ -n "$deny_hash" ] && [ "$deny_hash" = "$permit_hash" ]; then
        log_find "CRITICAL: pam_deny.so and pam_permit.so have IDENTICAL hashes -- possible swap!"
    else
        ok "pam_deny.so and pam_permit.so have different hashes"
    fi
fi

info "PAM stack ordering check..."
for conf in "$PAM_DIR"/*; do
    [ -f "$conf" ] || continue
    deny_line=0; permit_line=0; linenum=0
    while IFS= read -r line; do
        linenum=$((linenum + 1))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        echo "$line" | grep -q 'pam_permit\.so' && [ $permit_line -eq 0 ] && permit_line=$linenum
        echo "$line" | grep -q 'pam_deny\.so' && [ $deny_line -eq 0 ] && deny_line=$linenum
    done < "$conf"
    if [ $permit_line -gt 0 ] && [ $deny_line -gt 0 ] && [ $permit_line -lt $deny_line ]; then
        log_find "In $conf: pam_permit (line $permit_line) before pam_deny (line $deny_line)"
    fi
done

info "Recently modified PAM files (7 days):"
find /etc/pam.d -type f -mtime -7 2>/dev/null | while read -r f; do
    log_find "Recently modified PAM: $f"
done
if [ -n "$PAM_LIB_DIR" ]; then
    find "$PAM_LIB_DIR" -name "pam_*.so" -mtime -7 2>/dev/null | while read -r f; do
        log_find "Recently modified PAM lib: $f"
    done
fi

ok "PAM audit complete"

#=============================================================================
phase "7 - LD_PRELOAD / Library Injection"
#=============================================================================

info "LD_PRELOAD environment variable:"
if [ -n "${LD_PRELOAD:-}" ]; then
    log_find "LD_PRELOAD is set: $LD_PRELOAD"
else
    ok "LD_PRELOAD not set"
fi

info "/etc/ld.so.preload:"
if [ -f /etc/ld.so.preload ]; then
    log_find "/etc/ld.so.preload exists:"
    cat /etc/ld.so.preload
else
    ok "/etc/ld.so.preload does not exist"
fi

info "Checking ld.so.conf.d for unusual paths..."
for conf in /etc/ld.so.conf.d/*; do
    [ -f "$conf" ] || continue
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        [[ "$path" == \#* ]] && continue
        if [[ "$path" == /tmp/* ]] || [[ "$path" == /home/* ]] || [[ "$path" == /var/tmp/* ]] || [[ "$path" == /dev/shm/* ]]; then
            log_find "Suspicious library path in $conf: $path"
        fi
    done < "$conf"
done

info "Recently modified shared libraries (7 days):"
for libdir in /lib /lib64 /usr/lib /usr/lib64; do
    [ -d "$libdir" ] || continue
    find "$libdir" -name "*.so*" -mtime -7 2>/dev/null | head -10 | while read -r lib; do
        warn "Recent library: $lib"
    done
done

ok "LD_PRELOAD audit complete"

#=============================================================================
phase "8 - Binary Integrity Verification"
#=============================================================================

info "Checking critical service binaries against package manager..."
if command -v dpkg &>/dev/null; then
    dpkg --verify 2>/dev/null | grep -E '(sshd|apache|nginx|mysql|postfix|dovecot|named|vsftpd|proftpd)' | while read -r line; do
        finding "Modified package binary: $line"
    done
elif command -v rpm &>/dev/null; then
    rpm -Va 2>/dev/null | grep -E '(sshd|httpd|nginx|mysql|mariadb|postfix|dovecot|named|vsftpd)' | while read -r line; do
        finding "Modified package binary: $line"
    done
fi
ok "Binary integrity check complete"

#=============================================================================
# SUMMARY
#=============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
phase "Hunt Complete"
if [ "$FINDINGS" -eq 0 ]; then
    ok "No persistence findings detected"
else
    warn "Total findings: $FINDINGS"
    warn "Review each [FINDING] above and remediate"
fi
echo ""
ok "Completed in ${DURATION}s"

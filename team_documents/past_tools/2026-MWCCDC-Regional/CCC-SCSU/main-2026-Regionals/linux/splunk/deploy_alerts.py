import requests
import urllib3

urllib3.disable_warnings()

# ─── CHANGE THESE AT COMPETITION ─────────────────────────────────────────────
SPLUNK_IP = "YOUR-INDEXER_IP"       # IP of Your Splunk Server
SPLUNK_PASSWORD = "YOUR-PASSWORD"   # Splunk admin password
# ─────────────────────────────────────────────────────────────────────────────

AUTH = ("admin", SPLUNK_PASSWORD)
API = f"https://{SPLUNK_IP}:8089/servicesNS/admin/search/saved/searches"
INDEX_API = f"https://{SPLUNK_IP}:8089/servicesNS/admin/search/data/indexes"


def check_indexes():
    required = ["main", "security", "sysmon"]
    print("Checking indexes...")
    missing = []
    for idx in required:
        r = requests.get(f"{INDEX_API}/{idx}", auth=AUTH, verify=False)
        if r.status_code == 200:
            print(f"  ✓  index={idx} exists")
        else:
            print(f"  ✗  index={idx} MISSING — create it in GUI: Settings → Indexes → New Index")
            missing.append(idx)
    if missing:
        print(f"\n  ⚠ Create these indexes in Splunk GUI before continuing: {missing}")
        print("  Settings → Indexes → New Index\n")
        answer = input("  Continue anyway? (y/n): ")
        if answer.lower() != "y":
            print("Exiting. Create indexes first then rerun.")
            exit(1)
    else:
        print("  All indexes present!\n")


ALERTS = [

    # ── SECURITY INDEX — Windows Event Logs ───────────────────────────────────
    {
        "name": "ALERT-BruteForce-Windows",
        "search": "index=security EventCode=4625 | stats count by src_ip | where count > 10",
        "cron": "*/5 * * * *",
        "description": "Windows brute force: >10 failed logins in 5 min"
    },
    {
        "name": "ALERT-Win-Login-Success",
        "search": "index=security EventCode=4624 | table _time host user src_ip",
        "cron": "*/5 * * * *",
        "description": "Successful Windows logins"
    },
    {
        "name": "ALERT-Admin-Login",
        "search": 'index=security EventCode=4624 Account_Name="*admin*" | table _time host user src_ip',
        "cron": "*/5 * * * *",
        "description": "Admin account login detected"
    },
    {
        "name": "ALERT-New-User-Created",
        "search": "index=security EventCode=4720 | table _time host user Message",
        "cron": "*/2 * * * *",
        "description": "New user account created - should only be blue team activity"
    },
    {
        "name": "ALERT-User-Deleted",
        "search": "index=security EventCode=4726 | table _time host user",
        "cron": "*/5 * * * *",
        "description": "User account deleted"
    },
    {
        "name": "ALERT-AdminGroup-Changed",
        "search": "index=security (EventCode=4728 OR EventCode=4732) | table _time host user Message",
        "cron": "*/2 * * * *",
        "description": "User added to privileged group - almost certainly red team activity"
    },
    {
        "name": "ALERT-NewService-Installed",
        "search": "index=security EventCode=7045 | table _time host ServiceName ServiceFileName",
        "cron": "*/5 * * * *",
        "description": "New Windows service installed - common persistence method"
    },
    {
        "name": "ALERT-Scheduled-Task",
        "search": "index=security EventCode=4698 | table _time host user TaskName",
        "cron": "*/5 * * * *",
        "description": "Scheduled task created - persistence method"
    },
    {
        "name": "ALERT-PowerShell-Execution",
        "search": "index=security EventCode=4104 | table _time host ScriptBlockText",
        "cron": "*/5 * * * *",
        "description": "PowerShell script execution"
    },
    {
        "name": "ALERT-PowerShell-Encoded",
        "search": 'index=security EventCode=4104 "-enc" | table _time host ScriptBlockText',
        "cron": "*/5 * * * *",
        "description": "Encoded/obfuscated PowerShell execution"
    },

    # ── SYSMON INDEX ──────────────────────────────────────────────────────────
    {
        "name": "ALERT-Sysmon-Whoami-Execution",
        "search": 'index=sysmon EventCode=1 Image="*whoami.exe" | table _time Computer User Image CommandLine ParentImage',
        "cron": "*/2 * * * *",
        "description": "whoami.exe ran - first thing red team runs after getting a shell"
    },
    {
        "name": "ALERT-Sysmon-CobaltStrike-MSEdge",
        "search": 'index=sysmon EventCode=10 TargetImage="*msedge*" | table _time Computer User SourceImage TargetImage GrantedAccess',
        "cron": "*/2 * * * *",
        "description": "Process injecting into msedge.exe - matches known Cobalt Strike default config"
    },
    {
        "name": "ALERT-DNS-Tunnel-LargeQueryName",
        "search": 'index=sysmon EventCode=22 | eval qlen=len(QueryName) | where qlen > 50 | table _time Computer User Image QueryName qlen | sort -qlen',
        "cron": "*/3 * * * *",
        "description": "Sysmon: Long DNS QueryName - likely base64 payload in subdomain"
    },
    {
        "name": "ALERT-DNS-Tunnel-HighFrequency",
        "search": 'index=sysmon EventCode=22 | rex field=QueryName "^[^.]+\\.(?P<domain>.+)$" | stats count by domain Computer User | where count > 15 | sort -count | table Computer User domain count',
        "cron": "*/3 * * * *",
        "description": "Sysmon: Many DNS queries to same domain - small-chunk DNS tunneling"
    },
    {
        "name": "ALERT-DNS-Tunnel-Base64-Subdomain",
        "search": 'index=sysmon EventCode=22 | rex field=QueryName "^(?P<subdomain>[^.]+)" | where match(subdomain, "^[A-Za-z0-9+/]{20,}={0,2}$") | table _time Computer User Image QueryName subdomain | sort -_time',
        "cron": "*/3 * * * *",
        "description": "Sysmon: Base64-looking subdomain in DNS query - high confidence DNS tunneling"
    },

    # ── MAIN INDEX — Fedora / Linux Logs ──────────────────────────────────────
    {
        "name": "ALERT-BruteForce-Linux",
        "search": 'index=main source="/var/log/secure" "Failed password" | stats count by host src_ip | where count > 5',
        "cron": "*/5 * * * *",
        "description": "SSH brute force on Fedora machine"
    },
    {
        "name": "ALERT-Fedora-SSH-RootLogin",
        "search": 'index=main source="/var/log/secure" "Accepted password for root" OR "Accepted publickey for root"',
        "cron": "*/2 * * * *",
        "description": "Someone logged in as root via SSH - should never happen"
    },
    {
        "name": "ALERT-Fedora-SSH-NewConnection",
        "search": 'index=main source="/var/log/secure" "Accepted" | table _time host user src_ip',
        "cron": "*/2 * * * *",
        "description": "Any successful SSH login on Fedora"
    },
    {
        "name": "ALERT-Fedora-Sudo-Escalation",
        "search": 'index=main source="/var/log/secure" "sudo" NOT "session opened for user root by root" | table _time host user',
        "cron": "*/5 * * * *",
        "description": "Sudo usage on Fedora - watch for unexpected users"
    },
    {
        "name": "ALERT-Fedora-NewUser-Created",
        "search": 'index=main source="/var/log/secure" "new user" OR "new group" | table _time host message',
        "cron": "*/5 * * * *",
        "description": "New user or group created on Fedora"
    },
    {
        "name": "ALERT-Fedora-SegFault",
        "search": 'index=main source="/var/log/messages" "segfault" | table _time host message',
        "cron": "*/5 * * * *",
        "description": "Segfault - could indicate exploit attempt or crashing malware"
    },
    {
        "name": "ALERT-Fedora-OOM-Killed",
        "search": 'index=main source="/var/log/messages" "Out of memory" OR "oom_kill" | table _time host message',
        "cron": "*/5 * * * *",
        "description": "Out of memory killed - possible resource exhaustion"
    },
    {
        "name": "ALERT-Fedora-Kernel-Error",
        "search": 'index=main source="/var/log/messages" "kernel" ("error" OR "panic" OR "BUG") | table _time host message',
        "cron": "*/5 * * * *",
        "description": "Kernel-level errors on Fedora"
    },
    {
        "name": "ALERT-Mail-SpamFlood",
        "search": 'index=main source="/var/log/maillog" | stats count by host | where count > 100',
        "cron": "*/5 * * * *",
        "description": "High volume mail activity - possible spam flood"
    },
    {
        "name": "ALERT-Mail-AuthFail",
        "search": 'index=main source="/var/log/maillog" ("authentication failed" OR "SASL LOGIN authentication failed") | stats count by src_ip | where count > 5',
        "cron": "*/5 * * * *",
        "description": "Mail auth failures - brute force against mail server"
    },
    {
        "name": "ALERT-Mail-OpenRelay",
        "search": 'index=main source="/var/log/maillog" "relay" NOT "relay=local" | table _time host message',
        "cron": "*/5 * * * *",
        "description": "Mail relay activity - check if being used as open relay"
    },
    {
        "name": "ALERT-Fedora-NewCronJob",
        "search": 'index=main source="/var/log/cron" ("CROND" OR "crontab") "edited" OR "new" | table _time host user message',
        "cron": "*/5 * * * *",
        "description": "New cron job - common attacker persistence method"
    },
    {
        "name": "ALERT-Fedora-Cron-SuspiciousCmd",
        "search": 'index=main source="/var/log/cron" ("/tmp" OR "bash -i" OR "nc " OR "curl" OR "wget") | table _time host user message',
        "cron": "*/5 * * * *",
        "description": "Cron running suspicious commands - likely malicious persistence"
    },
    {
        "name": "ALERT-HTTP-404Flood",
        "search": 'index=main (source="/var/log/httpd/access_log" OR source="/var/log/httpd/error_log") status=404 | stats count by src_ip | where count > 50',
        "cron": "*/5 * * * *",
        "description": "Web scanning / directory brute force"
    },
    {
        "name": "ALERT-HTTP-WebShell",
        "search": 'index=main source="/var/log/httpd/access_log" (uri="*.php*" OR uri="*.sh*") ("cmd=" OR "exec=" OR "system(" OR "passthru" OR "base64") | table _time host src_ip uri',
        "cron": "*/3 * * * *",
        "description": "Possible web shell or command injection via HTTP"
    },
    {
        "name": "ALERT-HTTP-SQLInjection",
        "search": 'index=main source="/var/log/httpd/access_log" ("UNION SELECT" OR "1=1" OR "DROP TABLE" OR "xp_cmdshell") | table _time host src_ip uri',
        "cron": "*/3 * * * *",
        "description": "SQL injection attempt in web logs"
    },
    {
        "name": "ALERT-HTTP-Error500Flood",
        "search": 'index=main source="/var/log/httpd/error_log" "error" | stats count by host | where count > 30',
        "cron": "*/5 * * * *",
        "description": "High Apache error rate - possible exploit attempt"
    },
    {
        "name": "ALERT-DNS-ZoneTransfer",
        "search": 'index=main source="/var/log/named/*" "AXFR" OR "zone transfer" | table _time host src_ip message',
        "cron": "*/2 * * * *",
        "description": "DNS zone transfer attempt - attacker mapping DNS records"
    },
    {
        "name": "ALERT-DNS-QueryFlood",
        "search": 'index=main source="/var/log/named/*" | stats count by src_ip | where count > 200',
        "cron": "*/5 * * * *",
        "description": "DNS query flood - possible DDoS or tunneling"
    },
    {
        "name": "ALERT-DNS-Tunneling-Named",
        "search": 'index=main source="/var/log/named/*" | eval qlen=len(query) | where qlen > 50 | stats count by src_ip query | where count > 10',
        "cron": "*/5 * * * *",
        "description": "Long DNS queries via named - possible DNS tunneling"
    },
    {
        "name": "ALERT-DNS-NXDOMAIN-Flood",
        "search": 'index=main source="/var/log/named/*" "NXDOMAIN" | stats count by src_ip | where count > 50',
        "cron": "*/5 * * * *",
        "description": "High NXDOMAIN rate - possible DGA malware or recon"
    },
    {
        "name": "ALERT-Audit-PrivEsc",
        "search": 'index=main source="/var/log/audit*" "type=SYSCALL" ("execve" OR "setuid") "auid!=0" | table _time host user exe',
        "cron": "*/5 * * * *",
        "description": "Privilege escalation caught by auditd"
    },
    {
        "name": "ALERT-Audit-FileChange-Passwd",
        "search": 'index=main source="/var/log/audit*" ("/etc/passwd" OR "/etc/shadow" OR "/etc/sudoers") | table _time host user exe message',
        "cron": "*/2 * * * *",
        "description": "Critical system files modified"
    },
    {
        "name": "ALERT-Audit-SuspiciousExec",
        "search": 'index=main source="/var/log/audit*" "type=EXECVE" ("/tmp" OR "/dev/shm" OR "nc " OR "bash -i" OR "python -c") | table _time host user exe',
        "cron": "*/3 * * * *",
        "description": "Suspicious binary execution caught by auditd"
    },
    {
        "name": "ALERT-UFW-PortScan",
        "search": 'index=main source="/var/log/ufw.log" "BLOCK" | stats count by src_ip | where count > 20',
        "cron": "*/3 * * * *",
        "description": "Port scan detected via UFW"
    },
    {
        "name": "ALERT-UFW-Repeated-Block",
        "search": 'index=main source="/var/log/ufw.log" "BLOCK" | stats count by src_ip dest_port | where count > 10 | sort -count',
        "cron": "*/5 * * * *",
        "description": "Repeated connection attempts to specific port"
    },
    {
        "name": "ALERT-Firewalld-RuleChange",
        "search": 'index=main sourcetype="journald" unit="firewalld" ("Reload" OR "rule" OR "zone") | table _time host message',
        "cron": "*/2 * * * *",
        "description": "Firewalld rules changed - attacker may be opening ports"
    },
    {
        "name": "ALERT-Firewalld-Stopped",
        "search": 'index=main sourcetype="journald" unit="firewalld" ("Stopped" OR "stop" OR "deactivating") | table _time host message',
        "cron": "*/2 * * * *",
        "description": "Firewalld stopped - firewall is down!"
    },
    {
        "name": "ALERT-DNS-Resolver-Changed",
        "search": 'index=main sourcetype="journald" unit="systemd-resolved" ("DNS server" OR "nameserver" OR "DNSSEC") | table _time host message',
        "cron": "*/5 * * * *",
        "description": "DNS resolver config changed - possible DNS hijacking"
    },
    {
        "name": "ALERT-TempDir-Execution",
        "search": 'index=main ("/tmp" OR "/dev/shm") | table _time host user process',
        "cron": "*/5 * * * *",
        "description": "Process executed from /tmp or /dev/shm - malware indicator"
    },
    {
        "name": "ALERT-Outbound-Suspicious",
        "search": "index=main dest_ip!=10.0.0.0/8 dest_ip!=192.168.0.0/16 | stats count by src_ip dest_ip | where count > 20",
        "cron": "*/5 * * * *",
        "description": "High volume outbound traffic to external IPs"
    },
    {
        "name": "ALERT-DNS-HighFrequency",
        "search": 'index=* sourcetype=dns NOT (query=*scsu.edu* OR query=*microsoft.com* OR query=*windows.com*) | stats count by query src_ip | where count > 20 | sort -count',
        "cron": "*/5 * * * *",
        "description": "High-frequency DNS queries to unexpected domains"
    },

    # ── AIO Hardening Script Logs ─────────────────────────────────────────────
    {
        "name": "ALERT-AIO-Error-Warning",
        "search": 'index=main source="/var/log/aio_hardening/*" ("ERROR" OR "FAIL" OR "warn") | table _time host message',
        "cron": "*/5 * * * *",
        "description": "AIO hardening script logged an error or warning"
    },
    {
        "name": "ALERT-AIO-Phase-Failed",
        "search": 'index=main source="/var/log/aio_hardening/*" ("Phase 1 failed" OR "Phase 2 failed" OR "Phase 3 failed") | table _time host message',
        "cron": "*/5 * * * *",
        "description": "AIO hardening phase failed - check immediately"
    },

    # ── Red Flags Monitor ─────────────────────────────────────────────────────
    {
        "name": "ALERT-RedFlags-Any",
        "search": 'index=main source="/var/log/redflags/*" | table _time host message',
        "cron": "*/2 * * * *",
        "description": "AIO monitoring detected a red flag - check immediately"
    },
    {
        "name": "ALERT-RedFlags-Critical",
        "search": 'index=main source="/var/log/redflags/*" ("critical" OR "CRITICAL" OR "high" OR "HIGH" OR "danger") | table _time host message',
        "cron": "*/2 * * * *",
        "description": "AIO monitoring detected a critical red flag"
    },

    # ── ZEEK ──────────────────────────────────────────────────────────────────
    {
        "name": "ALERT-Zeek-C2-Beaconing",
        "search": 'index=main source="/var/log/zeek/conn.log" | bucket _time span=1m | stats count by id.orig_h id.resp_h | stats stdev(count) as variance count as windows by id.orig_h id.resp_h | where variance < 2 AND windows > 10 | sort variance',
        "cron": "*/5 * * * *",
        "description": "Zeek: Regular interval connections = C2 beaconing"
    },
    {
        "name": "ALERT-Zeek-DNS-Tunneling",
        "search": 'index=main source="/var/log/zeek/dns.log" | eval qlen=len(query) | where qlen > 50 | stats count by id.orig_h query | where count > 5',
        "cron": "*/5 * * * *",
        "description": "Zeek: Long DNS queries - possible DNS tunnel"
    },
    {
        "name": "ALERT-Zeek-LongConnection",
        "search": 'index=main source="/var/log/zeek/conn.log" duration > 3600 | table _time id.orig_h id.resp_h id.resp_p duration bytes',
        "cron": "*/10 * * * *",
        "description": "Zeek: Connection over 1 hour - possible C2 or exfil"
    },
    {
        "name": "ALERT-Zeek-LargeUpload",
        "search": 'index=main source="/var/log/zeek/conn.log" | where orig_bytes > 10000000 | table _time id.orig_h id.resp_h orig_bytes',
        "cron": "*/5 * * * *",
        "description": "Zeek: Large outbound transfer (>10MB) - possible exfil"
    },
    {
        "name": "ALERT-Zeek-PortScan",
        "search": 'index=main source="/var/log/zeek/conn.log" | stats dc(id.resp_p) as ports by id.orig_h | where ports > 20',
        "cron": "*/5 * * * *",
        "description": "Zeek: One host hitting many ports - port scan"
    },
    {
        "name": "ALERT-Zeek-HTTP-BadUserAgent",
        "search": 'index=main source="/var/log/zeek/http.log" (user_agent="*curl*" OR user_agent="*wget*" OR user_agent="*python*" OR user_agent="*nmap*") | table _time id.orig_h id.resp_h uri user_agent',
        "cron": "*/5 * * * *",
        "description": "Zeek: Suspicious HTTP user agents"
    },
    {
        "name": "ALERT-Zeek-SSH-External",
        "search": 'index=main source="/var/log/zeek/ssh.log" NOT id.orig_h=10.0.0.0/8 NOT id.orig_h=192.168.0.0/16 | table _time id.orig_h id.resp_h auth_success',
        "cron": "*/2 * * * *",
        "description": "Zeek: SSH from external IP"
    },
    {
        "name": "ALERT-Zeek-Notice",
        "search": 'index=main source="/var/log/zeek/notice.log" | table _time note msg src dst',
        "cron": "*/3 * * * *",
        "description": "Zeek: Built-in threat detection fired"
    },
]


def create_alert(alert):
    data = {
        "name": alert["name"],
        "search": alert["search"],
        "dispatch.earliest_time": "-5m",
        "dispatch.latest_time": "now",
        "alert_type": "number of events",
        "alert_comparator": "greater than",
        "alert_threshold": "0",
        "cron_schedule": alert["cron"],
        "is_scheduled": "1",
        "actions": "add_to_triggered_alerts",
        "description": alert.get("description", ""),
    }
    r = requests.post(API, data=data, auth=AUTH, verify=False)
    if r.status_code == 201:
        print(f"  ✓  {alert['name']}")
    elif r.status_code == 409:
        print(f"  ~  {alert['name']} (already exists, skipping)")
    else:
        print(f"  ✗  {alert['name']} — HTTP {r.status_code}: {r.text[:120]}")


if __name__ == "__main__":
    print(f"\nConnecting to Splunk at {SPLUNK_IP}...")
    check_indexes()
    print(f"Deploying {len(ALERTS)} alerts...\n")
    for alert in ALERTS:
        create_alert(alert)
    print("\nDone! Check: Activity → Triggered Alerts in Splunk Web\n")


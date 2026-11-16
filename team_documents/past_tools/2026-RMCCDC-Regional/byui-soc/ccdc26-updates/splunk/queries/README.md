# CCDC26 Splunk Threat Hunting Queries

Pre-built SPL queries for rapid threat detection during competition. Copy-paste directly into Splunk search.

## Quick Start

1. Open Splunk Web UI at `https://<SPLUNK_SERVER>:8000` (check `config.env` for IP)
2. Go to **Search & Reporting**
3. Copy any query from the `.spl` files below
4. Paste into the search bar and adjust the time range
5. For the dashboard, go to **Dashboards > Create New Dashboard > Source** and paste `dashboards.xml`

## Index Reference

### Windows Indexes

| Index | Contents | Sourcetypes |
|-------|----------|-------------|
| `windows-security` | Security EventLog, Defender, Firewall, TaskScheduler, RDP, Directory Service | `WinEventLog:Security`, `WinEventLog:Defender`, `WinEventLog:Firewall`, `WinEventLog:TaskScheduler`, `WinEventLog:RDP`, `WinEventLog:DirectoryService` |
| `windows-system` | System EventLog | `WinEventLog:System` |
| `windows-application` | Application EventLog | `WinEventLog:Application` |
| `windows-powershell` | PowerShell Operational, PowerShellCore | `WinEventLog:PowerShell` |
| `windows-sysmon` | Sysmon Operational (XML) | `WinEventLog:Sysmon` |
| `windows-dns` | DNS Server EventLog | `WinEventLog:DNS` |

### Linux Indexes

| Index | Contents | Sourcetypes |
|-------|----------|-------------|
| `linux-security` | auth.log, secure, audit.log, fail2ban | `linux_secure`, `linux_audit`, `fail2ban` |
| `linux-os` | syslog, messages, kern.log, cron | `syslog`, `linux_kernel`, `cron` |
| `linux-web` | Apache, Nginx access/error logs | `access_combined`, `apache_error`, `nginx_error` |
| `linux-database` | MySQL, MariaDB, PostgreSQL logs | `mysql_error`, `postgresql` |
| `linux-mail` | mail.log, maillog | `sendmail` |
| `linux-dns` | BIND/named query logs | `named` |
| `linux-ftp` | vsftpd, proftpd logs | `vsftpd`, `proftpd` |

## Query Files

| File | Purpose |
|------|---------|
| `windows-threats.spl` | Windows event log threat detection (brute force, credential theft, process abuse) |
| `linux-threats.spl` | Linux log threat detection (SSH attacks, web shells, SQLi, privilege escalation) |
| `active-directory.spl` | AD attack detection (Kerberoasting, DCSync, Golden Ticket, password spray) |
| `lateral-movement.spl` | Cross-platform lateral movement (PsExec, WMI, SMB, RDP, SSH pivoting) |
| `persistence.spl` | Persistence mechanisms (registry, scheduled tasks, services, cron, systemd) |
| `c2-detection.spl` | C2 and beaconing (DNS tunneling, HTTP beaconing, data exfil, known frameworks) |
| `dashboards.xml` | Splunk Simple XML dashboard for quick import |

## Time Range Recommendations

| Query Type | Recommended Range | Splunk Syntax |
|------------|-------------------|---------------|
| Active brute force | Last 15 minutes | `earliest=-15m` |
| Credential attacks | Last 1 hour | `earliest=-1h` |
| Account/config changes | Last 24 hours | `earliest=-24h` |
| Persistence hunting | Last 7 days | `earliest=-7d` |
| Lateral movement | Last 4 hours | `earliest=-4h` |
| C2 beaconing | Last 24 hours | `earliest=-24h` |
| Full investigation | Since competition start | `earliest=-3d` |

## Competition Network

- Splunk Server: check `config.env` for `SPLUNK_SERVER` IP
- Receiver Port: `9997` (default)
- Web UI: `https://<SPLUNK_SERVER>:8000`
- Management: `https://<SPLUNK_SERVER>:8089`

## Tips

- Use `| head 100` at the end of expensive queries to limit results during initial triage
- Add `host=<hostname>` to scope queries to a specific machine
- Use `| table` to select specific fields for cleaner output
- Combine queries with `OR` in the search bar for broader detection
- Save frequently-used queries as reports in Splunk for one-click access
- Use `ctrl+\` in the Splunk search bar to expand multi-line queries

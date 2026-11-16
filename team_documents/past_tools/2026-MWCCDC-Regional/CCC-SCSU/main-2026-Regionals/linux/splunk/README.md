# deploy_alerts.py
### the script that does your job for you

## Description

Look, manually creating Splunk alerts one by one during a
competition where red team is actively trying to ruin your day sounds
like a terrible time. So we automated it.

`deploy_alerts.py` connects to your Splunk instance and deploys all
security alerts in one command so you can spend less time clicking
around and more time watching red team cry when their C2 beacon
gets caught.

The script monitors for:
- Windows brute force, privilege escalation, new users, PowerShell execution, persistence
- Sysmon events: whoami execution, Cobalt Strike msedge injection, DNS tunneling
- Linux/Fedora SSH attacks, sudo escalation, cron persistence, auditd events
- Web server attacks: 404 floods, web shells, SQL injection
- DNS attacks: zone transfers, query floods, tunneling via named and Sysmon
- Mail server: auth failures, spam floods, open relay
- Firewall: firewalld stopped or rules changed
- Zeek network monitoring: C2 beaconing, large uploads, port scans
- AIO hardening script: errors, warnings, red flags
- Red Flags: anything the AIO monitoring script flags as suspicious

---

## Requirements

- Python 3
- `requests` library (one whole dependency, very manageable)
```bash
pip3 install requests --break-system-packages
```

---

## How to Use

### Step 1 — Clone the repo
```bash
git clone https://github.com/YOUR-ORG/YOUR-REPO.git
cd YOUR-REPO
```

### Step 2 — Fill in your Splunk details
```bash
nano deploy_alerts.py
```

Change these two lines at the top:
```python
SPLUNK_IP = "YOUR-INDEXER-IP"      # IP address of your Splunk server
SPLUNK_PASSWORD = "YOUR-PASSWORD"  # Splunk admin password
```
Save with `Ctrl+X → Y → Enter`

### Step 3 — Install the Splunk apps
```bash
cd apps/
sudo tar -xvzf splunk-add-on-for-sysmon.tgz -C /opt/splunk/etc/apps/
sudo tar -xvzf splunk-add-on-for-microsoft-windows.tgz -C /opt/splunk/etc/apps/
sudo tar -xvzf splunk-add-on-for-unix-and-linux.tgz -C /opt/splunk/etc/apps/
cd /opt/splunk/bin && sudo ./splunk restart
```

### Step 4 — Create required indexes in Splunk GUI
Because unfortunately we can't do everything for you.
```
Settings → Indexes → New Index
```
You need these three:
- `main` (probably already exists, check anyway)
- `security`
- `sysmon`

### Step 5 — Run it
```bash
python3 deploy_alerts.py
```
Grab a snack. It'll be done before you get back.

---

## Expected Output
```
Connecting to Splunk at 172.x.x.x...
Checking indexes...
  ✓  index=main exists
  ✓  index=security exists
  ✓  index=sysmon exists
  All indexes present!

Deploying 59 alerts...

  ✓  ALERT-BruteForce-Windows
  ✓  ALERT-BruteForce-Linux
  ✓  ALERT-Sysmon-Whoami-Execution
  ... (56 more ✓'s)

Done! Check: Activity → Triggered Alerts in Splunk Web
```

| Symbol | Meaning |
|---|---|
| `✓` | Alert created successfully |
| `~` | Already exists, skipped |
| `✗` | Something broke, check the error message |

---

## Verifying Alerts Are Running

In Splunk Web:
```
Activity → Triggered Alerts
```
If red team is doing anything suspicious it'll show up here.
Check it often. Like, really often.

Also confirm all alerts exist at:
```
Settings → Searches Reports and Alerts → filter Type: Alert
```

---


## Splunk Apps (install before running script)

Download from [splunkbase.splunk.com](https://splunkbase.splunk.com) and install:
```bash
cd apps/
sudo tar -xvzf splunk-add-on-for-sysmon.tgz -C /opt/splunk/etc/apps/
sudo tar -xvzf splunk-add-on-for-microsoft-windows.tgz -C /opt/splunk/etc/apps/
sudo tar -xvzf splunk-add-on-for-unix-and-linux.tgz -C /opt/splunk/etc/apps/
sudo tar -xvzf splunk-security-essentials.tgz -C /opt/splunk/etc/apps/
sudo ./splunk restart
```

| App | Why |
|---|---|
| Splunk Add-on for Sysmon | Required — DNS tunneling and Cobalt Strike alerts need this |
| Splunk Add-on for Microsoft Windows | Recommended — proper Windows field parsing |
| Splunk Add-on for Unix and Linux | Recommended — proper Linux field parsing |
| Splunk Security Essentials | Optional — pre-built security detections and dashboards |

---


## Files
```
├── deploy_alerts.py                              # main script — run this
├── README.md                                     # this file
└── apps/
    ├── splunk-add-on-for-sysmon.tgz              # required - DNS tunneling + Cobalt Strike alerts
    ├── splunk-add-on-for-microsoft-windows.tgz   # recommended - Windows field parsing
    ├── splunk-add-on-for-unix-and-linux.tgz      # recommended - Linux field parsing
    └── splunk-security-essentials.tgz            # download separately from splunkbase.splunk.com - too large for GitHub
```

---

## Notes

- Safe to re-run — existing alerts get skipped, nothing explodes
- Do NOT push real credentials to GitHub (red team can use Google too)
- Change the default Splunk password the second you log in
- If something's on fire check `Activity → Triggered Alerts` first,
  panic second

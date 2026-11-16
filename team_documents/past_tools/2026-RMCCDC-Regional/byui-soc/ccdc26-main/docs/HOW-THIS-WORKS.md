# How This Works

A plain-language guide to CCDC, our competition environment, and what
every tool in this repository does. Written for someone who has never
competed in CCDC before.

---

## What is CCDC?

CCDC (Collegiate Cyber Defense Competition) is a cybersecurity competition
where your team manages a small corporate network. A professional red team
(penetration testers hired by the competition) attacks you from the moment
the clock starts. Meanwhile, an automated scoring engine checks whether
your services -- websites, email, file sharing -- are still working.

You're judged on three things:

1. **Uptime** -- keeping your services running. Every few minutes the
   scoring engine tries to use your services like a normal customer would
   (logging into webmail, browsing the web store, resolving DNS). If it
   can't, you lose points.
2. **Defense** -- stopping the red team from taking over your machines,
   stealing data, or planting backdoors.
3. **Injects** -- business tasks the competition throws at you during the
   event ("write a policy document," "set up a new user account,"
   "produce a network diagram"). Think of these as assignments from your
   fictional CEO.

The competition lasts about eight hours. It is very fast. The first 15
minutes determine a lot -- if you haven't changed default passwords and
patched critical vulnerabilities by then, red team is already inside.

---

## The Competition Network

### What to Expect

Every CCDC environment is different, but they follow a pattern. You'll
get a "competition packet" at flag drop that tells you what machines you
have, their IPs, and what services are scored. Read it carefully.

### Typical Setup

The network usually has:

- **Linux servers** -- various distributions running scored services
  (web servers, email, databases, etc.)
- **Windows servers** -- usually centered around Active Directory, with
  one or more domain controllers plus member servers
- **Network devices** -- firewalls and/or routers separating zones
- **A scoring engine** -- sits outside your network and periodically
  tests your services

Think of it like a small company network. You're the IT team.

### Common Machine Types

**Linux machines you might see:**

| Type | What it does |
|------|-------------|
| Web server | E-commerce, CMS (WordPress, Joomla), or custom web app. Usually scored. |
| Mail server | Email (Postfix, Dovecot). Usually scored (SMTP/POP3/IMAP). |
| DNS server | Sometimes a standalone Linux DNS. Scored if present. |
| Database server | MySQL/MariaDB/PostgreSQL backing a web app. |
| Splunk / SIEM server | Log aggregation. Think of it as security cameras for every machine. |
| Workstation | General-purpose Linux desktop. |

**Windows machines you might see:**

| Type | What it does |
|------|-------------|
| Domain Controller (DC) | The "brain" of the Windows network. Controls user accounts, group policies, and usually DNS. **If this falls, the attacker owns everything.** |
| Web server (IIS) | A Windows-based website. Usually scored. |
| File server / FTP | File sharing. Sometimes scored. |
| Workstation | General-purpose Windows desktop. |

**Network devices you might see:**

| Type | What it does |
|------|-------------|
| Firewall (any vendor) | Controls what traffic goes in/out. Could be Palo Alto, Cisco FTD/ASA, pfSense, FortiGate, etc. |
| Router | Connects zones to each other and to the outside. Could be VyOS, Cisco IOS, etc. |

### How It All Connects (Typical)

```
                  [Scoring Engine]
                        |
                     [Router]
                    /        \
            [Firewall A]   [Firewall B]
                 |               |
           [Zone 1]        [Zone 2]
           - Linux hosts    - Windows hosts
```

The zones might be on different subnets with firewalls between them,
or everything might be flat on one network. **The packet tells you.**
The scoring engine sits outside and sends traffic through. If any link
in the chain is broken, it can't reach your services and you lose points.

> **Key takeaway:** Don't assume anything about the topology until you
> read the packet. Our scripts are designed to work regardless of the
> specific layout.

### The Red Team

Red team are professional penetration testers. They start attacking the
instant the competition begins. They will:

- Try default and common passwords on every service
- Exploit known vulnerabilities (unpatched software)
- Install backdoors so they can come back even after you kick them out
- Steal data and deface websites for points

They are very good. Assume they will get in. Your job is to make that as
hard as possible, detect them when they do, and remove them quickly.

---

## What is Monarch?

Monarch is our Linux orchestration tool. It lets you control all Linux
machines from one keyboard.

Without Monarch, you'd have to open a separate SSH session (remote
terminal connection) to each Linux machine, type commands on each one
individually, and hope you didn't forget a machine. With four machines,
that's four terminals and four times the work.

With Monarch, you type one command and it runs on every machine at the
same time.

### How It Works

Monarch is a Python program that uses SSH -- the same protocol you'd
normally use to log into a remote Linux machine. It opens connections to
all your machines in parallel (simultaneously) and dispatches commands or
scripts to each one.

### Key Commands

| Command | What it does |
|---------|-------------|
| `scan` | Finds all Linux machines on a network range automatically. Like sonar -- it pings every address and remembers which ones respond to SSH. |
| `script` | Uploads a script file to every machine via SFTP (secure file transfer) and runs it. This is how you deploy hardening, monitoring, and hunting scripts. |
| `rotate` | Changes the root password on every machine at once. |
| `shell` | Opens an interactive terminal session on one specific machine, for when you need to do something by hand. |
| `list` | Shows all machines Monarch knows about. |
| `upload` / `download` | Copies files to or from every machine. |

Monarch saves its host list in a config file (`conf.json`) so you don't
have to re-scan every time.

### Why It Matters

Speed wins in CCDC. Changing passwords on four machines manually takes
around ten minutes. With Monarch, it takes ten seconds. Deploying a
hardening script to every machine by hand means SSHing into each one,
copying the script over, running it, and checking the output -- per
machine. With Monarch, it's one command.

---

## What is Dovetail?

Dovetail is the Windows equivalent of Monarch. Same concept, different
protocol.

Instead of SSH, Dovetail uses **WinRM** (Windows Remote Management).
WinRM is the built-in Windows way to run commands on a remote machine --
think of it as Windows's answer to SSH. It uses PowerShell sessions
instead of bash shells.

### Key Features

- **Auto-discovery from Active Directory** -- pass `-Targets domain` and
  Dovetail queries AD to find every Windows machine on the network
  automatically.
- **Parallel dispatch** -- sends scripts to all machines as background
  jobs, collects output from each one.
- **Session management** -- establishes WinRM sessions once (`-Connect`),
  then reuses them for every script you dispatch. Can repair broken
  sessions without starting over.
- **Per-host logging** -- saves each machine's output to a separate log
  file so you can review what happened where.

---

## Why the Scripts are Numbered

The scripts in `monarch/scripts/` (Linux) and `dovetail/scripts/`
(Windows) are numbered because they're meant to run in order. Each one
builds on the last. Think of it like a recipe -- you can't frost a cake
before you bake it.

### `00-snapshot` -- Photograph the crime scene

Takes a complete picture of the system before you change anything:
running processes, network connections, user accounts, installed
packages, cron jobs, firewall rules, file hashes.

Why? Two reasons:

1. **Rollback** -- if your hardening breaks something, you can compare
   the "before" snapshot to figure out what changed.
2. **Inject responses** -- the competition may ask "what was on this
   machine when you received it?" You'll have the answer.

### `01-harden` / `01-blitz` -- Lock the doors

This is the most important script. It runs through a checklist of
security fixes:

- **Patch known vulnerabilities (CVEs)** -- the red team *will* exploit
  EternalBlue, PrintNightmare, and Zerologon in the first five minutes if
  you don't patch them. (More on these attacks below.)
- **Harden SSH / RDP** -- disable root login, enforce strong ciphers,
  limit login attempts.
- **Disable dangerous services** -- telnet, rsh, and other insecure
  protocols that have no business running.
- **Lock down file permissions** -- make sure sensitive files like
  `/etc/shadow` (password hashes) can only be read by root.
- **Tighten kernel settings** -- disable IP forwarding, enable SYN
  cookies (a defense against denial-of-service attacks), restrict access
  to kernel memory pointers.

The Windows version (`01-blitz.ps1`) does all of this plus Windows-
specific hardening: enabling the firewall with default-deny, protecting
LSASS (the process that stores credentials in memory), blocking LOLBins
(legitimate Windows programs that attackers abuse), and enabling
PowerShell logging.

### `02-firewall` / `02-ad` -- Set the rules

**Linux (`02-firewall.sh`):** Configures iptables or nftables rules to
block unauthorized access while allowing scored services through.
Think of it as a bouncer with a guest list -- only traffic that should
be there gets in.

**Windows (`02-ad.ps1`):** Fixes Active Directory-specific attacks:

- Rotates the `krbtgt` password (prevents golden ticket attacks)
- Enables AES encryption for Kerberos (prevents Kerberoasting)
- Patches Zerologon (a vulnerability that lets attackers reset the
  domain controller's machine password to blank)

### `03-services` / `03-audit` -- Harden the applications

Makes the scored services themselves harder to exploit:

- Disable unnecessary PHP functions on web servers
- Remove anonymous FTP access
- Tighten database permissions
- Restrict what web applications can do

The Windows `03-audit.ps1` enables comprehensive logging so you can
see what's happening -- PowerShell transcription, process creation
auditing, Windows Event Forwarding.

### `04-splunk` -- Send everything to one place

Deploys Splunk Universal Forwarder to every machine, configured to
ship logs to your Splunk server.

Why this matters: without centralized logging, you're blind. Each
machine generates its own logs, but nobody has time to SSH into four
machines and read log files during a competition. With Splunk, all
logs flow to one dashboard. When red team does something, you see it
in Splunk within seconds.

Think of it like connecting all your security cameras to one monitor
room instead of having to walk to each camera individually.

### `05-monitor` -- Watch for trouble

Sets up real-time monitoring and alerting:

- New processes starting
- New network connections being established
- New user accounts being created
- File integrity changes (someone modifying system files)

This is your early warning system. When red team gets in, these alerts
tell you about it.

---

## What the Hunt Scripts Do

Hunting is proactive -- you're not waiting for an alert, you're actively
searching for signs of compromise. Run these periodically throughout the
competition.

### `hunt-persistence` -- Find the backdoors

When red team gets into a machine, the first thing they do is install a
way to come back -- a "persistence mechanism." These scripts check every
known hiding spot:

- **Cron jobs** (Linux) / **Scheduled tasks** (Windows) -- commands that
  run automatically on a timer
- **Services** -- programs that start automatically at boot
- **SUID binaries** (Linux) -- programs that run with elevated
  privileges. If an attacker makes `/tmp/evil` run as root, they can use
  it to get root access anytime.
- **PAM modules** (Linux) -- the authentication system. Attackers can
  install a module that accepts any password.
- **Registry run keys** (Windows) -- settings that tell Windows to
  launch a program every time someone logs in
- **WMI event subscriptions** (Windows) -- invisible triggers that run
  commands when certain conditions are met (like "every five minutes" or
  "when someone logs in")

### `hunt-webshells` -- Find attacker scripts in web directories

A webshell is a tiny script (usually PHP or ASPX) that an attacker drops
into your web server's file directory. Once it's there, they can run
commands on your server through the website -- just by visiting a URL.

This script compares the files in your web directories against a known
baseline. Anything that wasn't there before is suspicious.

### `hunt-golden` -- Find forged authentication tokens

A golden ticket is a forged Kerberos authentication token. Kerberos is
the system Active Directory uses to prove "this person is who they claim
to be." A golden ticket is like a perfectly forged employee badge -- it
gives the attacker admin access to every Windows machine, and it works
even after you change passwords.

This script looks for Kerberos tickets with abnormally long lifetimes
(the forged ones typically last ten years instead of the normal ten
hours).

### `hunt-pii` -- Find sensitive data

CCDC sometimes has compliance injects: "Find all personally identifiable
information on your network." This script searches for patterns that look
like Social Security numbers, credit card numbers, and other sensitive
data.

### `scan-vulns` -- Find unpatched vulnerabilities

Uses Nuclei (a template-based vulnerability scanner) to check your services
for known CVEs. It downloads the scanner, pulls the latest templates, and
tests every listening port on the machine. Flags critical and high-severity
issues with specific remediation suggestions.

### `setup-waf` -- Deploy a Web Application Firewall

Installs ModSecurity with the OWASP Core Rule Set on Apache or Nginx.
This blocks SQL injection, cross-site scripting (XSS), path traversal,
and other common web attacks. Starts in blocking mode with paranoia
level 1 (fewest false positives). If it breaks the scoring engine,
you can switch it to detection-only mode.

### `setup-ids` -- Deploy a Network Intrusion Detection System

Installs Suricata, which monitors network traffic for known attack
signatures (like a security camera for your network). Runs in passive
mode -- it watches and logs, it does NOT block traffic. Logs go to
`/var/log/suricata/` for Splunk to ingest.

### `update-cms-creds` -- Update web app database passwords

When you rotate MySQL/MariaDB passwords, web applications like OpenCart,
WordPress, and Joomla store the database password in their config files.
If you change the DB password but don't update the config, the website
breaks. This script finds and updates all CMS config files automatically.

### `find-ips` -- Find hardcoded IP addresses

Searches configuration files for IP addresses. Useful when you need to
find every config that references a specific machine's IP, or when IPs
change during competition.

---

## What the IR Scripts Do

IR stands for "Incident Response." These are your emergency tools -- use
them when you know (or strongly suspect) you've been compromised.

### `ir-triage` -- What's happening right now?

A quick overview of the machine's current state:

- Who's logged in?
- What processes are running?
- What network connections are active?
- What has changed recently?

Run this first when something seems wrong. It's the equivalent of
walking into a room and looking around before touching anything.

### `ir-kill` -- Kick the attacker out

Terminates an attacker's session and optionally blocks their IP address.
When you've identified a malicious connection or login session, this
script ends it.

### `ir-collect` -- Package up the evidence

Gathers logs, process lists, network state, and other forensic data into
a compressed archive (tarball). Useful for:

- Detailed post-incident analysis
- Inject responses ("provide evidence of the compromise")
- Handing off to a teammate for review

### `ir-isolate` -- Cut the cord

The nuclear option. Blocks all network traffic to and from the machine
*except* SSH (so you can still manage it remotely). Use this when a
machine is actively being used by the attacker and you need to stop the
bleeding immediately.

Warning: this will also block scored service traffic, so you will lose
uptime points. Use it only when the alternative is worse.

---

## What the Sanity Check Does

`dovetail/scripts/sanity-check.ps1` is a verification tool. After
running the hardening scripts, it checks whether the changes actually
took effect.

It tests things like:

- Is SMBv1 disabled?
- Is the Windows firewall on with default-deny?
- Is LSASS protected (RunAsPPL)?
- Are LOLBins blocked from making outbound connections?
- Are PowerShell logs enabled?
- Is SMB signing required?

Each check gets a PASS, FAIL, or WARN. If anything fails, your
hardening didn't apply correctly and you need to fix it before moving on.

Think of it as a checklist a pilot runs through before takeoff -- you
don't just trust that everything is fine, you verify it.

---

## `config.env` Explained

`config.env` is a small configuration file with just the settings that
scripts actually need. Fill it in at competition start.

| Field | What it is | Where to find it |
|-------|-----------|-----------------|
| `SPLUNK_SERVER` | IP of your Splunk machine | Competition packet |
| `SPLUNK_PORT` | Splunk log receiving port | Usually `9997` -- don't change |
| `SPLUNK_VERSION` | Splunk version on the server | Run `/opt/splunk/bin/splunk version` |
| `SPLUNK_BUILD` | Build hash for the forwarder download | Same command shows the build hash |
| `WAZUH_MANAGER` | IP of Wazuh manager (if using Wazuh) | Same box as Splunk or a dedicated host |
| `COMP_USER` | Sudo user created on all Linux hosts | Default: `sysadmin` |
| `CONFIGURED` | Flip to `true` when done | Set after filling in Splunk values |

**You don't need to put host IPs in config.env.** Monarch discovers hosts
automatically via `scan`. Record IPs from the competition packet on your
printed QUICKREF.md credential tables or on paper instead.

Set `CONFIGURED=true` at the bottom of the file after filling in the
Splunk values. `deploy.sh` will warn you if it's still `false`.

---

## Common Red Team Attacks

Here's what you're defending against and which scripts handle each one.

### EternalBlue

**What:** Exploits a bug in SMBv1 (an old version of Windows file
sharing) to get remote admin access without any password.

**Analogy:** Imagine a back door in your office that was bricked over
years ago, except someone left the bricks loose. Anyone who knows can
push them in and walk right through.

**Fix:** `01-blitz.ps1` disables SMBv1 entirely.

### PrintNightmare

**What:** Exploits the Windows Print Spooler service to run code as
SYSTEM (the highest privilege level).

**Analogy:** The office printer has a "install driver" feature that
doesn't check who's asking. An attacker sends it a malicious "driver"
and now they control the machine.

**Fix:** `01-blitz.ps1` disables the Print Spooler and sets registry
keys to block the vulnerability.

### Zerologon

**What:** Resets the domain controller's machine account password to
blank. This gives the attacker full control over Active Directory.

**Analogy:** Someone walks up to the master key safe and resets the
combination to 0000.

**Fix:** `02-ad.ps1` applies the registry patch and monitors for
exploitation attempts.

### Kerberoasting

**What:** Requests encrypted service tickets from Active Directory and
cracks them offline to reveal service account passwords.

**Analogy:** You can ask the front desk for anyone's encrypted badge
number. The encryption is weak, so you take it home and crack it with
a computer.

**Fix:** `02-ad.ps1` switches service accounts to AES encryption
(much harder to crack) and flags accounts with weak encryption.

### Golden Ticket

**What:** Forges a Kerberos authentication token using the `krbtgt`
account's password hash. This gives the attacker admin access to every
machine in the domain, and it survives password changes.

**Analogy:** Someone stole the master stamp used to make employee
badges. They can make unlimited perfect forgeries.

**Fix:** `02-ad.ps1` rotates the `krbtgt` password twice (you need
two rotations because Kerberos remembers the previous password).
`hunt-golden.ps1` detects tickets with suspicious lifetimes.

### Webshells

**What:** A small script (PHP, ASPX, JSP) dropped in a web server's
file directory. It lets the attacker run commands through a web
browser.

**Analogy:** Someone slips a walkie-talkie into your office. They can
talk to it from outside and tell it to do things.

**Fix:** `hunt-webshells.ps1` scans web directories for files that
shouldn't be there.

### Cron/Task Backdoors

**What:** Scheduled commands that run periodically (every minute, every
hour, at boot) to maintain access or re-establish a connection.

**Analogy:** The attacker sets an alarm clock inside your building
that opens a window every five minutes.

**Fix:** `hunt-persistence.sh` / `hunt-persistence.ps1` enumerates
all scheduled tasks and cron jobs for review.

### Reverse Shells

**What:** A program on your machine that connects *out* to the
attacker's machine, giving them a remote command prompt. Because the
connection goes outbound, firewalls that only block incoming traffic
won't catch it.

**Analogy:** Instead of breaking into your building, the attacker
convinces someone inside to call them and leave the phone off the
hook.

**Fix:** `05-monitor` watches for suspicious outbound connections.
The emergency procedures in `ir-kill` terminate active reverse shells
and block the destination IP.

---

## Where to Learn More

| Resource | What's in it |
|----------|-------------|
| `docs/THREAT-HUNTING.md` | Detailed hunting procedures with step-by-step decision trees |
| `docs/TROUBLESHOOTING.md` | Fixes for common problems (SSH locked out, services down, scoring failures) |
| `docs/CHECKLIST.md` | Minute-by-minute competition day checklist |
| `docs/QUICKREF.md` | One-page command reference for Monarch, Dovetail, and common operations |
| `splunk/queries/` | Pre-built Splunk searches for detecting attacks (persistence, lateral movement, C2) |
| `injects/TEMPLATE.md` | How to format inject responses |

---

*Last updated: February 2026. If something in this document doesn't match
what you see in the repository, the code is the source of truth.*

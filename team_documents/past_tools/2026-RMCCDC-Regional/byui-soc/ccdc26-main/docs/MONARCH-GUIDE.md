# Monarch User Guide

Monarch is the Linux orchestration tool. It lets you control every Linux machine
from one keyboard. Instead of SSHing into each machine one by one, you type one
command and it executes on all machines simultaneously.

Monarch was originally built by the UC Irvine CCDC team (2025 National Champions).

---

## Starting Monarch

```bash
cd /opt/ccdc26/monarch
python3 -m monarch
```

You'll see a `>` prompt. This is the Monarch REPL (Read-Eval-Print Loop) --
an interactive shell where you type commands.

If you get a module error, install dependencies first:

```bash
pip3 install -r requirements.txt
python3 -m monarch
```

---

## First Steps (Competition Day)

```
> scan 10.0.1.0/24 changeme
```

This scans the subnet for machines with SSH on port 22, then tries to log in
with the password `changeme`. Every machine it successfully connects to gets
saved to `conf.json`.

You can scan multiple subnets or try multiple passwords:

```
> scan 10.0.1.0/24 changeme
> scan 10.0.2.0/24 password123 letmein
```

After scanning:

```
> list
root@10.0.1.11:22 (password changeme)
root@10.0.1.12:22 (password changeme)
root@10.0.1.13:22 (password changeme)
root@10.0.1.14:22 (password changeme)
```

---

## Core Commands

### list / ls

Shows all known hosts with their current user, IP, port, password, and aliases.

Example output (IPs and aliases will match your actual environment):

```
> list
root@10.0.1.11:22 (password changeme, aliases ecom)
root@10.0.1.12:22 (password changeme, aliases webmail)
root@10.0.1.13:22 (password xK9!mPq#2r, aliases splunk)
root@10.0.1.14:22 (password changeme)
```

This is your **live password inventory**. After every `rotate`, the passwords
update here automatically.

### script / sc

Runs a script on ALL hosts simultaneously. The script is uploaded via SFTP,
made executable, and executed. Output is collected per-host.

```
> script 01-harden.sh
```

To run on just ONE host, use `-H`:

```
> script -H ecom 01-harden.sh
```

Scripts must be in the `scripts/` directory. Monarch finds them by filename.

### rotate

Changes passwords on all hosts. Picks random passwords from `passwords.db`
(a CSV file with pre-generated strong passwords).

```
> rotate
```

To rotate just one host:

```
> rotate ecom
```

To set a specific password on all hosts:

```
> rotate -p "MyTeamP@ss2026!"
```

After rotation, `conf.json` is updated with the new passwords. Run `list`
to see them.

**How it works:** Monarch uploads `pass_for.sh` to each host, which runs
`chpasswd` to change the root password. It then verifies by trying to SSH
in with the new password. If verification fails, the old password is kept
in `conf.json`.

### shell / sh

Opens an interactive SSH session to a specific host.

```
> shell ecom
root@ecom:~#
```

You get a full terminal. Type `exit` to return to the Monarch prompt.

Monarch supports **fuzzy matching** -- you don't need the exact alias:

```
> shell eco        # matches "ecom"
> shell web        # matches "webmail"
> shell .13        # matches any host ending in .13
```

### profile / pr

Connects to all hosts, gets their SSH banner and hostname, and saves
them as tags and aliases in `conf.json`.

```
> profile
```

After profiling, `list` shows hostnames as aliases:

```
> list
root@10.0.1.11:22 (password changeme, aliases ecom)
root@10.0.1.12:22 (password changeme, aliases webmail)
```

Now you can use `shell ecom` instead of `shell 10.0.1.11`.

### upload / up

Uploads a file to all hosts (or one host).

```
> upload my-script.sh
> upload my-script.sh ecom
```

The file is uploaded to the home directory of the SSH user.

### download / down

Downloads a file or directory from all hosts as tar archives.

```
> download /etc/passwd
> download /var/log ecom
```

Creates a directory per host with the downloaded content.

### add / a

Manually add a host that wasn't found by scan.

```
> add 10.0.1.50 changeme
```

### remove / rm

Remove a host from the inventory.

```
> remove 10.0.1.50
```

### edit / e

Change a host's stored password, alias, or port.

```
> edit ecom password NewP@ss123!
> edit 10.0.1.11 alias ecommerce
> edit ecom port 2222
```

### help / h

Show help for all commands or a specific command.

```
> help
> help rotate
> help script
```

### exit

Exit the Monarch REPL.

```
> exit
```

---

## The Competition Workflow

```
> scan 10.0.1.0/24 changeme         # 1. Find all hosts
> script 00-snapshot.sh              # 2. Forensic baseline (before changes)
> rotate                             # 3. Change ALL passwords
> script 01-harden.sh                # 4. Harden everything
> script 02-firewall.sh              # 5. Apply firewall rules
> script 03-services.sh              # 6. Harden running services
> profile                            # 7. Get hostnames for aliases
> list                               # 8. Review -- you now have a hardened network
```

After stabilizing:

```
> script 04-splunk.sh                # Deploy Splunk forwarders
> script 05-monitor.sh               # Deploy monitoring
```

Ongoing:

```
> script hunt-persistence.sh         # Hunt for backdoors
> script hunt-pii.sh                 # PII compliance scan
> script scan-vulns.sh               # CVE vulnerability scan
> shell ecom                         # SSH into a specific box
```

Security tool deployment (when stable):

```
> script setup-waf.sh                # Deploy ModSecurity WAF on web servers
> script setup-ids.sh                # Deploy Suricata IDS on all hosts
```

After DB password rotation:

```
> script update-cms-creds.sh NewDBPass123    # Update CMS configs
```

Utilities:

```
> script find-ips.sh                 # Find hardcoded IPs in configs
```

Incident response:

```
> script -H ecom ir-triage.sh        # Triage one host
> script -H ecom ir-kill.sh          # Kill attacker on one host
> script -H ecom ir-collect.sh       # Collect evidence from one host
```

---

## conf.json -- The Password Inventory

Monarch saves all host data to `conf.json` in the `monarch/` directory.
This file is your single source of truth for every host's credentials.

```json
{
    "10.0.1.11": {
        "ip": "10.0.1.11",
        "user": "root",
        "password": "xK9!mPq#2rTv",
        "aliases": ["ecom"],
        "open_ports": [22],
        "tags": ["SSH-2.0-OpenSSH_8.9p1 Ubuntu-3"],
        "port": 22
    },
    "10.0.1.12": {
        "ip": "10.0.1.12",
        "user": "root",
        "password": "Lm4@nBz$8wYp",
        "aliases": ["webmail"],
        "open_ports": [22],
        "tags": [],
        "port": 22
    }
}
```

**Important:** This file contains plaintext passwords. It's in `.gitignore`
so it won't be committed. Don't copy it anywhere insecure.

---

## passwords.db -- The Password Pool

Monarch picks passwords from `passwords.db` (a CSV file) during `rotate`.
Each password is used once and removed from the pool.

```csv
id,password
1,xK9!mPq#2rTv_8wYp
2,Lm4@nBz$8wYp_3kQr
3,...
```

The file ships with 50 pre-generated passwords. If you run out (50 rotations
across all hosts), generate more or use `rotate -p "specific_password"`.

---

## Troubleshooting

### "Script X was not found"

Monarch searches the `scripts/` directory relative to where you launched it.
Make sure you're in `/opt/ccdc26/monarch/`:

```bash
cd /opt/ccdc26/monarch
python3 -m monarch
```

### "Authentication failed" after rotate

The password was changed on the host but Monarch couldn't verify it.
The password in `conf.json` may be stale. Check:

```
> list                          # See what Monarch thinks the password is
> edit HOST password ACTUAL_PW  # Fix it manually
> shell HOST                    # Verify you can connect
```

### "No host for alias X"

The host wasn't found. Check spelling or use the IP directly:

```
> list                          # See available hosts and aliases
> shell 10.0.1.11               # Use IP instead of alias
```

### Script output floods the prompt

When a script produces a lot of output, it can interfere with the REPL
display. The script still executed correctly -- just wait for the `>` prompt
to reappear and continue typing.

### Host not found during scan

- Verify the host is on and reachable: `ping <ip>` from the controller
- Verify SSH is running on the host: `nc -zv <ip> 22`
- Try a different password: `scan 10.0.1.0/24 password1 password2`
- Add manually: `add 10.0.1.50 thepassword`

# CCDC26 Defense Toolkit

Hardening, monitoring, and incident response scripts for CCDC 2026. Supports Linux and Windows systems with centralized management via Ansible.

**Competition Day?** See [QUICKREF.md](QUICKREF.md) for credentials, commands, and what each option does.

---

## Prerequisites

Install on ONE machine (your Ansible controller):

```bash
# Fedora/RHEL
sudo dnf install -y git python3-pip sshpass && pip3 install ansible pywinrm

# Ubuntu/Debian
sudo apt install -y git python3-pip sshpass && pip3 install ansible pywinrm
```

### Network Requirements

**IMPORTANT**: For Ansible to manage Windows hosts from Linux, you must configure:

1. **Windows Firewall** (on each Windows host):
   ```powershell
   # Run as Administrator on each Windows machine:
   cd C:\ccdc26\windows-scripts
   .\Setup-WinRM-Ansible.ps1
   ```
   This allows Linux subnet (172.20.242.0/24) to connect via WinRM (port 5985).

2. **Cisco FTD Firewall** (manual configuration required):
   - Allow traffic from Linux subnet (172.20.242.0/24) to Windows subnet (172.20.240.0/24)
   - Required ports: TCP 5985 (WinRM), ICMP (ping)
   - Access FTD via browser: https://172.20.240.200 from Windows hosts

3. **Test connectivity**:
   ```bash
   # From Ansible controller:
   ansible-playbook -i ansible/inventory.ini ansible/test-network-connectivity.yml
   ```

---

## Quick Start

### Option 1: Standalone Deployment (Recommended)

**On any Linux machine, deploy directly:**

```bash
# Clone and deploy in one step
sudo ./deploy-standalone.sh --repo-url https://github.com/YOUR_REPO/ccdc26.git

# Or clone manually, then run
git clone https://github.com/YOUR_REPO/ccdc26.git /opt/ccdc26
cd /opt/ccdc26
sudo ./deploy.sh
```

### Option 2: Ansible Deployment (From Controller)

**On Ansible controller machine:**

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_REPO/ccdc26.git /opt/ccdc26
cd /opt/ccdc26

# 2. Run the toolkit
sudo ./deploy.sh

# 3. Select an option:
#    1) Quick Harden  - Hardens THIS machine (no passwords changed)
#    2) Ansible       - Manage ALL machines remotely (uses git clone)
#    3) Advanced      - Individual tools and scripts
```

---

## What Each Option Does

### Main Menu

| Option | Runs On | What It Does |
|--------|---------|--------------|
| **1) Quick Harden** | This machine | Hardens SSH, firewall, services, permissions, kernel. Does NOT change passwords. |
| **2) Ansible Control Panel** | Other machines via SSH/WinRM | Manage multiple machines at once (passwords, hardening, agents) |
| **3) Advanced Options** | This machine | Individual scripts, SIEM agents, persistence hunting, IR tools |

### Ansible Menu (Option 2)

| Option | What It Does |
|--------|--------------|
| **1) Generate inventory** | Convert CSV to inventory.ini |
| **2) Test connectivity** | Ping all machines to verify Ansible can reach them |
| **3) Password Reset** | Change ALL passwords on ALL machines + kick active sessions |
| **4) Deploy Hardening** | Clone repo to all machines via git (optionally run hardening) |
| **5) Deploy Splunk Forwarders** | Install Splunk forwarder on all machines |
| **7) Gather Facts** | Collect system info from all machines |

---

## How Ansible Works

```
Your Machine (Controller)          Other Machines (Targets)
┌─────────────────────┐            ┌─────────────────┐
│  ./deploy.sh        │    SSH     │  Ubuntu Ecom    │
│  Option 2: Ansible  │───────────>│  172.20.242.30  │
│                     │            └─────────────────┘
│  Reads inventory.ini│    SSH     ┌─────────────────┐
│  Runs playbooks     │───────────>│  Fedora Webmail │
│                     │            │  172.20.242.40  │
└─────────────────────┘            └─────────────────┘
                           WinRM   ┌─────────────────┐
                       ───────────>│  Windows AD/DNS │
                                   │  172.20.240.102 │
                                   └─────────────────┘
```

- **Controller**: The machine where you run `./deploy.sh` and select Ansible options
- **Targets**: All other machines listed in `ansible/inventory.ini`
- Ansible connects via SSH (Linux) or WinRM (Windows) and clones the repository via git
- Each target machine gets a full copy of the repo, allowing standalone script execution

**Network Architecture**:
- Linux Zone: 172.20.242.0/24 (via Palo Alto firewall)
- Windows Zone: 172.20.240.0/24 (via Cisco FTD firewall)
- Inter-zone connectivity requires firewall rules (see Network Requirements above)

**Deployment Method**:
- Ansible uses `git clone` to deploy the repository to each target machine
- This is faster and more reliable than copying individual files
- Each machine can then run scripts locally without Ansible connectivity

---

## Windows Scripts

Windows machines don't use `deploy.sh`. Copy the toolkit to `C:\ccdc26` and run PowerShell scripts directly.

### Quick Start (Windows)

```powershell
# Copy toolkit to C:\ccdc26 (via download)

# Run as Administrator:
cd C:\ccdc26\windows-scripts

# Harden any Windows machine
.\hardening\Full-Harden.ps1 -q

# Harden Domain Controller (AD-specific)
.\hardening\AD-Harden.ps1 -q

# Install Splunk forwarder
.\Install-SplunkForwarder.ps1
```

### Windows Scripts Reference

| Script | What It Does |
|--------|--------------|
| `Full-Harden.ps1` | Patches CVEs (EternalBlue, PrintNightmare, Mimikatz), enables Defender ASR rules, disables dangerous services, removes backdoors |
| `AD-Harden.ps1` | Domain Controller only: Zerologon/noPac patches, Kerberos hardening, privileged group cleanup, LDAP signing |
| `Install-SplunkForwarder.ps1` | Installs Splunk forwarder for log collection |
| `lib/passwords.ps1` | Generates deterministic passwords from username+salt |

See [windows-scripts/README.md](windows-scripts/README.md) for full details.

---

## Repository Structure

```
ccdc26/
├── deploy.sh              # Main entry point (Linux)
├── QUICKREF.md            # Competition quick reference
├── ansible/               # Playbooks for remote management
│   ├── inventory.ini      # Machine IPs and credentials
│   └── changepw_kick.yml  # Password reset playbook
├── linux-scripts/
│   ├── hardening/         # System hardening scripts
│   ├── monitoring/        # Real-time monitoring
│   ├── persistence-hunting/  # Find attacker backdoors
│   └── incident-response/ # IR tools
└── windows-scripts/
    ├── hardening/
    │   ├── Full-Harden.ps1   # Main Windows hardening
    │   ├── AD-Harden.ps1     # Domain Controller hardening
    │   └── lib/              # Shared functions
    └── Install-SplunkForwarder.ps1
```

---

## Key Commands

```bash
# Harden this machine
sudo ./deploy.sh            # Then select 1

# Change all passwords (from Ansible controller)
sudo ./deploy.sh            # Then select 2 -> 3

# Run hardening on all machines
sudo ./deploy.sh            # Then select 2 -> 4 -> 2

# Command line shortcuts
sudo ./deploy.sh --quick    # Quick harden (no menu)
sudo ./deploy.sh --help     # Show help
```

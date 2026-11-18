# CCDC26 Ansible Automation

Ansible playbooks for rapid deployment of the CCDC26 toolkit across multiple hosts.

## Quick Start (Competition Day)

```bash
# 1. Set your team number in inventory.ini (line: team_number=X)

# 2. Test connectivity to all hosts
ansible all -i inventory.ini -m ping

# 3. IMMEDIATELY: Change all passwords
ansible-playbook -i inventory.ini change_all_passwords.yml -e "new_password=YourSecureP@ss123!"

# 4. Deploy Splunk forwarders
ansible-playbook -i inventory.ini deploy_splunk_forwarders.yml

# 5. Deploy hardening to all hosts
ansible-playbook -i inventory.ini deploy_hardening.yml
```

## Directory Structure

```
ansible/
├── setup/
│   └── csv2inv.py              # CSV to inventory converter
├── roles/
│   └── gather/                 # Host fact gathering role
├── inventory.ini               # Competition hosts (PRE-CONFIGURED!)
├── vars.yml                    # Competition variables
├── change_all_passwords.yml    # Mass password reset (RUN FIRST!)
├── changepw_kick.yml           # Password reset + user creation
├── deploy_hardening.yml        # Deploy linux-scripts
├── deploy_splunk_forwarders.yml # Deploy Splunk forwarders
└── gather_facts.yml            # Collect host information
```

## Inventory Setup

### Pre-Configured for RMCCDC 2026

The `inventory.ini` file is **pre-configured** with all competition systems:

**Linux Zone (172.20.242.0/24):**
- `ecom` - Ubuntu E-commerce (HTTP/HTTPS)
- `webmail` - Fedora Webmail (SMTP/POP3)
- `splunk` - Splunk Server (Oracle Linux)
- `ubuntu-wks` - Ubuntu Workstation

**Windows Zone (172.20.240.0/24):**
- `ad-dns` - AD/DNS Server 2019 (DNS)
- `web` - Web Server 2019 (HTTP/HTTPS)
- `ftp` - FTP Server 2022
- `win11-wks` - Windows 11 Workstation

**Network Devices:**
- `paloalto` - Palo Alto Firewall
- `cisco-ftd` - Cisco FTD Firewall
- `vyos` - VyOS Router

### Set Your Team Number

Edit `inventory.ini` and change the team number:

```ini
[all:vars]
team_number=1  # Change to your assigned team number (1-20)
```

## Playbooks

### change_all_passwords.yml (RUN FIRST!)

**Purpose**: Change ALL default passwords across the competition environment

```bash
# Change all passwords to a single secure password
ansible-playbook -i inventory.ini change_all_passwords.yml -e "new_password=YourSecureP@ss123!"
```

This playbook:
- Changes sysadmin/root passwords on all Linux hosts
- Changes administrator password on all Windows hosts
- Changes VyOS router password
- Locks unnecessary Linux accounts
- Reminds you to manually change Palo Alto, Cisco FTD, and Splunk passwords

### changepw_kick.yml

**Purpose**: First-15-minutes critical actions

- Creates competition admin users (ccdcuser1, ccdcuser2)
- Resets ALL user passwords to a prompted value
- Kills all active user sessions

```bash
ansible-playbook -i inventory.ini changepw_kick.yml
# You will be prompted for the new password
```

### deploy_hardening.yml

**Purpose**: Deploy repository via git clone and optionally run hardening scripts

**How it works**: Uses `git clone` to deploy the full repository to each target machine. This is faster and more reliable than copying individual files.

```bash
# Deploy repository to all Linux hosts (git clone)
ansible-playbook -i inventory.ini deploy_hardening.yml

# Deploy and run full hardening
ansible-playbook -i inventory.ini deploy_hardening.yml -e "run_full=true"

# Specify custom repository URL
ansible-playbook -i inventory.ini deploy_hardening.yml -e "repo_url=https://github.com/byui-soc/ccdc26.git"

# Deploy to specific hosts only
ansible-playbook -i inventory.ini deploy_hardening.yml --limit ecom,webmail
```

**What it does**:
1. Installs git if not present
2. Clones/updates repository to `/opt/ccdc26` on each Linux host
3. Makes all scripts executable
4. Optionally runs hardening scripts if `run_full=true`

**Benefits**:
- Faster than copying hundreds of files
- Easy to update: just `git pull` on each host
- Works standalone: hosts can run scripts without Ansible
- Standard tool (git) vs custom file copying logic

### deploy_splunk_forwarders.yml

**Purpose**: Deploy Splunk Universal Forwarders to all hosts

```bash
# Deploy forwarders to all Linux and Windows hosts
ansible-playbook -i inventory.ini deploy_splunk_forwarders.yml
```

Forwarders send logs to the competition Splunk server at 172.20.242.20:9997.

### gather_facts.yml

**Purpose**: Collect reconnaissance data from all hosts

```bash
ansible-playbook -i inventory.ini gather_facts.yml
# Creates JSON files in ./collected_facts/
```

## Variables

Edit `vars.yml` or pass via command line:

```bash
# Override variables
ansible-playbook playbook.yml -e "splunk_server=172.20.242.20" -e "temp_password=NewPass123"
```

Key variables:
- `toolkit_dest`: Where to deploy scripts (default: /opt/ccdc26)
- `repo_url`: Repository URL for git clone (default: from inventory or github)
- `repo_branch`: Branch to clone (default: main)
- `competition_users`: List of users to create
- `splunk_server`: Splunk server IP (default: 172.20.242.20)
- `splunk_port`: Splunk receiving port (default: 9997)

## Requirements

### Ansible Controller

```bash
# Install Ansible
pip3 install ansible

# For Windows hosts
pip3 install pywinrm
```

### Target Hosts

**Linux**: 
- SSH access with sudo
- Git installed (will be installed automatically if missing)
- Python 3 (for Ansible modules)

**Windows**: 
- WinRM enabled (port 5985)
- Git preferred (for git clone), or will use ZIP download fallback

Enable WinRM on Windows:
```powershell
winrm quickconfig
Enable-PSRemoting -Force
```

## Deployment Methods

### Method 1: Ansible (Recommended for Multiple Hosts)

Deploy to all hosts via Ansible:

```bash
ansible-playbook -i inventory.ini deploy_hardening.yml
```

### Method 2: Standalone (When Ansible Fails)

Each host can deploy itself:

```bash
# On any Linux host:
sudo ./deploy-standalone.sh --repo-url https://github.com/byui-soc/ccdc26.git
```

This clones the repo and makes scripts executable. No Ansible needed.

### Method 3: Manual Git Clone

```bash
# On any Linux host:
git clone https://github.com/byui-soc/ccdc26.git /opt/ccdc26
cd /opt/ccdc26/linux-scripts
sudo ./hardening/full-harden.sh
```

## Tips for Competition

1. **Pre-create inventory template** with expected host ranges
2. **Test locally first** with a VM
3. **Run changepw_kick.yml immediately** on competition start
4. **Use --limit** to target specific hosts: `--limit ecom,webmail`
5. **Use -v** for verbose output to debug issues
6. **If Ansible fails**, use `deploy-standalone.sh` on each host directly
7. **Update scripts easily**: After git clone, just `git pull` on each host to update

# CCDC26 Defense Toolkit

Hardening, monitoring, and incident response for CCDC competition environments.

**New to the team?** Read [docs/HOW-THIS-WORKS.md](docs/HOW-THIS-WORKS.md) first.

**Competition day?** Read [docs/START-HERE.md](docs/START-HERE.md).

## Quick Start

### Linux (from any Linux machine)

```bash
sudo git clone https://github.com/byui-soc/ccdc26.git /opt/ccdc26
cd /opt/ccdc26
sudo ./deploy.sh --configure
cd monarch && python3 -m monarch
> scan SUBNET PASSWORD
> script 01-harden.sh
```

### Windows (PowerShell as Admin)

```powershell
cd C:\ccdc26\dovetail\scripts
.\01-blitz.ps1
```

## Architecture

- `monarch/` -- Linux orchestration ([guide](docs/MONARCH-GUIDE.md)) -- Python SSH REPL, dispatches scripts to all hosts
- `dovetail/` -- Windows orchestration ([guide](docs/DOVETAIL-GUIDE.md)) -- PowerShell WinRM dispatcher
- `splunk/` -- SIEM queries and setup
- `docs/` -- Competition playbooks and reference

## Repository

https://github.com/byui-soc/ccdc26

# CCDC Linux Scripts

This directory contains various security and system administration scripts for CCDC (Collegiate Cyber Defense Competition) environments.

## Quick Start

### Background Script Runner

The `run_background.sh` script provides an easy way to run any script in the background with automatic logging.

#### Interactive Menu Mode

Simply run the script without arguments to see an interactive menu of all available scripts:

```bash
./run_background.sh
```

This will display a numbered menu of all scripts in the directory. Select a script by entering its number, and optionally provide additional arguments when prompted.

**Example:**
```
==========================================
  CCDC Background Script Runner
==========================================

Available scripts:

   1) add_powershell.sh
   2) audit_pam_binaries.sh
   3) backup.sh
   4) change_passwords.sh
   5) ...
   0) Exit

==========================================
Select a script to run in background: 1
```

#### Direct Mode

You can also run scripts directly by providing the script path:

```bash
./run_background.sh ./download_tools.sh
./run_background.sh ./enable_logging.sh --verbose
```

#### Features

- **Automatic Logging**: All output (stdout and stderr) is logged to timestamped files
- **PID Tracking**: Process IDs are saved for easy monitoring
- **Log Directory**: Defaults to `/var/log/ccdc/background` (configurable via `LOG_DIR` environment variable)
- **Metadata**: Logs include start time, PID, script path, and arguments

#### Log Files

Log files are stored in `/var/log/ccdc/background/` with the format:
- **Log file**: `<script_name>_<timestamp>.log`
- **PID file**: `<script_name>_<timestamp>.pid`

**Example:**
```
/var/log/ccdc/background/download_tools_20250115_143022.log
/var/log/ccdc/background/download_tools_20250115_143022.pid
```

#### Custom Log Directory

Set a custom log directory using the `LOG_DIR` environment variable:

```bash
LOG_DIR=/tmp/logs ./run_background.sh ./monitor_tcp_connections.sh
```

#### Monitoring Running Scripts

After starting a script, you'll receive:
- The process ID (PID)
- The log file location
- Commands to monitor or stop the process

**Useful commands:**
```bash
# Monitor output in real-time
tail -f /var/log/ccdc/background/<script_name>_<timestamp>.log

# Check if process is still running
kill -0 <PID>

# Stop the process
kill <PID>
```

---

## Available Scripts

### Security Tools

- **`download_tools.sh`** - Downloads and installs security tools (LinPEAS, Chkrootkit, Rkhunter, Lynis, ClamAV, witr)
- **`rkhunter.sh`** - Runs Rootkit Hunter security scan
- **`audit_pam_binaries.sh`** - Audits PAM binaries for security issues
- **`check_pam_config.sh`** - Checks PAM configuration
- **`check_ld_preload.sh`** - Checks for LD_PRELOAD hijacking

### System Configuration

- **`enable_logging.sh`** - Enables comprehensive system logging
- **`configure_firewall.sh`** - Configures firewall rules
- **`set_permissions.sh`** - Sets proper file permissions
- **`manage_process_priorities.sh`** - Manages process priorities

### Monitoring

- **`monitor_tcp_connections.sh`** - Monitors TCP connections
- **`get_inventory.sh`** - Gathers system inventory information

### Backup & Recovery

- **`backup.sh`** - Creates system backups
- **`create_backups.sh`** - Creates backups of critical files
- **`clone_key_directories.sh`** - Clones key directories

### Password Management

- **`change_passwords.sh`** - Changes user passwords
- **`change_passwords_shadow.sh`** - Changes passwords using shadow file

### Other Tools

- **`add_powershell.sh`** - Adds PowerShell to the system
- **`ssh_honeypot.sh`** - Sets up SSH honeypot

---

## Usage Examples

### Running a script in background with menu

```bash
./run_background.sh
# Select script from menu
# Enter arguments if needed
```

### Running a script directly

```bash
./run_background.sh ./download_tools.sh
```

### Running with custom log directory

```bash
LOG_DIR=/var/log/myproject ./run_background.sh ./enable_logging.sh
```

### Running with arguments

```bash
./run_background.sh ./enable_logging.sh --verbose --all
```

---

## Requirements

- Bash 4.0 or higher
- Root privileges (for most scripts)
- Standard Unix utilities (find, date, etc.)

---

## Notes

- Most scripts require root privileges to function properly
- Logs are stored in `/var/log/ccdc/background/` by default
- The background runner automatically makes scripts executable if needed
- All scripts are logged with timestamps for easy tracking

---

## Troubleshooting

### Script not found
If a script is not found, ensure it exists in the same directory as `run_background.sh` and has a `.sh` extension.

### Permission denied
Most scripts require root privileges. Run with `sudo`:
```bash
sudo ./run_background.sh
```

### Log directory creation fails
Ensure you have write permissions to the log directory, or set `LOG_DIR` to a writable location:
```bash
LOG_DIR=/tmp/logs ./run_background.sh ./script.sh
```

---

## Contributing

When adding new scripts:
1. Place them in this directory with a `.sh` extension
2. Make them executable: `chmod +x script_name.sh`
3. They will automatically appear in the `run_background.sh` menu

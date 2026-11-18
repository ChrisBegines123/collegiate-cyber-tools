#!/usr/bin/env python3
"""
CCDC26 Toolkit - CSV to Ansible Inventory Converter

Converts a CSV file with host information to an Ansible inventory INI file.

CSV Format:
    ip,username,password[,group]

Example CSV:
    192.168.1.10,admin,changeme,linux
    192.168.1.20,administrator,Password123,windows
    192.168.1.30,root,toor

Usage:
    python3 csv2inv.py hosts.csv inventory.ini
    python3 csv2inv.py hosts.csv  # outputs to stdout
"""

import sys
import csv
import argparse
from collections import defaultdict


def csv_to_inventory(csv_path: str, output_path: str = None, ssh_port: int = 22):
    """
    Convert CSV to Ansible inventory format.
    
    Args:
        csv_path: Path to input CSV file
        output_path: Path to output INI file (or None for stdout)
        ssh_port: Default SSH port
    """
    hosts = defaultdict(list)
    ungrouped = []
    
    try:
        with open(csv_path, 'r', newline='', encoding='utf-8') as csvfile:
            # Try to detect if there's a header
            sample = csvfile.read(1024)
            csvfile.seek(0)
            has_header = csv.Sniffer().has_header(sample)
            
            reader = csv.reader(csvfile)
            
            if has_header:
                next(reader)  # Skip header row
            
            for row in reader:
                if not row or not row[0].strip():
                    continue
                
                # Parse fields
                ip = row[0].strip()
                username = row[1].strip() if len(row) > 1 else 'root'
                password = row[2].strip() if len(row) > 2 else ''
                group = row[3].strip().lower() if len(row) > 3 else None
                
                # Build host entry
                host_entry = ip
                host_vars = []
                
                host_vars.append(f'ansible_user={username}')
                
                if password:
                    host_vars.append(f'ansible_password={password}')
                    host_vars.append(f'ansible_become_password={password}')
                
                # Detect Windows vs Linux based on username or group
                is_windows = (
                    group == 'windows' or 
                    username.lower() in ['administrator', 'admin'] or
                    'win' in (group or '').lower()
                )
                
                if is_windows:
                    host_vars.append('ansible_connection=winrm')
                    host_vars.append('ansible_winrm_transport=ntlm')
                    host_vars.append('ansible_winrm_server_cert_validation=ignore')
                    host_vars.append('ansible_port=5985')
                else:
                    host_vars.append(f'ansible_port={ssh_port}')
                
                host_line = f"{host_entry} {' '.join(host_vars)}"
                
                if group:
                    hosts[group].append(host_line)
                else:
                    ungrouped.append(host_line)
    
    except FileNotFoundError:
        print(f"Error: File not found: {csv_path}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading CSV: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Generate inventory
    lines = []
    lines.append("# CCDC26 Ansible Inventory")
    lines.append("# Generated from: " + csv_path)
    lines.append("")
    
    # Ungrouped hosts
    if ungrouped:
        lines.append("[all]")
        lines.extend(ungrouped)
        lines.append("")
    
    # Grouped hosts
    for group, group_hosts in sorted(hosts.items()):
        lines.append(f"[{group}]")
        lines.extend(group_hosts)
        lines.append("")
    
    # Create group vars
    if 'linux' in hosts:
        lines.append("[linux:vars]")
        lines.append("ansible_become=yes")
        lines.append("ansible_become_method=sudo")
        lines.append("")
    
    if 'windows' in hosts:
        lines.append("[windows:vars]")
        lines.append("ansible_connection=winrm")
        lines.append("ansible_winrm_transport=ntlm")
        lines.append("")
    
    # All group (combines everything)
    all_groups = list(hosts.keys())
    if all_groups:
        lines.append("[servers:children]")
        for g in sorted(all_groups):
            lines.append(g)
        lines.append("")
    
    inventory_content = '\n'.join(lines)
    
    # Output
    if output_path:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(inventory_content)
        print(f"Inventory written to: {output_path}")
        print(f"Total hosts: {len(ungrouped) + sum(len(h) for h in hosts.values())}")
    else:
        print(inventory_content)


def main():
    parser = argparse.ArgumentParser(
        description='Convert CSV to Ansible inventory',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
CSV Format:
  ip,username,password,group

Examples:
  192.168.1.10,admin,changeme,linux
  192.168.1.20,administrator,Password123,windows
  192.168.1.30,root,toor
        """
    )
    
    parser.add_argument('csv_file', help='Input CSV file')
    parser.add_argument('output_file', nargs='?', help='Output inventory file (default: stdout)')
    parser.add_argument('--port', '-p', type=int, default=22, help='Default SSH port (default: 22)')
    
    args = parser.parse_args()
    
    csv_to_inventory(args.csv_file, args.output_file, args.port)


if __name__ == '__main__':
    main()

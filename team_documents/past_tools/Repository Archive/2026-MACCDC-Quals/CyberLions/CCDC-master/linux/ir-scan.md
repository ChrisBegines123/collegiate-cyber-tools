# First clean system
sudo ./ir_changes.sh --baseline

# Later / compromised system
sudo ./ir_changes.sh --scan

# Scan + remediation
sudo ./ir_changes.sh --scan --remediate

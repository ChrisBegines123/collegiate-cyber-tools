import subprocess

# Create a global variable for findings
findings = []

# Add findings to the variable
def add_finding(severity, message):
    findings.append({
        "severity": severity,
        "message": message
    })

# Check to see if the subprocess is actually running
result = subprocess.run(
    ["systemctl", "is-active", "sshd"],
    capture_output=True,
    text=True
)

if result.stdout.strip() == "active":
    add_finding(
        "PASS",
        "SSH service running"
    )
else:
    add_finding(
        "CRITICAL",
        "SSH service not running"
    )
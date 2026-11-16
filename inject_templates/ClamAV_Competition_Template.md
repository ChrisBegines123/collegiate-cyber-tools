# ClamAV Competition Deployment & Inject Template

> Reusable for NCCDC/CCDC competitions. Replace every `[placeholder]`. **Do not claim a device is protected until verified.**

## Inject details

- Competition: [name]
- Inject ID / title: [ID / title]
- Deadline: [date/time/time zone]
- Team: [team]
- Owner: [name]
- Tool: ClamAV (or approved alternative)
- Requirement: Deploy open-source anti-malware on Linux and Windows devices; submit a business memo listing installed devices with screenshot evidence for each platform (verify the current inject wording).

## Before touching systems

- [ ] Read the inject and scoring rules; confirm which devices count.
- [ ] Inventory OS, IP, credentials source, and critical services.
- [ ] Check internet/DNS, repositories, free disk space, and maintenance restrictions.
- [ ] Protect scored services: avoid heavy full-disk scans or automatic quarantine on production systems.
- [ ] Decide who owns each host and where screenshots/logs will be stored.

## Host tracker

| Host | OS | Internal IP | Owner | Installed | Signatures | Scan | Evidence | Notes |
|---|---|---|---|---|---|---|---|---|
| E-commerce | Rocky Linux 9 | 172.20.240.10 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Email | Ubuntu 22.04 | 172.20.240.15 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Splunk | Debian 12 | 172.20.240.20 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Active Directory | Windows Server 2022 | 172.20.240.100 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| MSSQL | Windows Server 2019 | 172.20.240.120 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Ubuntu workstation | Ubuntu (DHCP) | [discover] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Windows workstation | Windows 11 (DHCP) | [discover] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| Kali workstation | Kali | 172.17.0.2 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |

**Topology note:** The Palo Alto firewall (inside 172.20.240.254) and VyOS router are network appliances, not ordinary Windows/Linux endpoints; include only if the inject explicitly requires them. IPs are example values from the supplied competition topology, not universal defaults. No passwords are stored here.

## Per-host deployment record (duplicate this section)

### [Hostname]

- OS / version: [ ]
- IP: [ ]
- Business service: [ ]
- Installation method / package version: [ ]
- Command/output proving installation: [ ]
- Signature database date / count: [ ]
- Scan target: [small, safe directory]
- Scan command: [ ]
- Scan summary: [scanned files, infected files, errors]
- Services / updater state: [ ]
- Screenshot(s): `evidence/[hostname]-install.png`, `evidence/[hostname]-scan.png`
- Issues and resolution: [ ]
- Verified by / timestamp: [ ]
- [ ] Installed
- [ ] Definitions available and reasonably current
- [ ] Test scan completed (no database errors)
- [ ] Evidence captured

## Evidence checklist

- [ ] Show host identity (`hostname` or `$env:COMPUTERNAME`).
- [ ] Show ClamAV version (`clamscan --version` or `clamscan.exe --version`).
- [ ] Show scan summary with **Known viruses > 0** and an actual file count.
- [ ] Record scan errors; zero infections alone does **not** prove a successful scan.
- [ ] Capture at least one Linux and one Windows device per inject wording; capture more when time permits.
- [ ] Name screenshots consistently and attach/embed them in the memo.
- [ ] List **only successfully completed devices** in the final memo.

## Copy-ready business memorandum

**To:** [Competition Management / Inject Reviewers]  
**From:** [Team Name / Number]  
**Date:** [Date]  
**Subject:** [Inject ID] – Implementation of Anti-Malware Tools on End Devices

### Purpose

This memorandum documents the deployment and verification of open-source anti-malware tooling on the Linux and Windows systems within the competition environment, in response to [inject ID].

### Implementation

The team selected ClamAV for on-demand malware detection on supported endpoints. On the devices listed below, the team installed the software, prepared its signature database, and executed verification scans. [Describe any platform-specific alternatives or limitations.] Installation alone does not imply real-time protection.

### Verified devices

| Device | Operating system | Anti-malware tool | Verification / evidence |
|---|---|---|---|
| [Device] | [OS] | [Tool/version] | [Screenshot / log] |

### Verification and evidence

[Describe the command used, scanned file count, signature availability, infected file count, and any errors.]

- **Figure 1:** [Linux host] — version and successful scan summary. `![Linux evidence](evidence/linux-scan.png)`
- **Figure 2:** [Windows host] — version and successful scan summary. `![Windows evidence](evidence/windows-scan.png)`
- **Additional figures:** [If available]

### Operational considerations

Scans were restricted to [paths] to avoid disrupting scored applications. [Document any ongoing update schedule, exclusions, or unresolved issues accurately.]

### Conclusion

ClamAV was successfully deployed and verified on the devices listed above. [State any incomplete hosts explicitly rather than claiming universal coverage.]

Respectfully submitted,  
[Team]

## Submission gate

- [ ] All claims match screenshots and command output.
- [ ] The memo lists actual devices, not an unverified target inventory.
- [ ] At least one screenshot for each required platform.
- [ ] Screenshots are embedded or attached (relative Markdown links need accompanying image files).
- [ ] Team number is consistent in heading and signature.
- [ ] Submit in the required format before deadline.

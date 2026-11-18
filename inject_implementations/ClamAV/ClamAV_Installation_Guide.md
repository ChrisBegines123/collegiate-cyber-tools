# ClamAV Installation & Verification — NCCDC Quick Reference

> Applies to the example topology: Rocky Linux 9 e-commerce, Ubuntu 22.04 email, Debian 12 Splunk, Ubuntu workstation, Kali workstation, Windows Server 2022 AD, Windows Server 2019 MSSQL, Windows 11 workstation. Run commands on the **corresponding host** with administrator/root rights. Versions and package availability may differ in future competitions.

## FASTEST COMPETITION PROOF — DO THIS FIRST

**Goal:** prove the scanner can scan **one small file**. Do **not** scan entire drives, `/`, mailboxes, Splunk indexes, AD databases, or SQL databases. Once installed and signatures are present, these commands are sufficient for a quick screenshot.

| Competition system | Fastest scan command |
|---|---|
| Rocky Linux 9 — E-commerce | `clamscan /etc/hostname` |
| Ubuntu 22.04 — Email | `clamscan /etc/hostname` |
| Debian 12 — Splunk | `clamscan /etc/hostname` |
| Ubuntu — Workstation | `clamscan /etc/hostname` |
| Kali — Workstation | `clamscan /etc/hostname` |
| Windows Server 2022 — AD | `& "C:\Program Files\ClamAV\clamscan.exe" --database="C:\Program Files\ClamAV\database" C:\Windows\win.ini` |
| Windows Server 2019 — MSSQL | Same Windows command |
| Windows 11 — Workstation | Same Windows command |

**Screenshot proof:** show the command and `SCAN SUMMARY` with `Known viruses` **greater than 0**, `Scanned files: 1`, `Infected files: 0`, and **no database or scan errors**. `clamscan --version` alone is not sufficient. If `win.ini` does not exist, use the two-line Windows fallback below. No need to scan more than one file for a basic functionality check.

**Windows fallback (PowerShell):**

```powershell
'Safe test file' | Set-Content "$env:TEMP\clamav-test.txt"
& 'C:\Program Files\ClamAV\clamscan.exe' --database='C:\Program Files\ClamAV\database' "$env:TEMP\clamav-test.txt"
```

**If signatures are missing:** On Linux, use the `freshclam` instructions under your distribution below. On Windows, follow the Windows signature configuration below. An error or `Known viruses: 0` is **not** proof of a working malware scanner.

---

## Golden rules

1. Install from the OS package manager on Linux. **Do not `git clone` the ClamAV source repository just to install the scanner.**
2. `clamscan --version` proves the binary is present, **not** that the signature database works.
3. Run a small scan first; confirm `Known viruses` is greater than zero and `Scanned files` is greater than zero.
4. A `clamscan` exit code of **0** means no infection found, **1** means infected files found, and **2** means an error occurred. Never treat an error as a clean scan.
5. Avoid recursive scans of `/`, databases, mail spools, or AD/Splunk/MSSQL live data under competition time pressure. Do not automatically remove/quarantine scored files.
6. ClamAV on-demand scanning is **not** automatic real-time protection. `clamav-daemon`/`clamd` does not by itself enable on-access scanning.

## 1. Rocky Linux 9 — e-commerce server (example 172.20.240.10)

```bash
sudo dnf install -y epel-release
sudo dnf install -y clamav clamav-freshclam
clamscan --version
```

If EPEL is unavailable, check enabled repositories and outbound DNS/network policy rather than compiling from source under time pressure. Package naming varies by repository: `dnf search clamav` and `dnf provides '*/freshclam'` can identify available packages.

Update signatures (choose one update method; don't run `freshclam` concurrently with an active updater):

```bash
sudo freshclam
```

If the command reports a lock held by an updater, let that updater finish and check the database instead. Then scan a small known directory:

```bash
clamscan /etc/hostname
```

## 2. Ubuntu 22.04 server/workstation — email server and Ubuntu workstation

```bash
sudo apt update
sudo apt install -y clamav clamav-freshclam
clamscan --version
```

Ubuntu may run a `clamav-freshclam` service automatically. To force a one-time refresh **only when necessary**:

```bash
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl start clamav-freshclam
```

Verify without scanning live mail data:

```bash
clamscan /etc/hostname
systemctl status clamav-freshclam --no-pager
```

Optional daemon for additional integrations (not required for manual `clamscan`):

```bash
sudo apt install -y clamav-daemon
sudo systemctl enable --now clamav-daemon
```

## 3. Debian 12 — Splunk server (example 172.20.240.20)

```bash
sudo apt update
sudo apt install -y clamav clamav-freshclam
clamscan --version
clamscan /etc/hostname
```

If definitions are missing, use the Ubuntu one-time `freshclam` sequence above. **Do not scan `/opt/splunk` recursively during an inject without considering Splunk performance.**

## 4. Kali Linux workstation (example 172.17.0.2)

```bash
sudo apt update
sudo apt install -y clamav clamav-freshclam
clamscan --version
clamscan /etc/hostname
```

If definitions are missing, use the same stop → `sudo freshclam` → start sequence as Ubuntu. Kali is Debian-based, but package and service state may differ.

## 5. Windows Server 2019/2022 and Windows 11

**Hosts:** MSSQL Server 2019, AD Server 2022, Windows 11 workstation. Use an elevated PowerShell terminal.

### Download and install

1. Open the official ClamAV downloads page: https://www.clamav.net/downloads
2. Download the current **Windows x64 MSI** from the official project/release links, if offered. Do not assume an old filename/version will remain available.
3. Install the MSI from the folder where it was downloaded (replace the filename):

```powershell
Start-Process msiexec.exe -Verb RunAs -Wait -ArgumentList '/i "C:\Users\Administrator\Downloads\clamav-<version>.win.x64.msi"'
```

Or run the MSI interactively. The installation directory is commonly `C:\Program Files\ClamAV`; check it before continuing.

### Configure signature downloads

The Windows distribution may provide sample config files rather than active ones. First inspect the installation:

```powershell
$clam = 'C:\Program Files\ClamAV'
Get-ChildItem $clam
& "$clam\clamscan.exe" --version
```

Create a writable database directory and prepare `freshclam.conf` if an example exists:

```powershell
New-Item -ItemType Directory -Force "$clam\database" | Out-Null
Copy-Item "$clam\conf_examples\freshclam.conf.sample" "$clam\freshclam.conf"
notepad "$clam\freshclam.conf"
```

**If that sample path does not exist**, locate it with `Get-ChildItem $clam -Recurse -Filter '*freshclam*'`, or use the official config example matching the installed release. In `freshclam.conf`, remove/comment the line `Example`, set `DatabaseDirectory C:\Program Files\ClamAV\database`, and keep the official update mirror settings. Some builds require different syntax or permissions; follow the installed example and `freshclam.exe --help`.

Run the update explicitly with that configuration:

```powershell
& "$clam\freshclam.exe" --config-file="$clam\freshclam.conf"
```

If the database directory is not writable, run PowerShell as Administrator and check folder permissions. If the updater fails, **do not report a successful scan**. Official instructions: https://docs.clamav.net/manual/Installing.html

### Verify a real scan

```powershell
& "$clam\clamscan.exe" --database="$clam\database" C:\Windows\win.ini
```

If `win.ini` is missing, create a harmless test file and scan that instead:

```powershell
'Safe ClamAV test file' | Set-Content "$env:TEMP\clamav-test.txt"
& "$clam\clamscan.exe" --database="$clam\database" --infected --summary "$env:TEMP\clamav-test.txt"
```

The scan summary should show **Known viruses > 0** and at least one scanned file. A successful version output alone is insufficient. Windows ClamAV installs do **not** automatically provide the same managed protection as Microsoft Defender; avoid disabling Defender or changing scored service policies just to satisfy the inject.

## 6. Quick verification and evidence

### Linux

```bash
hostname
clamscan --version
clamscan /etc/hostname
echo "Scan exit code: $?"
```

Optional non-destructive test of detection using the industry-standard EICAR test file **only if competition rules allow**. Never use real malware for this check. Save screenshot of host name, version, signature count, scan summary, and errors.

### Windows (PowerShell)

```powershell
$env:COMPUTERNAME
& 'C:\Program Files\ClamAV\clamscan.exe' --version
& 'C:\Program Files\ClamAV\clamscan.exe' --database='C:\Program Files\ClamAV\database' C:\Windows\win.ini
"Scan exit code: $LASTEXITCODE"
```

For Windows hosts, also screenshot the actual `Known viruses` count. If it says zero or `No such file or directory ... database`, the scan is **not verified**.

## 7. Troubleshooting table

| Symptom | Likely issue | Fast action |
|---|---|---|
| `clamscan: command not found` | Not installed / PATH | Install package; on Windows use full `.exe` path |
| `Known viruses: 0` | No usable signature DB | Run/repair `freshclam`; inspect database path |
| `LibClamAV Error: ... database` | DB missing, invalid or inaccessible | Check configured `DatabaseDirectory`, permissions, and update logs |
| `freshclam` lock / resource temporarily unavailable | Updater already running | Don't run a second instance; inspect service and wait |
| `freshclam` permission denied in `/var/log/clamav` | Incorrect user/ownership or competing service | Use packaged service; inspect `journalctl -u clamav-freshclam` and log ownership |
| Update DNS/network errors | Resolver, firewall, proxy, mirror | Check DNS and HTTPS access; do not weaken competition firewall blindly |
| `Access denied` on files | Scanner lacks access | Use an authorized readable test file; avoid assuming skipped files were scanned |
| `clamscan` returns 1 | Infection detected | Investigate safely; do not delete critical scored files automatically |
| `clamscan` returns 2 | Scan error | Fix and rerun; do not count as successful verification |
| Scan too slow | Large directory or live service data | Stop the scan and use a small test file for evidence |

## 8. Host coverage checklist

- [ ] Rocky Linux 9 e-commerce — install, definitions, scan, screenshot
- [ ] Ubuntu 22.04 email — install, definitions, scan, screenshot
- [ ] Debian 12 Splunk — install, definitions, scan, screenshot
- [ ] Ubuntu workstation — install, definitions, scan, screenshot
- [ ] Kali workstation — install, definitions, scan, screenshot
- [ ] Windows Server 2022 AD — install, definitions, scan, screenshot
- [ ] Windows Server 2019 MSSQL — install, definitions, scan, screenshot
- [ ] Windows 11 workstation — install, definitions, scan, screenshot

## 9. Submission reminder

The provided SRVA07A inject requests a **business memo** documenting successful deployment on Linux and Windows, screenshots of implementation on one device per platform, and a list of every installed device. Do not claim full coverage based solely on installing a package or getting a version number. Use `ClamAV_Competition_Template.md` for the deliverable.

## References

- Competition inject: `SRVA07A_-_Implement_Anti-malware_Tool_on_End_Devices.pdf` (supplied)
- Previous team memo and screenshots: `clamAV.pdf` (supplied; some screenshots document errors rather than completed verification)
- ClamAV documentation: https://docs.clamav.net/
- ClamAV downloads: https://www.clamav.net/downloads

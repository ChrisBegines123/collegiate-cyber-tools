# Splunk Technology Add-ons (TAs)

Pre-bundle these TAs in this directory **before competition day** so they can be
deployed to an air-gapped competition network without internet access.

Technology Add-ons provide field extraction and CIM mapping so Splunk can
properly parse log data from forwarders.

## Required TAs

Download from [Splunkbase](https://splunkbase.splunk.com/) (free account required):

| TA File | Splunkbase Link | Deploy To |
|---------|----------------|-----------|
| `splunk-add-on-for-microsoft-windows_*.tgz` | [TA-windows](https://splunkbase.splunk.com/app/742) | Server + Windows forwarders |
| `splunk-add-on-for-microsoft-sysmon_*.tgz` | [TA-sysmon](https://splunkbase.splunk.com/app/5709) | Server + Windows forwarders |
| `splunk-add-on-for-microsoft-iis_*.tgz` | [TA-iis](https://splunkbase.splunk.com/app/3185) | Server |
| `splunk-add-on-for-apache-web-server_*.tgz` | [TA-apache](https://splunkbase.splunk.com/app/3186) | Server + Linux forwarders |
| `splunk-add-on-for-mysql_*.tgz` | [TA-mysql](https://splunkbase.splunk.com/app/6154) | Server |
| `splunk-add-on-for-palo-alto-networks_*.tgz` | [TA-paloalto](https://splunkbase.splunk.com/app/2757) | Server |

## How to download

1. Go to each Splunkbase link above
2. Click "Download" (sign in with free Splunk account)
3. Save the `.tgz` file to this directory
4. For Windows forwarders, also keep `.zip` versions if available

## Deployment

TAs in this directory are automatically deployed by:
- `ansible/deploy_splunk_forwarders.yml` (if files are present)
- `linux-scripts/tools/splunk-server.sh` (install on server via CLI)

### Manual install on Splunk server

```bash
/opt/splunk/bin/splunk install app /path/to/ta-file.tgz -auth admin:password
/opt/splunk/bin/splunk restart
```

### Manual install on forwarder

```bash
tar -xzf ta-file.tgz -C /opt/splunkforwarder/etc/apps/
```

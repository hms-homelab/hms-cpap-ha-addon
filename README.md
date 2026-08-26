# CpapDash add-on repository for Home Assistant

Add this repository to Home Assistant to install CpapDash as an app:

**Settings → Apps → ⋮ → Repositories**, then add

```
https://github.com/hms-homelab/hms-cpap-ha-addon
```

## Add-ons in this repository

### [CpapDash](./cpapdash)

Reads your CPAP machine's SD card over WiFi and keeps the whole night on your own
hardware: charts, events, oximetry, PDF reports and native Home Assistant
sensors, with no cloud account anywhere in the path.

Supported architectures: `amd64`, `aarch64`.

## Why this is not on HACS

HACS distributes integrations, Lovelace cards and themes. It does not host
add-ons. A repository URL added under Settings → Apps is the only way an add-on
reaches a Home Assistant install, which is what this repository is for.

CpapDash needs no custom integration: it publishes MQTT discovery, so Home
Assistant creates the entities itself.

## Source

The service lives at [hms-homelab/hms-cpap](https://github.com/hms-homelab/hms-cpap).
This repository is packaging only.

# CpapDash

Reads your CPAP machine's SD card over WiFi and keeps the whole night on your own
hardware: charts, events, oximetry, PDF reports, and native Home Assistant
sensors. No cloud account anywhere in the path.

## What you need

A way for the add-on to reach the card. CpapDash supports three:

| Source | What it is |
|---|---|
| `ezshare` | An ez Share WiFi SD card, or the CpapDash Push kit, serving the card over HTTP |
| `fysetc` | A Fysetc SD WiFi Pro, which connects out to CpapDash rather than being polled |
| `local` | A directory Home Assistant can already see, e.g. a mounted network share |

All three are network paths, so the add-on needs no USB device mapping and no
privileged mode.

## Installation

1. Settings → Apps → ⋮ → Repositories, and add
   `https://github.com/hms-homelab/hms-cpap-ha-addon`
2. Install **CpapDash** from the store.
3. Set `source` and its address in Configuration.
4. Start, then open the Web UI.

## Options

**`source`** (`ezshare`, `local`, `fysetc`) Where the nights come from.

**`ezshare_url`** The card's address, e.g. `http://192.168.4.1`. Only used when
`source` is `ezshare`.

**`local_dir`** The card root, meaning the directory that holds both `STR.edf`
and `DATALOG`. Only used when `source` is `local`. Because the add-on maps Home
Assistant's `share` folder, a path like `/share/cpap` works once you have the
card contents there.

**`burst_interval`** Seconds between sweeps. 300 is a sensible default; the
machine writes once a night, so polling harder gains nothing.

**`database`** `sqlite` (default), `postgresql` or `mysql`. SQLite needs no
server and stores the database alongside the add-on's configuration, so it
survives updates. The other two need `db_host` and friends filled in; if
`db_host` is left empty the add-on falls back to SQLite rather than refusing to
start.

**`log_level`** Reserved for future use.

## Home Assistant entities

If you have an MQTT broker, the add-on finds it by itself. There is nothing to
type: `services: mqtt:want` means the Supervisor hands over the host, port and
credentials, and CpapDash publishes MQTT discovery for everything it knows.

You get sensors for the nightly AHI and its breakdown, usage, leak, mask
pressure, SpO2, the CpapDash index, supplies and cleaning schedules, plus live
session state and sleep stage while a session is running.

With no broker configured, the add-on still works. It simply publishes nothing,
and everything stays in the web UI.

## Ingress

The UI runs through Ingress, so there is no port to open and no second password.
Direct access on port 8893 is available if you want the API from another machine:
map it in the add-on's Network panel.

## Data

The generated configuration and the SQLite database live in the add-on's own
`/data` directory, which persists across add-on updates. Card files are archived
there too. Nothing you need to edit by hand lives outside the Configuration tab.

## This is not a medical device

CpapDash shows you what your machine recorded. It does not diagnose anything, it
does not replace your clinician, and no number it displays should be used to
change your therapy on your own.

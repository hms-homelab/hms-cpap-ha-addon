# Changelog

## 5.5.4

STR.edf reaches the archive a minute after mask-off, not an hour.

### Fixed
- **The STR is read on the burst a session closes.** On an ez Share (or any
  card read over a transport), STR.edf was fetched only once the night had
  been quiet for an hour, so the archive's `STR.edf`, the dashboard's STR
  figures and the STR state on MQTT trailed mask-off by an hour. The machine
  writes STR.edf at mask-off, so the burst that sees a session close now reads
  it, once however many sessions closed. An OSCAR import from the archive no
  longer has to wait the hour for the night's settings. The hour of quiet
  still decides when the night is announced (outcome, SleepHQ export, range
  summaries) and reads the STR again first. A local folder is unchanged: it
  already reads its STR every burst.

## 5.5.3

An AirSense 11 whose card cannot be read is read over its own Bluetooth.

### Added
- **AirSense 11 over Bluetooth, through the bridge** (`airsense11` in
  `config.json`, off by default). Some AirSense 11 machines cannot power a
  WiFi SD card in their slot, so there is nothing to collect from the card.
  The bridge pairs with the machine over the machine's own Bluetooth (once,
  with the code on its screen, on the bridge's page) and answers the
  machine's daily summary at `GET /airsense11/summary?from=YYYY-MM-DD`: one
  record per therapy day, the figures the machine writes to `STR.edf`.
  hms-cpap pulls it every `pull_hours` (default 6) and stores the days with
  usage exactly as STR days (`saveSTRDailyRecords`, minus removed nights), so
  the dashboard, the trends and the reports show them. The first pull asks
  for everything the machine keeps; each later one from two days before the
  newest day it has. No waveforms and no event list come this way. Needs
  cpapdash-parser 8.7.0 (`AirSense11SummaryParser`).

## 5.5.2

Direct Bluetooth mode tells the two rings apart again.

### Fixed
- **Direct Bluetooth mode took an original O2Ring for an O2Ring-S** (since
  5.5.1). The O2Ring-S was also recognised by its manufacturer ID, which the
  original O2Ring advertises too, so an original ring went down the O2Ring-S
  path and was never read. The O2Ring-S is now recognised by its name or its
  service only.

## 5.5.1

Direct Bluetooth mode finds the O2Ring-S (experimental).

### Added
- **Direct Bluetooth mode talks to the O2Ring-S, EXPERIMENTAL.** With
  `WITH_BLE`, hms-cpap reaches the ring itself over BlueZ instead of through a
  bridge. Until now it only knew the original O2Ring family's protocol and
  never found an O2Ring-S. It now recognises the O2Ring-S by its `S8-AW` /
  `T8520_` name, its manufacturer ID or its service, and speaks its own
  protocol: live SpO2 and heart rate, the file list (as `<YYYYMMDDhhmmss>.o2s`)
  and downloads, resuming a download after a reconnect when the ring caps one
  connection's transfer. The ring's clock is left as its app set it. Not yet
  confirmed against a real O2Ring-S; the label comes off once it has been.

## 5.5.0

The O2Ring-S's recordings are read (experimental).

### Added
- **O2Ring-S (model T8520) recordings, EXPERIMENTAL.** Built from the ring's
  published protocol and synthetic recordings, not yet confirmed against a
  real O2Ring-S night; the label comes off once one has been. The O2Ring-S
  does not write `.vld` files: its recordings are one sample a second with the
  start time in the file name. hms-cpap now reads them wherever it reads a ring file: pulled
  from a bridge's `/o2ring/files`, found in a folder beside the card (named
  `.o2s`, or the ring's own bare `YYYYMMDDhhmmss` name, recognised by its
  header), and uploaded by hand. A recording the ring is still writing is
  left until it is finished, then read. Needs cpapdash-parser 8.6.0.

## 5.4.15

The Raspberry Pi zip is built the way 32-bit Raspberry Pi OS is.

### Fixed
- **On a Raspberry Pi, hms-cpap could crash parsing a night, and aborted on
  every stop.** 32-bit Raspberry Pi OS is built for ARMv6, and its C++ library
  counts shared pointers with a lock; the zip was built with Debian's ARMv7
  headers, which count them atomically. Where a shared pointer crossed between
  hms-cpap and the system's libraries it was counted two ways, and memory was
  freed twice: "corrupted double-linked list" in the log while a night was
  being read, and an abort (exit 6/ABRT) each time the service stopped. Every
  Pi zip since the first had it.

### Changed
- The Pi zip is now cross-compiled against Raspberry Pi OS's own libraries and
  C++ headers, and the release refuses to ship one built against any other
  headers. Before it ships, the binary runs its preflight and reads a night
  under emulation with memory checking on. The zip's contents and install
  steps are unchanged; an install through Settings > Update or `install.sh`
  replaces the binary as before.
- `cmake/arm-toolchain.cmake` (cross-builds for a Pi) uses the sysroot's C++
  headers too, and takes the sysroot from `RASPBIAN_SYSROOT`.

## 5.4.14

The shared library moves to hms-shared v1.6.18.

### Fixed
- **The MQTT client could hang for good on a subscribe.** It held its own lock
  across a subscribe while the incoming-message thread held the client
  library's lock to deliver into that same lock, so a subscribe made while
  retained messages were still arriving froze both: no more publishes, no more
  commands, until a restart. Home Assistant's retained `online` status is
  exactly such a message. Fixed in hms-shared v1.6.18.

### Changed
- The hms-shared pin moves from v1.6.10 to v1.6.18. Also in that range: the
  database pool reconnects missing connections on its own, and the Ollama
  agent sends tool-call arguments in the form Ollama expects on every round.

## 5.4.13

Every install its own device id (#33).

### Changed
- **A new install generates its own device id**, `cpapdash_` and eight hex
  characters, instead of a fixed default. Two installs on one broker kept the
  same default and published under the same topics, fighting over one Home
  Assistant device.
- **An install on an old fixed default is moved to a generated id, once.** If
  your id is `cpap_resmed_23243570851` (the default until 5.4.11) or `cpapdash`
  (5.4.12), the first start of this version moves every night to a new
  `cpapdash_...` id in one transaction and removes the old Home Assistant
  device. **Home Assistant then shows a new device with new entities:
  dashboards, automations and history graphs built on the old ones must be
  pointed at the new ones, and their history does not carry over.** To keep
  your id, add `"device_id_pinned": true` to `config.json` before upgrading.
  The Home Assistant add-on pins any id typed into its `device_id` option, and
  leaves `cpapdash_addon` as it is.

## 5.4.12

Home Assistant shows the machine you own (#33).

### Fixed
- **Every machine said it was an AirSense 10.** The Home Assistant device card
  carried a fixed model, firmware and manufacturer whatever wrote the card. They
  now come from the card: a ResMed's `Identification.json` (11 series) or
  `Identification.tgt`, and for a Prisma, an S.Box or a Luna what its parser
  read. So an AirCurve 11 VAuto shows as "AirCurve 11 VAuto", with its serial
  and software version. A field the card does not give is shown blank, never
  filled in, which also clears the "AirSense 10" an older release put on an
  existing device. A ResMed is corrected at startup; a Prisma, S.Box or Luna
  with its next session. Existing entity ids do not change.
- **A new install's default device id was a real machine's serial**, and its
  default name "ResMed AirSense 10". A new install now defaults to `cpapdash`
  and "CPAP". An existing install keeps its id and name, including one whose
  `config.json` never set them.

### Changed
- The cpapdash-parser pin moves to v8.5.4, which carries each machine's
  product name and firmware on the parsed session.

## 5.4.11

BMC / React Health Luna cards (beta).

### Added
- **A BMC / React Health Luna card**, from a local folder (format "BMC / React
  Health Luna (beta)" in Setup and Settings) or by uploading a zip of the card.
  Every session on the card not yet stored is imported; the newest is read
  again while the machine is still writing it. Sessions, the machine's own
  obstructive and clear-airway apneas, the AHI, leak, respiratory rate and I:E
  per minute. On a bi-level Luna, IPAP, EPAP and pressure support are
  published as on an AirCurve, and `avg_pressure` is not. Not over an ez Share.
  Beta: it is built on one card, and flow, tidal volume and several of the
  machine's record types are not read yet.
- The cpapdash-parser pin moves to v8.5.3, which brings the BMC parser and only
  that.

## 5.4.10

A re-parse now reaches Home Assistant (#33).

### Fixed
- **A re-parse changed the database and Home Assistant never heard of it.**
  A backfill (`POST /api/backfill`, the re-parse in Settings, or an uploaded
  card) re-read the nights and stored the new numbers, but published nothing,
  so every sensor kept its old value until the next new night. When a
  re-parse saves sessions, the newest night and the STR's daily sensors are
  now published again within one burst cycle. It does not regenerate the AI
  summary.
- **An AirCurve upgraded from before 5.2.8 showed IPAP, EPAP and pressure
  support as unknown.** The sensors were announced, but the nights stored
  before 5.2.8 hold no IPAP channel, and nothing re-reads a stored night on
  upgrade. **If your bi-level machine has been on hms-cpap since before
  5.2.8, run a re-parse once** (Settings, or `POST /api/backfill`): the three
  sensors fill as soon as it finishes.

### Changed
- **No `avg_pressure` on a bi-level.** On an AirCurve that sensor is the mean
  of a pressure waveform swinging between EPAP and IPAP (6.4 cmH2O on a
  5.3/9.3 night), a pressure the patient never receives. Use `hist_ipap` and
  `hist_epap` instead. The entity is removed when the machine is seen to be a
  bi-level and comes back if the machine changes. Every other machine still
  publishes it.

## 5.4.9

A failed download no longer damages the archive (since 5.4.4).

### Fixed
- **An error reply was saved into the file being downloaded.** Since 5.4.4 a
  transfer that stops part way keeps what landed and the next burst resumes
  from it. But when an hms-mm bridge could not fetch a file from its card, it
  answered 502 with a short error text, and that text was appended to the
  partial file and kept as if it were data. Every failed burst grew every
  file by the error text, and the next burst resumed past it: a night that
  began during the failure held nothing but error text, and a finished small
  file grew far past its real end, so later bursts asked the card for ranges
  past the end of the file, which an ezShare card does not survive well. An
  error reply now leaves the file exactly as it was.
- **Copies damaged that way repair themselves.** Before resuming a BRP, PLD
  or SAD file, a copy longer than the card lists the file, or one that does
  not open with an EDF header, is discarded and fetched again from the start.
  A night already stored from such a copy (it shows next to no usage while
  its STR row shows the real hours) counts as not archived, so it is fetched
  and parsed again on the next burst, with nothing to delete by hand.
- **The log says why a download failed.** `HTTP 502 for <file>` is now
  followed by the reply's own text, which on an hms-mm bridge is the reason
  its miner gave (from miner 1.0.3, the card's HTTP status or the network
  error).
- **MySQL: the weekly and monthly summaries found no nights since 5.4.8.**
  The query that reads a range of nights grouped by one expression and
  selected another, which MySQL 8's default `ONLY_FULL_GROUP_BY` refuses, and
  the refusal was not checked, so it came back as "no nights". It now groups
  by the selected night, and both night queries log MySQL's own error if they
  ever fail.

## 5.4.8

- **A night's events sit on the stretch they happened in, and a night has one
  AHI** everywhere it is shown (CpapDash 5.4.8). Past nights keep their old
  per-session events until they are parsed again.
- **The `fysetc` source is removed**, with CpapDash's own removal of it. Port
  9000, its inbound listener, is no longer published, and the add-on no longer
  writes a `fysetc` block into the configuration. `source` accepts `ezshare`
  and `local` only: an install that saved `fysetc` must choose one of them in
  the Configuration tab before it starts again.

## 5.4.7

### Fixed
- **Setup finds an hms-mm bridge.** The first-run scan only looked for
  CpapDash's own bridge, so a bridge built from the open-source hms-mm never
  showed up. It now finds both.
- **The ezShare Test button really tests.** It never contacted the address:
  any address came back as a failure reading "Connection failed: configured".
  It now asks a bridge for its status, so a bridge passes even when its card
  has no power, and otherwise asks the address for the card's listing. A
  failure shows the real reason.

## 5.4.6

### Fixed
- **PDF reports generate on PostgreSQL again.** Every report on a PostgreSQL
  install failed with "Failed to create report job" and logged nothing.

## 5.4.5

### Fixed
- **A night past the STR charts its own respiration, pressure and leak, not
  zero** (hms-homelab/hms-cpap#38). When a card's STR.edf stopped updating, the
  respiratory trend dropped to zero from that day on, while every session's own
  charts were complete. Respiratory rate, tidal volume, minute ventilation and
  mask pressure's 95th percentile and maximum are now taken from the night's
  own per-minute data, and the STR fills them only where those are missing.

## 5.4.4

### Changed
- **A transfer cut part way keeps what landed.** On a weak link a big file
  could drop part way and was downloaded again from the start on the next
  burst, so it might never finish. The next burst now resumes from where it
  stopped, and a stalled transfer gives up after 30 seconds instead of
  holding the burst for five minutes.

## 5.4.3

### Fixed
- **A night is over after an hour of quiet.** A night used to count as
  finished on the first burst that found its files unchanged, which can be a
  one-minute pause in the middle of the night, and that is when SleepHQ, the
  STR and the summaries were sent. A night is now over after 60 minutes with
  nothing new on the card, and its results are published then, whether or not
  the STR has the night yet.

## 5.4.2

No change you can see. Code nothing ran was removed, and the parser is pinned
to 2026.8.5.

## 5.4.1

### Fixed
- **The Download button on a PDF report failed for Home Assistant add-on
  users** (hms-homelab/hms-cpap#35). The report itself was fine; the link
  pointed at Home Assistant's own root rather than at CpapDash, so it answered
  404. It now points where the app is actually served from, and works the same
  as before for every other install.
- **A report's two timestamps disagreed by your time zone.** The time a report
  was requested was written in local time and the time it finished in UTC, so
  the same instant appeared twice, hours apart. Both are now the machine's own
  clock, on every database.

## 5.4.0

The app updates itself (SDD-041). It checks GitHub for a newer release once a
day, says so in one line on the dashboard, and installs it in one click. If the
new version does not come up, the old one is put back.

**This is the last version you install by hand.** Versions up to 5.3.0 have no
updater, so install this one the usual way; every release after it shows up in
the dashboard.

### Added
- **Update now, on the dashboard.** When a newer stable release exists, the
  dashboard says which one and offers to install it. Settings, Updates shows the
  version you run, the release notes, Check now, and the outcome of the last
  update.
- **Every download is checked before anything changes.** Each release now
  publishes a manifest with the size and SHA-256 of every file, and the file
  must match it. On macOS the new app must also carry CpapDash's own
  signature. On Windows the check is the checksum; the installer is not
  code-signed yet.
- **A failed update puts the old version back.** The whole install is replaced
  (the app on macOS, the installer on Windows), the new version must start and
  answer as itself within two minutes, and otherwise the previous one is
  restored and Settings says at which step it stopped.
- **Your database is copied before an update.** A SQLite database is backed up
  first. For PostgreSQL and MySQL, Settings says that rolling back any change to
  the data is yours.
- **Install updates automatically**, off by default. When on, an update waits
  until no night is being collected.
- **On a Raspberry Pi**, `install.sh` adds a small root service that applies an
  update from Settings. It downloads and checks the release itself rather than
  trusting a file from your home folder.
- Docker and the Home Assistant add-on update through their image, as before,
  and Settings says so.

### Fixed
- **Changing the Device ID in Settings emptied the sessions list** until a
  restart: nights were stored under the new ID while every page asked for the
  old one (CpapDash ticket 129). The Device ID now takes effect at the restart
  Settings offers, when every part of the app picks it up at once (SDD-042).
- **Some nights from a local folder stayed "live" for good.** A night first
  imported when it was two to five days old was never closed. Every cycle now
  closes a local night once it is five days old, at the end its own data gives
  (SDD-043, ticket 129).
- **"Restart now" under the desktop app stopped the service** instead of
  restarting it. The service now shuts down cleanly and the app brings it back.

## 5.3.0

One collection cycle for every source (SDD-040). A local folder used to have its
own copy of the collector, and every local defect this month came from the two
copies drifting apart: nights that never closed (5.2.18) and history that was
never read (5.2.19). There is now one.

### Changed
- **A local folder is collected by the same cycle as an ez Share card.** It is
  read through the same interface, so a fix to one is a fix to both. Anything
  that only makes sense across a network is skipped for a folder, because the
  folder is already the copy: nothing is downloaded, nothing is mirrored into
  the Archive Directory, and the card's other files are not walked.
- **A night is parsed as a whole night.** A folder that holds one night is read
  where it lies, with no temporary copy, where the local path used to copy every
  night's files on every cycle.

### Fixed
- **A night split across two blocks in one folder could be stored twice.** On
  an ez Share, each block was parsed from the whole folder, so both came back as
  the same merged night and were saved under two start times. Each block is now
  read on its own. It needed a rare shape to happen, but it would have doubled
  that night's events.
- **Switching the source to Local Directory in Settings could stop the app.**
  Found while testing this release in Docker and fixed before it shipped: after
  a switch made while running, the next collection cycle had nothing to read
  from and the process exited. It now picks up the new source straight away.

## 5.2.19

Two users, one card each, and the same sentence in both logs: "Scanning folders
from: …", followed by nothing (hms-homelab/hms-cpap#34, CpapDash ticket 129).

### Fixed
- **Nights older than the newest one already stored were never imported**
  (SDD-038). Collection asks for what is NEWER than the last session it has,
  which is right for a card that grows forward and blind to history that was
  already there: a rebuilt container kept its database and imported exactly one
  night, leaving thirteen on the card, on every cycle, for ever. Each cycle now
  also asks which nights on the card are missing from the database and imports
  them. A local folder catches up in one pass; an ez Share takes the three
  oldest per cycle, because there every folder is a request over the card's
  WiFi and tonight's data comes first. A night that has been removed on purpose
  stays removed, and a folder that holds nothing readable is tried once.
- **A failed query looked exactly like an empty history** (SDD-039). When a
  statement could not run, the page received the same empty answer it gets for
  an install with no nights: a 200 and an empty list. One user watched the
  sessions page go blank with 63 nights sitting in the database and nothing
  anywhere said why. A query that does not run now answers with the database's
  own message instead of silence.
- **Uploading a card could make the whole app stop answering** (SDD-039). The
  import ran on a web thread, so copying a card onto a slow or stalled network
  share held one of only two of them, and the dashboard never replied while a
  spinner turned. The upload is now handed to the worker that already does long
  imports and answers straight away; the page follows it through the progress it
  already polls. The server also takes its thread count from the machine (four
  to eight) rather than the two it had since the web UI was added.

## 5.2.18

Everything here is the Local Directory source, from one report of a first import
against a folder of nights (CpapDash ticket 129, SDD-037).

### Fixed
- **A local import left every night but the newest two reading LIVE, forever.**
  The local source stored a night open and closed it on a later cycle, once its
  files stopped changing, but only the newest night and the one before it are
  ever looked at again, so the rest could never be closed. A local session older
  than 5 days is now closed when it is stored, the way the backfill and the card
  upload already did; newer ones keep the old behaviour, because a local folder
  can be a card still being written.
- **`session_end` said when the import ran, not when the night ended.** It was
  the wall clock, so every night closed in one pass carried one timestamp. An
  imported night now takes the end its own data carries (the parser's, else
  start plus duration) on all three databases. A live ez Share night still uses
  the clock, which is the right answer there: that is when its files stopped.
- **The Data Source picker could not change the source.** Settings edits the
  transport and the format, and the save handler read neither, so the source
  stayed whatever it was and only editing config.json by hand worked. It now
  reads both, derives the source, and applies it on the next cycle without a
  restart.
- **Settings promised an archive a local source never writes.** The Archive
  Directory hint described nights being written there as a card layout, which
  only the ez Share and Fysetc sources do. With a local folder it now says the
  folder is already the card and OSCAR should read it directly. Five languages.

## 5.2.17

### Fixed
- **A removed night could not be brought back from the app** (SDD-036, CpapDash
  ticket 128). Remove night said "Reparse this date to bring it back", but
  Reparse lived on the night's row, which removing it deletes. The sessions
  page now lists removed nights below the table, each with a Restore button
  (the same reparse from the archive), backed by `GET /api/removed-nights`.
- **Uploading a card did nothing for a removed night it held** (SDD-036 D2).
  The ResMed zip copied the files and the backfill then skipped the folder
  without a word; a Sefam or Löwenstein zip counted it as removed. An uploaded
  card now restores the removed nights it holds, and only those, before the
  import, and the upload reply names them in `restored_nights`.

## 5.2.16

No change to CpapDash itself; 5.2.14, 5.2.15 and this one are the same
application. This release carries a working check on the add-on images.

### Fixed
- **The add-on image check failed against images that were correct** (SDD-035).
  It read the architecture through a Go template, and named the field wrongly
  twice: `.Manifest` on 5.2.14, which is only a descriptor, and `.Image.Os` on
  5.2.15, where the field is `OS`. It now dumps the image config as JSON and
  reads it with jq, verified against both published 5.2.15 images before this
  release rather than on the next one.

## 5.2.15

No change to CpapDash itself; 5.2.14's application code and this one's are the
same. The release exists to publish a correct pair of add-on images.

### Fixed
- **The add-on image job published only one architecture** (SDD-035). Its
  check read the architecture from the manifest DESCRIPTOR, which carries only
  a media type, a digest and a size, so it failed against an image that was
  correct; the matrix then cancelled the other architecture before it
  finished. The check now reads the image config, states the platform it
  expects, and additionally proves the published image runs the add-on
  entrypoint rather than the plain service, and one architecture failing no
  longer cancels the other.

## 5.2.14

### Fixed
- **A database whose sessions table has no unique key now repairs itself**
  (SDD-034). 5.2.13 only reported the gap; this release closes it. On the
  first start after updating, an install missing
  `UNIQUE (device_id, session_start)` on `cpap_sessions` keeps one row per
  night, adds the key, and logs what it did. The copy kept is the longest one,
  because a session row only ever grows, so that is the most complete record
  of the night; the shorter copies go, and the metrics, events, breaths,
  vitals and file rows hanging off them go with them. All of that is derived
  from card files still on disk, so a Reparse rebuilds any of it. Nothing runs
  on a database that already has the key, which is every install created by a
  recent build, and nothing runs twice.

## 5.2.13

### Added
- **A database whose sessions table has no unique key now says so** (SDD-034).
  Every backend declares `UNIQUE (device_id, session_start)` on
  `cpap_sessions`, and saving a session relies on it: without it a night that
  is still growing is stored again on every burst instead of being updated, so
  the night appears twice and its hours and events inflate. A table created
  before that declaration has no such key, and nothing added one. Startup now
  checks and logs one line naming how many nights are stored more than once.
  This release only reports it and changes nothing; the repair follows once
  the reports show who has the gap.

## 5.2.12

### Fixed
- **A night of more than one session read as the average of its sessions**
  (#33, SDD-033). A three-minute mask-fit counted as much as a five-hour
  night: on an AirCurve 11 card the published IPAP read 9.40 where the night's
  minutes give 9.31. Every minute-averaged figure of such a night is now the
  mean over its minutes: pressures, leak, breathing rate, tidal volume, minute
  ventilation, timing, flow limitation and snore. A night of one session,
  which is most nights, does not change at all.
- **Such a night's events were the busiest session's, not the night's.** The
  night counted the highest single session per event type, so Home Assistant
  showed an AHI of 1.14 where the dashboard showed 1.36 for the same night.
  They are summed now, and the two agree.
- **A night of more than one session takes the machine's own percentiles.** A
  session's leak percentile cannot be combined with another's: on that card
  the night's true leak 95th is 15.6 L/min, its sessions' are 8.4 and 16.8,
  and no averaging of those finds it. Where the card's STR has the day, its
  leak 50/95, mask pressure and SpO2 are the night's. Löwenstein and Sefam
  cards have no STR and keep ours.
- **On MySQL a Sefam night was published as an AHI** (SDD-024). `index_kind`
  was neither written nor read on that engine, so an apnea-only index went out
  under the name AHI since 2026-09-06. SQLite and PostgreSQL were unaffected.

### Added
- **The 11 series' `TCV` files belong to their session** (#33). An AirCurve 11
  writes `*_TCV.edf` beside each BRP; hms-cpap treated them as loose card
  files and re-downloaded every one of them in full on every burst, about 1 MB
  a night over the ez Share. They are now fetched and resumed like the other
  session files, and reach the archive for OSCAR and SleepHQ.
- **`SA2` and `TCV` join the EDF record-count repair** (parser 2026.8.4): the
  11 series writes them like BRP/PLD/SAD, so a copy pulled mid-recording
  carried the same stale count that 5.2.11 fixed for the others.

## 5.2.11

### Fixed
- **OSCAR showed only a minute or two of flow from the archive** (CpapDash
  support ticket 127, SDD-032). ResMed writes a signal file's EDF record count
  as `-1`, or too low, while it records, and the true count when it finalizes
  the file. hms-cpap resumes BRP/PLD/SAD with Range requests, so the header
  it held was always the mid-recording one, and a header-only change never
  reached the archive. The dashboard and SleepHQ compute the count from the
  file size; OSCAR trusts the field. The archive's BRP/PLD/SAD files now carry
  the real count: repaired as each night is archived and as a zip upload is
  copied, and once at startup for the archive already on disk. A repaired
  file is byte-identical to the card's finalized copy. Only ResMed signal
  files in hms-cpap's own archive are touched, never a card read in place.
  OSCAR keeps a night it already imported: purge it there to re-import it.
- Parser pinned to 2026.8.3 (the record-count repair).

## 5.2.10

### Fixed
- **Ring files kept in a folder per night were never imported** (#32,
  SDD-028 §7). The `.vld` scan read the card root and each folder beside
  DATALOG. A tool that files every night in its own folder
  (`OXYMETRY/20260913/`) was one level too deep, and the scan's line said
  "OXYMETRY/ holds 2 folder(s), which are not searched". It now also reads
  each folder inside those, always, and still skips DATALOG and SETTINGS.

### Added
- **A ring file without the `.vld` extension is recognised by its header**
  (#32). Not every export keeps the extension. A file with no extension in
  those folders is imported when its header is a Wellue ring file's: version
  3, a real date, and its own size at offset 9. Any other file is left alone
  and not read again until it changes. A ring file still being written is
  imported once it is complete.

## 5.2.9

### Added
- **A Sefam or Löwenstein card by upload** (#28, SDD-031). The upload page
  now works out what card it was given from its files, not the install's
  format. A Sefam S.Box/SleepBox or Löwenstein Prisma zip was refused with
  "No DATALOG date folders". Such a card is kept under
  `<data_dir>/uploads/<format>/`, and every session the database does not
  hold yet is imported, older nights included, then the daily summary is
  re-derived. Uploaded history is not published to MQTT and gets no AI
  summary. Checked on a real S.Box card zipped inside a wrapper folder (241
  sessions on 173 nights) and a real Prisma `therapy.pdat` (20 of 20,
  identical to the local-folder path).
- **A Sefam card through an ez Share** (#28, SDD-031). Settings offers the
  Sefam format for ez Share. The card is copied into the archive folder:
  all of it on the first burst, then only the card's last two nights, and a
  file is fetched only when it is new or has changed.

### Fixed
- **A Sefam night added after startup was never read.** The local-folder
  S.Box path scanned the folder once, at startup; it now rescans every burst.

## 5.2.8

### Added
- **A bi-level machine shows its pressures** (#33, SDD-030). On an AirCurve
  (VAuto or S), Home Assistant gets `ipap`, `epap` and `pressure_support` per
  night, and the STR day's prescribed `str_max_ipap`, `str_min_epap`,
  `str_pressure_support` with the daily targets `str_tgt_ipap_95` and
  `str_tgt_epap_95`. The machine's pressure channels were read all along; the
  delivered one (IPAP on a bi-level) was never stored. Nights stored before
  the upgrade gain it on their next reparse. An AirSense gets no new entities,
  and a machine that stops being a bi-level has them removed. Checked on a real
  AirCurve 11 VAuto and a real AirCurve 10 VAuto: IPAP and EPAP match the
  files, and their difference is the prescribed pressure support.

### Fixed
- **The therapy mode sensor read 0 on every machine.** It now follows the
  standing rule, the session's value first and the STR's when that is 0, so a
  ResMed shows the mode its card reports. On a bi-level, 6 (AirCurve 10) and
  8 (AirCurve 11) are named VAuto, not ASV.
- **No oximeter no longer reads 0 % SpO2.** `str_spo2_50` is published as
  unknown instead, replacing a stale retained 0.00.
- An AirCurve 10's daily targets were dropped by the parser (cpapdash-parser
  2026.8.2).

## 5.2.7

### Fixed
- **A `.vld` next to the card that changes is read again** (#32). 5.2.6 read
  each file once, by name. A file caught while the other tool was still
  writing it was stored short and never completed; it is now stored again
  whenever its size or modified time changes, as the collector does for the
  card's own files.
- **A `.vld` that would not read is retried when it changes**, instead of
  only after a restart.

### Changed
- **The folder scan says what it saw.** One log line with the card folder,
  how many `.vld` files it found, the folders it looked in, and any folder it
  does not search into, so "no files where it looked" no longer looks like
  "nothing new". Logged when it changes, not every burst.

## 5.2.6

### Added
- **Remove night** (#31, SDD-029). The sessions menu can remove a whole night
  from the database: its sessions, daily summary, O2 ring data and transfer
  record, in one step, after a confirmation. It stays removed: the collector,
  the STR, the ring's files, SleepHQ auto-export and backfills all skip it.
  Reparse of the same date brings it back from the archive. Files on disk are
  never touched. `DELETE /api/sessions/{date}`.
- **The O2 ring's `.vld` files next to the card** (#32, SDD-028). A `.vld` in
  the card's root or in any folder beside `DATALOG` (another tool's
  `Oxymetry/`, say) is imported on the next pass, and the O2 upload page takes
  `.vld` as well as CSV. The same file from the ring, the card or the upload is
  one night, not three.
- `architecture/db.md` and `architecture/layers.md`: every table on the three
  databases and the code's layers, linked from the README.

### Fixed
- **Reparse works on ezShare installs.** It answered "Reparse not available"
  whenever no local folder was configured; it now reparses from the archive
  the collector fills. The Backfill page and the CPAP zip upload use the same
  root.
- **A backfilled history shows our numbers.** The backfill kept the STR's
  hours and index on every night it imported when the card had an STR; it now
  re-derives each night from its sessions, as the collector does (5.2.5).
- MySQL: reparsing a night no longer leaves orphaned session-file rows.
- A manual model training request starts at once instead of after up to a
  minute.

## 5.2.5

### Fixed
- **A live night no longer freezes at its first mask-off.** 5.2.4 took the
  night's hours from the STR whenever one had been read, and the STR counts a
  mask-on period only once it ends. On a night with a break, the dashboard,
  the sessions list and the session cards stopped at the first mask-off (47
  minutes shown with 71 recorded and the mask on) and divided the night's
  events by those minutes, so the AHI read high as well. The night's hours
  are now the sum of our own sessions, they grow with the files, and every
  index divides by them. SDD-026 is amended accordingly.
- **Leak, mask pressure and SpO2 are ours.** The STR no longer overwrites
  the values our sessions measured. It fills one only where our sessions have
  none, and still supplies what we do not compute: mode, EPR level, mask pairs
  and the nights we have no session files for.
- The machine's own duration and index stay beside ours in the STR panel.
  Every night is recalculated on the first start after the upgrade.

## 5.2.4

### Changed
- **Our numbers win, the STR stays official (SDD-026).** The dashboard, the
  30-day trends, the week index, compliance, the sessions list and the
  session cards all read the same night the same way: our exact event count
  over the machine's own therapy hours, the STR's `Duration`, or over our
  recorded span until the STR has been read. The STR's own index and
  duration are kept in their own columns and shown in the STR panel as the
  machine's report, which reads differently because the STR floors its
  index to one decimal. Nights with no session files keep the STR's figures,
  so history stays on the charts. The machine's leak and pressure percentiles
  are never replaced by session means once an STR has written the night.
  This is the same arithmetic cpapdash.com uses, so the two agree on a night.
- **The headline leak is the 95th percentile**, as on cpapdash.com. It was
  the median under a field named p95.
- **The STR is read first on a fresh run**, before any session file, so the
  first rows on the dashboard already carry the machine's hours. It used to
  wait behind every download on the card.

## 5.2.3

### Fixed
- **Mask pressure, EPR and snore were missing from a night stored file by
  file.** 5.2.2 saves a session after every checkpoint file, so the first save
  of a minute can come from the BRP alone, before the PLD that carries those
  values has been downloaded. The per-minute insert ignored the later save and
  kept the half-empty row forever, and closing the session does not reparse.
  All three databases now complete the row on a later save and never erase
  what an earlier one knew.

### Added
- **A zip for the Raspberry Pi.** `hms-cpap-linux-armhf.zip` on the release
  page holds the service built for 32-bit Raspberry Pi OS (trixie), the web
  UI, a systemd unit and an install script. Unzip, `sudo ./install.sh`, open
  the address it prints. Running it again on a newer zip is the upgrade. See
  SDD-025.

## 5.2.2

### Fixed
- **A first run stored nothing until the whole card was in.** The burst
  collector downloaded every session the card listed, then every sidecar,
  then archived the folders, and only then parsed and saved. Against a card
  holding ten nights over an ez Share, which serves about one file per
  second, the dashboard stayed empty for close to forty minutes and every
  night sat at Live. A session is now parsed and saved after every checkpoint
  file it downloads, the way a later burst already re-parses a growing night,
  so the first rows appear within seconds of the service starting.

- **The newest night comes first.** Sessions are now fetched from the latest
  night backwards, so the night worth looking at is the first one on the
  dashboard instead of the last.

## 5.2.1

### Fixed
- **A Sefam S.Box card crashed the collector.** The card parsed correctly and
  the sessions were saved, then the worker thread dereferenced a null pointer
  looking for an `STR.edf` that Sefam machines do not write. The dashboard was
  empty for data the service had just read.

- **The sessions list was empty for everyone.** A column added to one half of
  the query and not the other made it fail when the statement was prepared.
  Nothing surfaced an error: the endpoint answered normally with an empty list
  while the dashboard beside it stayed full. Anyone on 5.2.0 was affected,
  whatever their machine.

- **A night's index no longer disagrees with itself.** The sessions list rebuilt
  it from the per-type event columns, which leaves out the apneas a machine
  reports without classifying. The same night read 0.00 in the list and 60.0 on
  the dashboard. ResMed nights carrying unclassified apneas were undercounted by
  the same route.

- **Reports named the wrong machine.** Every PDF cover said "ResMed AirSense 10"
  regardless of what recorded the data.

### Changed
- **An apnea index is no longer shown as an AHI.** The Sefam S.Box scores apneas
  and never marks hypopneas, so its events-per-hour is a different measurement
  on a different scale, and roughly a third of a real AHI is missing from it.
  Every surface that showed it now says which index it is, and none of them
  grade it against AHI severity bands: the dashboard, the sessions list, the
  session detail, the 30-day trend, and the PDF, in all five languages.

- **Counts a machine never measured are no longer shown as zero.** Obstructive,
  central, hypopnea and RERA are all zero on a machine that does not classify
  its events, and every one of these read that as a clean night. The hypopnea
  tile was even coloured green. Where there is no breakdown, there is now a
  sentence saying why, and the charts and panels that would have plotted flat
  lines along zero are gone. The event count itself is still shown.

- **The therapy score is withheld for a machine whose events cannot be graded**,
  rather than computed from the parts that remain. Scoring usage and leak alone
  rated a 17 apneas/hour night as good. Usage, leak and the apnea index are all
  still reported on their own.

## 5.2.0

### Added
- **You can now pick your machine in the interface.** Löwenstein Prisma and
  Sefam S.Box have both been supported for a while and neither could be selected
  anywhere: not in Settings, not in the first-run wizard, not in the desktop
  configurator. Owners of both had to hand-edit `config.json`. Philips
  Respironics is offered too, marked experimental.

- **The data source is now two questions instead of one.** Where the files come
  from, and what wrote them:

  ```
  transport   ezshare | local | fysetc
  format      resmed | lowenstein | sefam | philips
  ```

  `local`, `lowenstein` and `sefam` were never three sources. They are one
  source, a folder on disk, read by three different parsers. Splitting them is
  what lets a question about *where* be answered by asking about where: the
  check for "did this arrive over a network, so must we write it down first?"
  used to work by listing machine brands, and was right about Sefam only because
  nobody had got round to breaking it.

  **Your existing configuration is migrated automatically** and keeps working
  untouched. The old `source` setting is still written for one release, so
  downgrading is safe. `CPAP_SOURCE` still works everywhere it did.

### Fixed
- **The folder picker was unreachable for Prisma and S.Box owners** in the
  desktop configurator. It appeared only for ResMed, so users of the two
  machines that *only* read from a folder could not choose the folder.

## 5.1.6

Catches the add-on up with CpapDash. It was pinned to the 5.1.0 image and had
stayed there through five releases, so everything below has been shipping to
everyone else and not to add-on users.

- **Five languages** across the whole interface: English, Spanish, French,
  Portuguese and Hungarian.
- **Sefam S.Box cards can be read**, with apnea detection.
- **The card is no longer re-read from end to end on every beat.** CSL and EVE
  files are fetched only when the card's own timestamp shows they were
  rewritten. This is a correctness fix as much as a saving: an EVE grows by one
  small record per scored event, the card's directory listing rounds every size
  to a whole kilobyte, and 46% of nights never cross that first kilobyte at all.
  Size could not see an apnea being recorded. The timestamp can.
- **The dashboard says which night it is showing**, with the year, in your own
  language, and says how old it is once it is no longer current.
- **Angular patched** to 21.2.22, clearing every outstanding advisory.

From this release the add-on is bumped automatically whenever CpapDash is
released, so it cannot silently fall behind again.

## 5.1.1

The add-on no longer overwrites your CpapDash configuration on every start. It
writes only the settings it actually exposes and leaves the rest of the file
alone, so the LLM, SleepHQ, oximetry, ML training, sleep staging, logging and
agent settings you set in CpapDash's own Settings page now survive a restart. An
option you leave empty no longer blanks out a value that is already there.

This matters most when moving an existing install in: copy your old
`config.json` into the add-on's data directory and everything in it is kept.

Your MQTT settings are part of that. Home Assistant's broker is used when it
offers one, and when it does not, whatever broker you already point at is left
untouched instead of being switched off. Previously an install talking to a
broker elsewhere on the network lost every sensor on the first restart.

Filling in `device_id` now also skips the setup wizard, since only someone
migrating an existing install ever types one in.

## 5.1.0

Adds ResMed myAir, off by default. Connect it and CpapDash reads your own
nights back from ResMed and shows their score next to its own, per night and per
component. Read only: nothing is ever written back.

Your myAir password is used once to sign in and is then erased. ResMed issues a
revocable token that replaces it, which can only read this account's sleep data
and cannot sign in as you anywhere. The add-on keeps that token across restarts,
so once you are connected you can clear `myair_password` from the options.

`NA` covers Australia as well as North America. `EU` emails a verification code
the first time and then stops asking.

## 5.0.5

First release of CpapDash as a Home Assistant add-on.

5.0.5 rather than an earlier version because it is the first release whose web UI
survives being served underneath an Ingress prefix. On 5.0.4 the page loads and
then fails every asset and every API call, so there was nothing to package.

The add-on is a thin layer over that published image: an entrypoint that turns
add-on options into CpapDash configuration and asks the Supervisor for the MQTT
broker's credentials, so there is nothing to type and no second password. With no
broker configured it degrades to the web UI alone rather than refusing to start.

The entities were already there: CpapDash has published MQTT discovery for its
sensors, supplies, cleaning schedules and live session state for a long time, so
no custom integration is needed and none is offered.

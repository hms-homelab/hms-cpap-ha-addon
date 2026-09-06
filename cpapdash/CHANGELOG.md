# Changelog

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

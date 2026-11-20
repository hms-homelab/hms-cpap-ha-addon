#!/usr/bin/env sh
#
# Turn Home Assistant add-on options into a CpapDash configuration, then hand
# over to the service.
#
# Plain POSIX sh with jq rather than bashio. bashio ships with the Home Assistant
# base images, and this add-on is FROM the CpapDash image instead, so pulling it
# in would mean vendoring a shell library to do what two curl calls already do.
# The one thing bashio would have given us for free, the MQTT broker's
# credentials, is a single documented Supervisor endpoint.
#
set -eu

# The Supervisor writes the options to /data and nowhere else, so this path
# never follows the data directory (SDD-067).
OPTIONS=/data/options.json

opt() {
    # $1 = jq path, $2 = fallback when absent, null or empty
    value=$(jq -r "$1 // empty" "$OPTIONS" 2>/dev/null || true)
    if [ -z "$value" ]; then printf '%s' "$2"; else printf '%s' "$value"; fi
}

# ---------------------------------------------------------------------------
# The data directory (SDD-067)
# ---------------------------------------------------------------------------
# Everything the service keeps lives under one directory: config.json, the
# SQLite database, the Sleep Bridge banks and rebuilt cards, bridge update
# jobs, uploads, supply events and by default the card archive.
#
# By default that is /data, the add-on's own persistent storage, which
# survives an update but is not reachable from the file editor, Samba or
# share. The data_dir option puts it under /share, /config (the add-on's
# config folder) or /media instead. An install that never sets the option
# behaves exactly as before, in /data.
#
# When files have to move, hms-cpap's move mode moves them: it prints its
# progress here (the Log tab) and serves a progress page on the web port until
# it is done. It never overwrites a file that exists at the destination, and
# it leaves options.json, a copy of config.json and the marker in /data.
HOME_DIR=/data
MARKER="$HOME_DIR/.data_dir_moved"
CONFIG_DIR="$HOME_DIR"
DATA_DIR_WANTED=$(opt '.data_dir' '')
while [ "${#DATA_DIR_WANTED}" -gt 1 ] && [ "${DATA_DIR_WANTED%/}" != "$DATA_DIR_WANTED" ]; do
    DATA_DIR_WANTED=${DATA_DIR_WANTED%/}
done

# Anywhere else would land in the container and be lost on the next recreate.
data_dir_allowed() {
    case "$1" in
        */../*|*/..|*/./*|*/.) return 1 ;;
        /share|/share/*|/config|/config/*|/media|/media/*) return 0 ;;
        *) return 1 ;;
    esac
}

data_dir_writable() {
    mkdir -p "$1" 2>/dev/null || return 1
    probe="$1/.hms_cpap_write_test.$$"
    ( : > "$probe" ) 2>/dev/null || return 1
    rm -f "$probe"
}

# A directory that cannot be used: this run keeps its data in /data, says so
# here, and tells the service, whose pages show a banner naming both.
#
# The run also writes the marker, naming /data as where its data went, so the
# next start that can write the directory moves it across even when the
# directory was a fresh install that never moved anything. A marker that is
# already there is kept: it names the directory this install moved to, which
# a later start still needs to catch up into or to move from.
fall_back() {
    echo "[cpapdash] WARNING: data_dir $DATA_DIR_WANTED $1."
    echo "[cpapdash] WARNING: this run keeps its data in $HOME_DIR. Restart the add-on once $DATA_DIR_WANTED can be written."
    export HMS_CPAP_DATA_DIR_FALLBACK="$DATA_DIR_WANTED"
    CONFIG_DIR="$HOME_DIR"
    [ -s "$MARKER" ] || printf '%s\n' "$HOME_DIR" > "$MARKER"
}

# A move that does not complete counts as a directory that cannot be written.
move_to_wanted() {
    echo "[cpapdash] moving the data directory from $1 to $DATA_DIR_WANTED"
    if /usr/local/bin/hms_cpap --move-data "$1" "$DATA_DIR_WANTED" --port 8893; then
        CONFIG_DIR="$DATA_DIR_WANTED"
    else
        fall_back "could not take the files from $1"
    fi
}

MARKED=$(head -n 1 "$MARKER" 2>/dev/null || true)
if [ -n "$DATA_DIR_WANTED" ]; then
    if ! data_dir_allowed "$DATA_DIR_WANTED"; then
        fall_back "is not under /share, /config or /media"
    elif ! data_dir_writable "$DATA_DIR_WANTED"; then
        fall_back "cannot be created or written"
    else
        # The real path, which is what the marker holds, and checked again so
        # a symbolic link cannot lead out of the three places.
        DATA_DIR_WANTED=$(cd "$DATA_DIR_WANTED" && pwd -P)
        if ! data_dir_allowed "$DATA_DIR_WANTED"; then
            fall_back "is not under /share, /config or /media"
        elif [ -f "$DATA_DIR_WANTED/config.json" ]; then
            if [ "$MARKED" = "$DATA_DIR_WANTED" ] || [ "$MARKED" = "$HOME_DIR" ]; then
                # This install moved here before, or a fallback run stored in
                # /data since. Whatever is in /data and not here yet moves
                # across; nothing here is overwritten.
                move_to_wanted "$HOME_DIR"
            else
                # Already holds a configuration: used as it is, /data untouched.
                CONFIG_DIR="$DATA_DIR_WANTED"
            fi
        elif [ -n "$MARKED" ] && [ "$MARKED" != "$DATA_DIR_WANTED" ] && [ -f "$MARKED/config.json" ]; then
            # The option changed from one directory to another.
            move_to_wanted "$MARKED"
        elif [ -f "$HOME_DIR/config.json" ]; then
            # The first move out of /data.
            move_to_wanted "$HOME_DIR"
        else
            # A fresh install in the chosen directory.
            CONFIG_DIR="$DATA_DIR_WANTED"
        fi
    fi
fi

# Saved paths follow the move: a local_dir sitting inside a data directory
# this install used before (/data, or the one the marker names) points at the
# same place inside the one in use. Only when the option is set: cleared, the
# files stay where they are and so do the paths to them. MARKED is the marker
# as it was before this start's move, which named the directory moved from.
PREVIOUS_DIR_1=""
PREVIOUS_DIR_2=""
if [ -n "$DATA_DIR_WANTED" ]; then
    [ "$CONFIG_DIR" != "$HOME_DIR" ] && PREVIOUS_DIR_1="$HOME_DIR"
    [ -n "$MARKED" ] && [ "$MARKED" != "$CONFIG_DIR" ] && PREVIOUS_DIR_2="$MARKED"
fi
echo "[cpapdash] data directory: $CONFIG_DIR"

CONFIG="$CONFIG_DIR/config.json"

# The service keeps everything under this directory, so it is always passed
# on: the image's own default is not a place this add-on keeps anything.
export HMS_CPAP_DATA_DIR="$CONFIG_DIR"

SOURCE=$(opt '.source' 'ezshare')
EZSHARE_URL=$(opt '.ezshare_url' '')
FLASHAIR_URL=$(opt '.flashair_url' '')
LOCAL_DIR=$(opt '.local_dir' '')
BURST=$(opt '.burst_interval' '300')
DEVICE_NAME=$(opt '.device_name' 'CPAP')
DEVICE_ID=$(opt '.device_id' '')
DEVICE_ID_FROM_OPTIONS="$DEVICE_ID"
ARCHIVE_DIR=$(opt '.archive_dir' '')

# Every stored night is filed under device_id and every read filters on it, so a
# migration that changes it silently shows an empty dashboard over a full
# database. Left empty on a fresh install we generate one and keep it, rather
# than generating a NEW one on every restart, which would scatter history across
# a trail of device rows.
if [ -z "$DEVICE_ID" ] && [ -f "$CONFIG" ]; then
    DEVICE_ID=$(jq -r '.device_id // ""' "$CONFIG" 2>/dev/null || echo "")
fi
[ -n "$DEVICE_ID" ] || DEVICE_ID="cpapdash_addon"

# Where the card files are kept. The add-on's own /data by default, which
# survives updates; an explicit path is for carrying on writing where an
# existing install already writes.
[ -n "$ARCHIVE_DIR" ] || ARCHIVE_DIR="$CONFIG_DIR/cpap_archive"
DB_TYPE=$(opt '.database' 'sqlite')
DB_HOST=$(opt '.db_host' '')
DB_PORT=$(opt '.db_port' '0')
DB_NAME=$(opt '.db_name' '')
DB_USER=$(opt '.db_user' '')
DB_PASSWORD=$(opt '.db_password' '')
MYAIR_ENABLED=$(opt '.myair_enabled' 'false')
MYAIR_REGION=$(opt '.myair_region' 'NA')
MYAIR_USERNAME=$(opt '.myair_username' '')
MYAIR_PASSWORD=$(opt '.myair_password' '')

# ---------------------------------------------------------------------------
# MQTT, discovered rather than typed
# ---------------------------------------------------------------------------
# `services: [mqtt:want]` means the Supervisor will hand us the broker's details
# if one is configured, and simply 404 if not. CpapDash is fully usable with no
# broker, so a missing one disables MQTT instead of failing the start.
MQTT_ENABLED=false
MQTT_HOST=""
MQTT_PORT=1883
MQTT_USER=""
MQTT_PASSWORD=""

if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    mqtt_json=$(curl -sf -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/services/mqtt 2>/dev/null || true)
    if [ -n "$mqtt_json" ]; then
        MQTT_HOST=$(printf '%s' "$mqtt_json" | jq -r '.data.host // empty')
        if [ -n "$MQTT_HOST" ]; then
            MQTT_ENABLED=true
            MQTT_PORT=$(printf '%s' "$mqtt_json" | jq -r '.data.port // 1883')
            MQTT_USER=$(printf '%s' "$mqtt_json" | jq -r '.data.username // empty')
            MQTT_PASSWORD=$(printf '%s' "$mqtt_json" | jq -r '.data.password // empty')
            echo "[cpapdash] MQTT broker discovered at ${MQTT_HOST}:${MQTT_PORT}"
        fi
    fi
fi
[ "$MQTT_ENABLED" = "true" ] || echo "[cpapdash] no MQTT broker configured, Home Assistant entities disabled"

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
# SQLite under /config by default, so a first install needs no server and no
# decisions. /config is the add-on's own persistent directory, which is why the
# database survives an add-on update.
SQLITE_PATH="$CONFIG_DIR/cpap.db"
if [ "$DB_TYPE" != "sqlite" ] && [ -z "$DB_HOST" ]; then
    echo "[cpapdash] database=$DB_TYPE selected but db_host is empty, falling back to sqlite"
    DB_TYPE=sqlite
fi

# ---------------------------------------------------------------------------
# First install runs the wizard
# ---------------------------------------------------------------------------
# On a first install there is no configuration yet, so setup_complete stays
# false and opening the add-on lands on CpapDash's own setup wizard, with the
# machine in front of the user and whatever they typed into the options already
# filled in. That is a far better first run than a dashboard with no data and no
# explanation of why.
#
# On every start after that the existing answer is preserved, because sending a
# configured user back through the wizard on a restart would be absurd. The
# wizard writes setup_complete itself once it finishes.
#
# The one first start that must NOT open the wizard is a migration. Typing a
# device_id into the options is something only a person moving an existing
# install ever does: it is the id their history is already filed under, and they
# had to go and find it. Their database is populated and their source is already
# working, so answering the wizard's questions again buys nothing, and the wizard
# offering to generate a new id is the exact mistake that would hide their data.
SETUP_COMPLETE=false
# The same reasoning pins the id. CpapDash gives an install still on one of
# its old fixed default ids a generated one of its own, moving its nights to
# it; an id typed into the options was chosen, so it must never be moved. This
# start would also put the typed id straight back over the new one.
DEVICE_ID_PINNED=false
if [ -n "$DEVICE_ID_FROM_OPTIONS" ]; then
    echo "[cpapdash] device_id given in the options, treating this as a migration"
    SETUP_COMPLETE=true
    DEVICE_ID_PINNED=true
fi
MYAIR_DEVICE_TOKEN=""
MYAIR_REFRESH_TOKEN=""
if [ -f "$CONFIG" ]; then
    previous=$(jq -r '.setup_complete // false' "$CONFIG" 2>/dev/null || echo false)
    [ "$previous" = "true" ] && SETUP_COMPLETE=true
    # Both of these are written BY the service after a successful myAir sign-in,
    # not by the user, so they have to survive the config being regenerated.
    #
    # Losing the device token means ResMed emails a fresh code, which a headless
    # add-on has no way to answer. Losing the REFRESH token is worse in a quieter
    # way: the add-on would fall back to the password on every restart, so the
    # password could never be removed from the options and the whole point of
    # holding a revocable token instead would be lost.
    MYAIR_DEVICE_TOKEN=$(jq -r '.myair.device_token // ""' "$CONFIG" 2>/dev/null || echo "")
    MYAIR_REFRESH_TOKEN=$(jq -r '.myair.refresh_token // ""' "$CONFIG" 2>/dev/null || echo "")
fi

# myAir needs a username and something to sign in with: the password, or the
# token saved by an earlier sign-in. Checked only now, after that token has been
# read, because the password is meant to be cleared once the token exists, and
# judging by the password alone switched myAir off for exactly those users.
if [ "$MYAIR_ENABLED" = "true" ] && { [ -z "$MYAIR_USERNAME" ] || { [ -z "$MYAIR_PASSWORD" ] && [ -z "$MYAIR_REFRESH_TOKEN" ]; }; }; then
    echo "[cpapdash] myair_enabled is on but the username is empty, or there is neither a password nor a saved sign-in, leaving myAir off"
    MYAIR_ENABLED=false
fi

# Once a refresh token exists the password is not needed and is not written into
# the generated config at all. Users can clear it from the add-on options too,
# and the add-on keeps working.
if [ -n "$MYAIR_REFRESH_TOKEN" ] && [ -n "$MYAIR_PASSWORD" ]; then
    echo "[cpapdash] myAir is already connected; ignoring the password in the options."
    echo "[cpapdash] You can clear myair_password: it is no longer needed."
    MYAIR_PASSWORD=""
fi
echo "[cpapdash] setup_complete=$SETUP_COMPLETE"

# ---------------------------------------------------------------------------
# Write the configuration, by MERGING rather than replacing
# ---------------------------------------------------------------------------
# CpapDash's configuration is much larger than what this add-on exposes: the LLM
# settings, SleepHQ, ML training, the agent, oximetry, logging, sleep staging and
# the cloud mirror all live in the same file. An earlier version of this script
# wrote a fresh config on every start, which silently discarded every one of
# them, and would have thrown away a migrated install's entire tuning on its
# first restart.
#
# So the options below are an OVERLAY on whatever is already there. Anything the
# add-on does not own is preserved untouched, which is also what makes importing
# an existing config.json a supported way to move in.
#
# Built with jq rather than a heredoc so that a password containing a quote or a
# backslash cannot produce a broken file.
mkdir -p "$CONFIG_DIR"

BASE="$CONFIG_DIR/.config.base.json"
if [ -f "$CONFIG" ]; then cp "$CONFIG" "$BASE"; else echo '{}' > "$BASE"; fi

jq -n \
    --arg device_name "$DEVICE_NAME" \
    --arg device_id "$DEVICE_ID" \
    --arg archive_dir "$ARCHIVE_DIR" \
    --arg source "$SOURCE" \
    --arg ezshare_url "$EZSHARE_URL" \
    --arg flashair_url "$FLASHAIR_URL" \
    --arg local_dir "$LOCAL_DIR" \
    --argjson burst "${BURST:-300}" \
    --arg db_type "$DB_TYPE" \
    --arg sqlite_path "$SQLITE_PATH" \
    --arg db_host "$DB_HOST" \
    --argjson db_port "${DB_PORT:-0}" \
    --arg db_name "$DB_NAME" \
    --arg db_user "$DB_USER" \
    --arg db_password "$DB_PASSWORD" \
    --argjson mqtt_enabled "$MQTT_ENABLED" \
    --arg mqtt_host "$MQTT_HOST" \
    --argjson mqtt_port "${MQTT_PORT:-1883}" \
    --arg mqtt_user "$MQTT_USER" \
    --arg mqtt_password "$MQTT_PASSWORD" \
    --argjson setup_complete "$SETUP_COMPLETE" \
    --argjson device_id_pinned "$DEVICE_ID_PINNED" \
    --argjson myair_enabled "$MYAIR_ENABLED" \
    --arg myair_region "$MYAIR_REGION" \
    --arg myair_username "$MYAIR_USERNAME" \
    --arg myair_password "$MYAIR_PASSWORD" \
    --arg myair_device_token "$MYAIR_DEVICE_TOKEN" \
    --arg myair_refresh_token "$MYAIR_REFRESH_TOKEN" \
    '{
        device_id: $device_id,
        device_name: $device_name,
        archive_dir: $archive_dir,
        source: $source,
        ezshare_url: $ezshare_url,
        flashair_url: $flashair_url,
        local_dir: $local_dir,
        burst_interval: $burst,
        web_port: 8893,
        static_dir: "/home/cpap/static/browser",
        setup_complete: $setup_complete,
        database: {
            type: $db_type,
            sqlite_path: $sqlite_path,
            host: $db_host,
            port: $db_port,
            name: $db_name,
            user: $db_user,
            password: $db_password
        },
        myair: {
            enabled: $myair_enabled,
            region: $myair_region,
            username: $myair_username,
            password: $myair_password,
            refresh_token: $myair_refresh_token,
            device_token: $myair_device_token,
            poll_minutes: 60
        }
        # NOTE: no apostrophes anywhere in this jq program. It is inside a
        # single-quoted shell string, so one would end the string and the error
        # lands somewhere further down that looks unrelated.
    }
    # An empty option must not clobber a real value that is already there. That
    # is what lets someone fill in three options and keep everything else an
    # imported configuration brought with it. Booleans and numbers survive:
    # only empty strings and nulls are dropped.
    | with_entries(select(.value != "" and .value != null))
    | (.database |= with_entries(select(.value != "" and .value != null)))
    | (.myair   |= with_entries(select(.value != "" and .value != null)))

    # Chosen SQLite means SQLite. The overlay drops empty strings, so a server
    # the options once named would otherwise stay in the saved config beside
    # type sqlite, and the service, seeing a host, kept opening the server
    # (with port 0, since that one is a number and does land) and never the
    # file. The server fields go when the option says sqlite.
    | (if $db_type == "sqlite" then .database |= del(.host, .port, .name, .user, .password) else . end)

    # A saved config carries transport, and the service reads it ahead of
    # source. So the option is written as a transport too, or changing it here
    # on an install that already ran would not take: this tab wins, as the
    # docs say. The format is left alone (a folder may hold a Prisma or an
    # S.Box), except that a FlashAir card is ResMed.
    | . + {transport: $source}
    | . + (if $source == "flashair" then {format: "resmed"} else {} end)

    # Set when the id came from the options, and never cleared from here: a
    # false would overwrite a pin someone put in config.json by hand.
    | . + (if $device_id_pinned then {device_id_pinned: true} else {} end)

    # MQTT only when the Supervisor actually offered a broker. Otherwise leave
    # whatever is configured alone: an install migrating in may point at a
    # broker elsewhere on the network, and overwriting that with "none" is
    # exactly how its Home Assistant entities silently disappear.
    | . + (if $mqtt_enabled then {
        mqtt: {
            enabled: true,
            broker: $mqtt_host,
            port: $mqtt_port,
            username: $mqtt_user,
            password: $mqtt_password,
            client_id: "cpapdash_addon"
        }
      } else {} end)
    ' > "$CONFIG_DIR/.config.overlay.json"

# Recursive merge, overlay wins. Everything the add-on does not set survives.
# Except a database server under type sqlite: leaving it out of the overlay
# keeps the saved one, and the service, seeing a host, opens that server and
# refuses to start when it is gone. So it is dropped again after the merge.
#
# SDD-067: and a local_dir inside a data directory used before follows it into
# the one in use (see PREVIOUS_DIR above). archive_dir needs nothing: typed in
# the options it wins, and otherwise it is always the one in use.
jq -s \
    --arg old1 "$PREVIOUS_DIR_1" \
    --arg old2 "$PREVIOUS_DIR_2" \
    --arg now "$CONFIG_DIR" \
    'def follow($old):
        if $old == "" or type != "string" then .
        elif . == $old or startswith($old + "/") then $now + ltrimstr($old)
        else . end;
    .[0] * .[1]
    | if .database.type == "sqlite"
      then .database |= del(.host, .port, .name, .user, .password)
      else . end
    | if has("local_dir") then .local_dir |= (follow($old1) | follow($old2)) else . end' \
    "$BASE" "$CONFIG_DIR/.config.overlay.json" > "$CONFIG"
rm -f "$BASE" "$CONFIG_DIR/.config.overlay.json"

mkdir -p "$ARCHIVE_DIR" 2>/dev/null || \
    echo "[cpapdash] WARNING: cannot create $ARCHIVE_DIR. If it is on a network share, check it is mounted in Home Assistant under Settings, System, Storage."

echo "[cpapdash] source=$SOURCE database=$DB_TYPE myair=$MYAIR_ENABLED"
echo "[cpapdash] device_id=$DEVICE_ID archive=$ARCHIVE_DIR"

# exec, so signals reach the service and the Supervisor's stop is a clean stop
# rather than a timeout followed by a kill.
exec /usr/local/bin/hms_cpap --config "$CONFIG"

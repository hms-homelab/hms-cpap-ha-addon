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

OPTIONS=/data/options.json
# /data, not /config. /data is the add-on's own persistent directory, which is
# the documented home for add-on state and survives an update. /config is Home
# Assistant's user-facing app config folder; writing our generated file there
# would put a machine-written file in a place a person is invited to edit.
CONFIG_DIR=/data
CONFIG="$CONFIG_DIR/config.json"

opt() {
    # $1 = jq path, $2 = fallback when absent, null or empty
    value=$(jq -r "$1 // empty" "$OPTIONS" 2>/dev/null || true)
    if [ -z "$value" ]; then printf '%s' "$2"; else printf '%s' "$value"; fi
}

SOURCE=$(opt '.source' 'ezshare')
EZSHARE_URL=$(opt '.ezshare_url' '')
LOCAL_DIR=$(opt '.local_dir' '')
BURST=$(opt '.burst_interval' '300')
DEVICE_NAME=$(opt '.device_name' 'CPAP')
DEVICE_ID=$(opt '.device_id' '')
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

# myAir needs both halves or it is not configured, whatever the toggle says.
if [ "$MYAIR_ENABLED" = "true" ] && { [ -z "$MYAIR_USERNAME" ] || [ -z "$MYAIR_PASSWORD" ]; }; then
    echo "[cpapdash] myair_enabled is on but the username or password is empty, leaving myAir off"
    MYAIR_ENABLED=false
fi

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
SETUP_COMPLETE=false
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
# Write the configuration
# ---------------------------------------------------------------------------
# Built with jq rather than a heredoc so that a password containing a quote or a
# backslash cannot produce a broken file.
mkdir -p "$CONFIG_DIR"
jq -n \
    --arg device_name "$DEVICE_NAME" \
    --arg device_id "$DEVICE_ID" \
    --arg archive_dir "$ARCHIVE_DIR" \
    --arg source "$SOURCE" \
    --arg ezshare_url "$EZSHARE_URL" \
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
        mqtt: {
            enabled: $mqtt_enabled,
            broker: $mqtt_host,
            port: $mqtt_port,
            username: $mqtt_user,
            password: $mqtt_password,
            client_id: "cpapdash_addon"
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
    }' > "$CONFIG"

mkdir -p "$ARCHIVE_DIR" 2>/dev/null || \
    echo "[cpapdash] WARNING: cannot create $ARCHIVE_DIR. If it is on a network share, check it is mounted in Home Assistant under Settings, System, Storage."

echo "[cpapdash] source=$SOURCE database=$DB_TYPE myair=$MYAIR_ENABLED"
echo "[cpapdash] device_id=$DEVICE_ID archive=$ARCHIVE_DIR"

# exec, so signals reach the service and the Supervisor's stop is a clean stop
# rather than a timeout followed by a kill.
exec /usr/local/bin/hms_cpap --config "$CONFIG"

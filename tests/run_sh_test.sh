#!/bin/sh
# SDD-067: run.sh's data directory cases, without Home Assistant.
#
# Runs a copy of cpapdash/run.sh with /data, /share, /config and /media
# pointed into a temporary tree and a stand-in hms_cpap (stub_hms_cpap.sh), and
# checks which case applies, the fallback, the catch-up, a change of directory
# and the saved paths that follow a move. Needs sh, jq and perl.
#
#   sh tests/run_sh_test.sh [path/to/run.sh]
#
# Each check is a single-quoted expression evaluated after run.sh ran, so the
# variables in it are meant to expand late.
# shellcheck disable=SC2016,SC2034
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
RUN_SH="${1:-$HERE/../cpapdash/run.sh}"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

fresh() {
    ROOT=$(mktemp -d /tmp/sdd067-h.XXXXXX)
    ROOT=$(cd "$ROOT" && pwd -P)
    export HARNESS_ROOT="$ROOT"
    mkdir -p "$ROOT/data" "$ROOT/share" "$ROOT/config" "$ROOT/media" "$ROOT/bin"
    cp "$HERE/stub_hms_cpap.sh" "$ROOT/bin/hms_cpap"; chmod +x "$ROOT/bin/hms_cpap"
    perl -pe "s#(?<![\\w.])/(data|share|config|media)(?=[/|) \"'*]|\$)#$ROOT/\$1#g; s#/usr/local/bin/hms_cpap#$ROOT/bin/hms_cpap#g" \
        "$RUN_SH" > "$ROOT/run.sh"
    : > "$ROOT/calls.log"
}
options() { printf '%s' "$1" > "$ROOT/data/options.json"; }
existing() {  # an install that has run before, in /data
    printf '%s' '{"setup_complete":true,"device_id":"dev1","local_dir":"'"$ROOT"'/data/sleepbridge/TAP-1","sleep_bridge":{"port":8894}}' > "$ROOT/data/config.json"
    printf 'DB' > "$ROOT/data/cpap.db"
    mkdir -p "$ROOT/data/sleepbridge/TAP-1"; printf 'BANK' > "$ROOT/data/sleepbridge/TAP-1/bank.bin"
}
run() { (cd "$ROOT" && env -u HMS_CPAP_DATA_DIR_FALLBACK SUPERVISOR_TOKEN= sh "$ROOT/run.sh" > "$ROOT/out.log" 2>&1); }
started_with() { grep -q "STUB start data_dir=$1 " "$ROOT/calls.log"; }
fallback_is()  { grep -q "STUB start .* fallback=$1 config" "$ROOT/calls.log"; }
moved()        { grep -q "STUB move-data from=$1 to=$2" "$ROOT/calls.log"; }
no_move()      { ! grep -q "STUB move-data" "$ROOT/calls.log"; }
marker_is()    { [ "$(cat "$ROOT/data/.data_dir_moved" 2>/dev/null)" = "$1" ]; }
sum() { (cd "$1" && find . -type f -exec cksum {} + | sort); }

echo "1. option empty on an existing install"
fresh; existing; options '{"source":"local"}'; run
check "starts from /data"            'started_with "$ROOT/data"'
check "no fallback"                  'fallback_is ""'
check "no move"                      'no_move'
check "config.json setup_complete kept" '[ "$(jq -r .setup_complete "$ROOT/data/config.json")" = true ]'
check "cpap.db and sleepbridge byte-for-byte" '[ "$(cat "$ROOT/data/cpap.db")" = DB ] && [ "$(cat "$ROOT/data/sleepbridge/TAP-1/bank.bin")" = BANK ]'

for where in share config media; do
echo "2. fresh install into /$where/x"
fresh; options '{"data_dir":"'"$ROOT"'/'"$where"'/x"}'; run
check "starts from /$where/x"        'started_with "$ROOT/$where/x"'
check "config.json written there"    '[ -f "$ROOT/$where/x/config.json" ]'
check "sqlite path there"            'grep -q "sqlite=$ROOT/$where/x/cpap.db" "$ROOT/calls.log"'
check "/data holds only options.json" '[ "$(ls -A "$ROOT/data")" = options.json ]'
done

echo "3. option set on an existing install (first move)"
fresh; existing; options '{"data_dir":"'"$ROOT"'/share/x/"}'; run
check "move from /data"              'moved "$ROOT/data" "$ROOT/share/x"'
check "starts from /share/x"         'started_with "$ROOT/share/x"'
check "db and bank moved"            '[ -f "$ROOT/share/x/cpap.db" ] && [ -f "$ROOT/share/x/sleepbridge/TAP-1/bank.bin" ]'
check "/data: options, config copy, marker" '[ "$(ls -A "$ROOT/data" | tr "\n" " ")" = ".data_dir_moved config.json options.json " ]'
check "D19 local_dir follows"        'grep -q "local_dir=$ROOT/share/x/sleepbridge/TAP-1 " "$ROOT/calls.log"'
check "setup_complete kept"          '[ "$(jq -r .setup_complete "$ROOT/share/x/config.json")" = true ]'

echo "5. fallback: chosen directory not writable"
chmod 555 "$ROOT/share/x"; : > "$ROOT/calls.log"; run
check "starts from /data"            'started_with "$ROOT/data"'
check "fallback names the wanted dir" 'fallback_is "$ROOT/share/x"'
check "warning in the log"           'grep -q "WARNING: data_dir $ROOT/share/x cannot be created or written" "$ROOT/out.log"'
check "settings from the copy"       '[ "$(jq -r .setup_complete "$ROOT/data/config.json")" = true ] && [ "$(jq -r .sleep_bridge.port "$ROOT/data/config.json")" = 8894 ]'
check "D19 local_dir follows back to /data" 'grep -q "local_dir=$ROOT/data/sleepbridge/TAP-1 " "$ROOT/calls.log"'
check "the marker naming /share/x is kept" 'marker_is "$ROOT/share/x"'

echo "6. catch-up after the fallback"
mkdir -p "$ROOT/data/sleepbridge/TAP-1"; printf 'NEW' > "$ROOT/data/sleepbridge/TAP-1/bank2.bin"
chmod 755 "$ROOT/share/x"; : > "$ROOT/calls.log"; run
check "catch-up move from /data"     'moved "$ROOT/data" "$ROOT/share/x"'
check "starts from /share/x, no fallback" 'started_with "$ROOT/share/x" && fallback_is ""'
check "new batch moved across"       '[ "$(cat "$ROOT/share/x/sleepbridge/TAP-1/bank2.bin")" = NEW ]'

echo "10. data_dir changed to another directory"
options '{"data_dir":"'"$ROOT"'/media/y"}'; : > "$ROOT/calls.log"; run
check "move from the marked dir"     'moved "$ROOT/share/x" "$ROOT/media/y"'
check "marker names the new one"     'marker_is "$ROOT/media/y"'
check "starts from /media/y"         'started_with "$ROOT/media/y"'
check "D19 local_dir follows from the marked dir" 'grep -q "local_dir=$ROOT/media/y/sleepbridge/TAP-1 " "$ROOT/calls.log"'

echo "8. option cleared after a move"
options '{}'; before=$(sum "$ROOT/media/y"); : > "$ROOT/calls.log"; run
check "starts from /data"            'started_with "$ROOT/data"'
check "no move"                      'no_move'
check "chosen dir untouched"         '[ "$(sum "$ROOT/media/y")" = "$before" ]'

echo "7. chosen directory already has a config.json at first set"
fresh; existing; options '{"data_dir":"'"$ROOT"'/share/old"}'
mkdir -p "$ROOT/share/old"; printf '{"setup_complete":true}' > "$ROOT/share/old/config.json"
before=$(sum "$ROOT/data"); run
check "no move"                      'no_move'
check "starts from /share/old"       'started_with "$ROOT/share/old"'
check "/data byte-for-byte untouched" '[ "$(sum "$ROOT/data")" = "$before" ]'

echo "Fresh install in the chosen directory, a fallback run stores in /data, the next good start moves it"
fresh; options '{"data_dir":"'"$ROOT"'/share/f"}'; run
check "the fresh install starts in /share/f" 'started_with "$ROOT/share/f"'
check "no marker yet"                '[ ! -e "$ROOT/data/.data_dir_moved" ]'
mkdir -p "$ROOT/share/f/sleepbridge/TAP-1"; printf 'FIRST' > "$ROOT/share/f/sleepbridge/TAP-1/bank1.bin"
chmod 555 "$ROOT/share/f"; : > "$ROOT/calls.log"; run
check "the fallback run is in /data" 'started_with "$ROOT/data" && fallback_is "$ROOT/share/f"'
check "the fallback run writes the marker naming /data" 'marker_is "$ROOT/data"'
mkdir -p "$ROOT/data/sleepbridge/TAP-1"; printf 'SECOND' > "$ROOT/data/sleepbridge/TAP-1/bank2.bin"
chmod 755 "$ROOT/share/f"; : > "$ROOT/calls.log"; run
check "the good start moves from /data" 'moved "$ROOT/data" "$ROOT/share/f"'
check "it starts in /share/f, no fallback" 'started_with "$ROOT/share/f" && fallback_is ""'
check "the fallback run's batch moved across" '[ "$(cat "$ROOT/share/f/sleepbridge/TAP-1/bank2.bin")" = SECOND ]'
check "nothing there overwritten"    '[ "$(cat "$ROOT/share/f/sleepbridge/TAP-1/bank1.bin")" = FIRST ]'
check "the marker then names /share/f" 'marker_is "$ROOT/share/f"'

echo "D12. a data_dir outside /share, /config, /media"
fresh; existing; options '{"data_dir":"/tmp/elsewhere"}'; run
check "fallback"                     'started_with "$ROOT/data" && fallback_is "/tmp/elsewhere"'
check "warning"                      'grep -q "WARNING: data_dir /tmp/elsewhere is not under" "$ROOT/out.log"'
fresh; existing; options '{"data_dir":"'"$ROOT"'/share/../data"}'; run
check "a .. path is refused"         'fallback_is "$ROOT/share/../data"'

echo "D5. a move that fails"
fresh; existing; options '{"data_dir":"'"$ROOT"'/share/x"}'; STUB_MOVE_FAIL=1; export STUB_MOVE_FAIL; run; unset STUB_MOVE_FAIL
check "fallback after a failed move" 'started_with "$ROOT/data" && fallback_is "$ROOT/share/x"'
check "warning names the move"       'grep -q "could not take the files from $ROOT/data" "$ROOT/out.log"'

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]

#!/bin/sh
# Stand-in for hms_cpap in tests/run_sh_test.sh. --move-data follows the move
# rules coarsely (never overwrite, options.json and the marker stay, config.json
# copied out of /data, the marker names the destination); the real rules live
# in hms-cpap and are covered by its unit tests (SDD-067). The normal start
# records what run.sh handed over and exits.
set -eu
ROOT="${HARNESS_ROOT:?}"
if [ "${1:-}" = "--move-data" ]; then
    from="$2"; to="$3"
    echo "STUB move-data from=$from to=$to" >> "$ROOT/calls.log"
    [ "${STUB_MOVE_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' "$to" > "$ROOT/data/.data_dir_moved"
    mkdir -p "$to"
    (cd "$from" && find . -type f ! -path ./options.json ! -path ./.data_dir_moved) | while read -r f; do
        [ -e "$to/$f" ] && continue
        mkdir -p "$(dirname "$to/$f")"
        if [ "$from" = "$ROOT/data" ] && [ "$f" = "./config.json" ]; then cp "$from/$f" "$to/$f"
        else mv "$from/$f" "$to/$f"; fi
    done
    if [ "$from" != "$ROOT/data" ] && [ -f "$to/config.json" ]; then cp "$to/config.json" "$ROOT/data/config.json"; fi
    find "$from" -mindepth 1 -type d -empty -delete
    exit 0
fi
echo "STUB start data_dir=${HMS_CPAP_DATA_DIR:-} fallback=${HMS_CPAP_DATA_DIR_FALLBACK:-} config=$2" >> "$ROOT/calls.log"
echo "STUB local_dir=$(jq -r '.local_dir // ""' "$2") archive_dir=$(jq -r '.archive_dir // ""' "$2") sqlite=$(jq -r '.database.sqlite_path // ""' "$2")" >> "$ROOT/calls.log"

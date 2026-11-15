#!/bin/sh
# Everything that says whether the romaji is right, in one go:
# the Python reference against its fixtures, the reference fuzz, the
# Swift tests (which write the engine's readings), then the scorer's
# table over those readings. The readings come from the dictionary pack
# an app fetches, built here first, so what is scored is what ships.
#
# usage: scripts/romaji-eval.sh [--fast] [scorer options, e.g. --min-line 0.9]
#   --fast   the reference checks and the Swift tests only, with the
#            dictionary as the package has it (what CI runs)
#
# With fixtures/private/songs.json on this machine, the real-song set is
# scored too. Nothing from it is printed but the table and the misses'
# ids; pass --private-misses to see the lines.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
kit="$root/TestSupport"
fast=0
private_misses=0
if [ "${1:-}" = "--fast" ]; then fast=1; shift; fi
if [ "${1:-}" = "--private-misses" ]; then private_misses=1; shift; fi

TMPDIR=${TMPDIR:-/tmp}
export TMPDIR
export PYTHONDONTWRITEBYTECODE=1

echo "== Reference renderer against its fixtures"
python3 -I "$kit/tools/check_reference.py"

echo "== Reference fuzz"
python3 -I "$kit/tools/fuzz_reference.py"

if [ "$fast" = 0 ]; then
    echo "== Dictionary pack"
    "$root/scripts/romaji-dictionary.sh"
    ROMAJI_PACK="$root/.build/romaji-pack/trimmed"
    export ROMAJI_PACK
fi

echo "== Swift tests"
log="$TMPDIR/romaji-swift-test.log"
if (cd "$root" && swift test 2>&1) > "$log"; then
    grep -E "^(Renderer fixtures|Renderer fuzz|Reading fixture|Romaji results|Romaji private results)|Test run with" "$log"
else
    grep -E "✘|error:|Test run with" "$log" || tail -40 "$log"
    echo "Swift tests failed; the whole log is in $log"
    exit 1
fi

[ "$fast" = 1 ] && exit 0

echo "== Scorer"
status=0
python3 -I "$kit/tools/score_readings.py" "$TMPDIR/romaji-results.json" "$@" || status=$?

if [ -f "$kit/fixtures/private/songs.json" ] && [ -f "$TMPDIR/romaji-results-private.json" ]; then
    echo "== Scorer, private real-song set"
    if [ "$private_misses" = 1 ]; then
        python3 -I "$kit/tools/score_readings.py" "$TMPDIR/romaji-results-private.json" \
            --gold "$kit/fixtures/private/songs.json" "$@" || status=$?
    else
        python3 -I "$kit/tools/score_readings.py" "$TMPDIR/romaji-results-private.json" \
            --gold "$kit/fixtures/private/songs.json" "$@" | sed -n '1,/^Misses:/p' | sed '$d' || status=$?
    fi
fi
exit $status

#!/bin/sh
# the BASIC port against the C original: the bot's games and the random-input games
# on every table must give the same state hashes, step for step.
#   tools/check_trace.sh [games [steps]]      (default 8 games, to game over)
D=$(cd "$(dirname "$0")/.." && pwd)
BOING=${BOING:-$D/../../build/boing}
T=${TMPDIR:-/tmp}
"$D/tools/trace.sh" "${1:-8}" "${2:-72000}" > "$T/pb_c.txt" || exit 1
(cd "$D" && "$BOING" run Trace.bbp "${1:-8}" "${2:-72000}") > "$T/pb_bas.txt" 2>&1
if diff "$T/pb_c.txt" "$T/pb_bas.txt" > /dev/null; then
    echo "trace: same as the C ($(grep -c hash "$T/pb_c.txt") hashes)"
else
    diff "$T/pb_c.txt" "$T/pb_bas.txt" | head -20; echo "trace: DIFFERENT"; exit 1
fi

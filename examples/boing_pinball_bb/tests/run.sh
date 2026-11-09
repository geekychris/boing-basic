#!/bin/sh
# Boing Pinball's tests on the host (the Mac):
#  1. the BASIC rules give the C original's state hashes (tools/check_trace.sh: 24 bot games
#     to game over and 3 random-input games, on all three tables);
#  2. the form program and the benches compile;
#  3. the console bench, the bot playing each table with every frame drawn, gives the
#     expected state and picture hashes (tests/expected.txt; `tests/run.sh --update` rewrites it).
# Needs the pictures as PPM: python3 tools/make_art.py --ppm
D=$(cd "$(dirname "$0")/.." && pwd)
BOING=${BOING:-$D/../../build/boing}
cd "$D" || exit 1
fail=0
[ -f art/playfield_comet.ppm ] || python3 tools/make_art.py --ppm > /dev/null
tools/check_trace.sh || fail=1
for p in Pinball.bbp Bench.bbp Trace.bbp; do
    "$BOING" check $p || { echo "check $p: FAIL"; fail=1; }
done
out=$(for t in 0 1 2; do "$BOING" run Bench.bbp --frames 1500 --table $t | grep -E "^state|^picture" | sed "s/^/table $t: /"; done)
if [ "$1" = "--update" ]; then
    echo "$out" > tests/expected.txt; echo "bench: expected hashes written"
elif [ "$out" = "$(cat tests/expected.txt)" ]; then
    echo "bench: same state and picture hashes on all three tables"
else
    echo "bench: DIFFERENT"; echo "$out" | diff tests/expected.txt - ; fail=1
fi
[ $fail = 0 ] && echo PASS || echo FAIL
exit $fail

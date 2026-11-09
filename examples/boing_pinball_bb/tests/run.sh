#!/bin/sh
# Boing Pinball's tests on the host (the Mac):
#  1. the BASIC rules give the C original's state hashes (tools/check_trace.sh: 24 bot games
#     to game over and 3 random-input games, on all three tables);
#  2. the form program and the benches compile;
#  4. the form program on the headless forms backend: its --bench gives the console bench's
#     hashes, and the title (the demo, help, high scores) runs without an error;
#  3. the console bench, the bot playing each table with every frame drawn, gives the
#     expected state and picture hashes (tests/expected.txt; `tests/run.sh --update` rewrites it).
D=$(cd "$(dirname "$0")/.." && pwd)
BOING=${BOING:-$D/../../build/boing}
cd "$D" || exit 1
fail=0
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
want=$(grep "^table 0" tests/expected.txt | grep -o "hash [0-9A-F]*" | head -1)
got=$(BOING_HEADLESS=1 BOING_HEADLESS_SECS=60 "$BOING" run Pinball.bbp --bench 1500 < /dev/null 2>&1)
if echo "$got" | grep -q "$want" && echo "$got" | grep -q "$(grep "^table 0: picture" tests/expected.txt | sed 's/table 0: //')"; then
    echo "form: headless --bench gives the console bench's hashes"
else
    echo "form: headless --bench FAIL (want $want)"; echo "$got" | tail -4; fail=1
fi
for scr in title demo help1 help2 scores play; do
    t=$(BOING_HEADLESS=1 BOING_HEADLESS_SECS=2 "$BOING" run Pinball.bbp --screen $scr --log < /dev/null 2>&1; echo "exit $?")
    if echo "$t" | grep -qi "error" || ! echo "$t" | grep -q "exit 0"; then
        echo "form: headless --screen $scr FAIL"; echo "$t" | tail -3; fail=1
    fi
done
echo "form: headless screens ran"
t=$(BOING_HEADLESS=1 BOING_HEADLESS_SECS=30 "$BOING" run Pinball.bbp --script < /dev/null 2>&1)
if [ "$t" = "$(cat tests/script.out)" ]; then
    echo "form: the key script gives tests/script.out"
elif [ "$1" = "--update" ]; then
    echo "$t" > tests/script.out; echo "form: tests/script.out written"
else
    echo "form: the key script FAIL"; echo "$t" | diff tests/script.out -; fail=1
fi
[ $fail = 0 ] && echo PASS || echo FAIL
exit $fail

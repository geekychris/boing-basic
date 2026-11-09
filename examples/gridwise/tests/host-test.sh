#!/bin/sh
# Gridwise and Penwright, headless on the host (BOING_HEADLESS=1): the guest smoke scripts
# run through the real forms code-behind (menus, timers, canvas drawing), and the logs
# must end with "ok", hold the expected values and no errors. Called by make test.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BOING=$ROOT/build/boing
TMP=${TMPDIR:-/tmp}/office-host-test.$$
mkdir -p "$TMP"
fail=0
run() {   # dir project script expected...
    d=$1; p=$2; s=$3; shift 3
    log=$TMP/$p.log
    # in a copy of the example: the scripts save files (RAM:x on the host is a file name)
    mkdir -p "$TMP/work"
    cp -R "$ROOT/examples/$d" "$TMP/work/"
    ( cd "$TMP/work/$d" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=120 "$BOING" run "$p.bbp" --script "tests/$s" --log "$log" > "$TMP/$p.out" 2>&1 )
    ok=1
    [ "$(tail -1 "$log" 2>/dev/null)" = ok ] || ok=0
    grep -q "rc 10" "$log" 2>/dev/null && ok=0
    for e in "$@"; do grep -qF -- "$e" "$log" 2>/dev/null || { echo "  missing: $e"; ok=0; }; done
    if [ $ok = 1 ]; then echo "PASS office $p headless ($s)"; else echo "FAIL office $p headless ($s)"; cat "$TMP/$p.out"; fail=1; fi
}
run gridwise Gridwise smoke.gwr "GETCELL E8 -> 4,743.45" "GETCELL B11 -> 26.30%" "CHARTS -> 2"
run penwright Penwright smoke.pws "GETPARA 2 -> What it does" "SPELLNEXT -> thsi" "FIND rewriting -> 7 44"
rm -rf "$TMP"
exit $fail

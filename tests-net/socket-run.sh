#!/bin/sh
# tests-net/socket-run.sh BOING - Socket events in a form program on the host (headless forms),
# VM and native: tests-net/sockform. (tests/socket/ has the console tests, run by tests/run.sh.)
BOING=${1:-build/boing}
case $BOING in /*) ;; *) BOING=$(pwd)/$BOING ;; esac
root=$(cd "$(dirname "$0")/.." && pwd)
d=$root/tests-net/sockform
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rc=0
got=$(cd "$d" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=10 "$BOING" run sockform.bbp 2>&1)
if [ "$got" = "$(cat "$d/sockform.out")" ]; then echo "PASS net/sockform (vm)"; else echo "FAIL net/sockform (vm)"; echo "$got" | head -20; rc=1; fi
if "$BOING" build "$d/sockform.bbp" -o "$work/sockform" > "$work/build.txt" 2>&1; then
    got=$(cd "$d" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=10 "$work/sockform" 2>&1)
    if [ "$got" = "$(cat "$d/sockform.out")" ]; then echo "PASS net/sockform (native)"; else echo "FAIL net/sockform (native)"; echo "$got" | head -20; rc=1; fi
else
    echo "FAIL net/sockform (native build)"; cat "$work/build.txt"; rc=1
fi
got=$("$BOING" run "$root/tests-net/sockresolve.bas" 2>&1)
if [ "$got" = "$(cat "$root/tests-net/sockresolve.out")" ]; then echo "PASS net/sockresolve (vm)"; else echo "FAIL net/sockresolve: $got"; rc=1; fi
exit $rc

#!/bin/sh
# tests-net/run.sh BOING - the Http class tests on the host: starts tools/http_testserver.py,
# runs http.bas with `boing run` and as a native build, compares both with httptest.out.
BOING=${1:-build/boing}
case $BOING in /*) ;; *) BOING=$(pwd)/$BOING ;; esac
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
python3 "$root/tools/http_testserver.py" --ports-file "$work/ports" --certs "$root/build/net-certs" &
srv=$!
trap 'kill $srv 2>/dev/null; wait $srv 2>/dev/null; rm -rf "$work"' EXIT
i=0; while [ ! -s "$work/ports" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
[ -s "$work/ports" ] || { echo "FAIL net: the test server didn't start"; exit 1; }
set -- $(cat "$work/ports") ; hp=$1 sp=$2 ca=$3
args="http://127.0.0.1:$hp https://localhost:$sp $ca"
cd "$work" || exit 1
rc=0
for t in httptest asynctest sessiontest asyncexit; do
    "$BOING" run "$root/tests-net/$t.bas" $args > vm.txt 2>&1
    if diff "$root/tests-net/$t.out" vm.txt >/dev/null; then echo "PASS net/$t (vm)"; else echo "FAIL net/$t (vm)"; diff "$root/tests-net/$t.out" vm.txt | head -20; rc=1; fi
    if "$BOING" build "$root/tests-net/$t.bas" -o "$work/${t}_native" > build.txt 2>&1; then
        "$work/${t}_native" $args > nat.txt 2>&1
        if diff "$root/tests-net/$t.out" nat.txt >/dev/null; then echo "PASS net/$t (native)"; else echo "FAIL net/$t (native)"; diff "$root/tests-net/$t.out" nat.txt | head -20; rc=1; fi
    else
        echo "FAIL net/$t (native build)"; cat build.txt; rc=1
    fi
done
exit $rc

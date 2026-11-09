#!/bin/sh
# command-line behaviour (make test): `boing run` from another directory; App.Path is the
# program's directory (VM, .bbc) and the executable's (native). Usage: sh tests/cli/run.sh BOING
B=${1:-build/boing}; d=$(cd "$(dirname "$0")" && pwd); tmp=${TMP:-/tmp}/bb-cli.$$
mkdir -p "$tmp"; fail=0
want=$(printf 'dir apppath\ndata beside the program')
check() { if [ "$2" = "$want" ]; then :; else echo "FAIL cli $1:"; echo "$2"; fail=1; fi; }
check "run .bas" "$(cd "$tmp" && "$B" run "$d/apppath/apppath.bas" 2>&1)"
check "run relative" "$(cd "$d" && "$B" run apppath/apppath.bas 2>&1)"
"$B" compile "$d/apppath/apppath.bas" -o "$d/apppath/apppath.bbc" >/dev/null 2>&1
check "run .bbc" "$(cd "$tmp" && "$B" run "$d/apppath/apppath.bbc" 2>&1)"
rm -f "$d/apppath/apppath.bbc"
if "$B" build "$d/apppath/apppath.bas" -o "$d/apppath/apppath.exe" >/dev/null 2>&1; then
    check "native" "$(cd "$tmp" && "$d/apppath/apppath.exe" 2>&1)"
    rm -f "$d/apppath/apppath.exe"
else echo "FAIL cli native (build)"; fail=1; fi
# a form Timer keeps its period when its handler is slow (headless forms, VM and native)
for mode in vm nat; do
    if [ $mode = vm ]; then got=$(cd "$d/timer" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=5 "$B" run timer.bbp 2>&1)
    else "$B" build "$d/timer/timer.bbp" -o "$tmp/timer" >/dev/null 2>&1 && got=$(cd "$d/timer" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=5 "$tmp/timer" 2>&1); fi
    [ "$got" = "ticks ok" ] || { echo "FAIL cli timer ($mode): $got"; fail=1; }
done
# the JIT's decision is logged once with -v (on, off with the reason, or forced), never without
n=$(cd "$d/apppath" && "$B" run --jit -v apppath.bas 2>&1 >/dev/null | grep -c '^jit: ')
[ "$n" = 1 ] || { echo "FAIL cli jit -v: $n decision lines"; fail=1; }
n=$(cd "$d/apppath" && "$B" run --jit-force -v apppath.bas 2>&1 >/dev/null | grep -c '^jit: on (.*forced)')
[ "$n" = 1 ] || { echo "FAIL cli jit-force -v: $n lines"; fail=1; }
n=$(cd "$d/apppath" && "$B" run --jit apppath.bas 2>&1 >/dev/null | grep -c '^jit: ')
[ "$n" = 0 ] || { echo "FAIL cli jit without -v logged"; fail=1; }
rm -rf "$tmp"
echo "cli tests: $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail

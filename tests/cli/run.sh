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
rm -rf "$tmp"
echo "cli tests: $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail

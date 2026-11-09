#!/bin/sh
# Ctrl-C tests (make test): each program loops until it gets SIGINT; checks error 18 with a
# handler, "***Break" + exit 20 without, and On Error Resume Next not swallowing it.
# In the VM, with the JIT and native. Usage: sh tests/break/run.sh BOING
B=${1:-build/boing}; d=$(cd "$(dirname "$0")" && pwd); tmp=${TMP:-/tmp}/bb-break.$$
mkdir -p "$tmp"; fail=0; n=0
expect() {  # name expected-output-file-content
    case $1 in handler) printf 'running\ncleanup 18 User interrupt occurred\nrc=0\n' ;;
    nohandler) printf 'running\nnohandler.bas:5: ***Break\nrc=20\n' ;;
    resumenext) printf 'running\nouter caught 18 \nrc=0\n' ;; esac
}
for t in handler nohandler resumenext; do
    (cd "$d" && "$B" build $t.bas -o "$tmp/$t" >/dev/null 2>&1) || { echo "FAIL break $t (build)"; fail=1; continue; }
    for mode in vm jit nat; do
        n=$((n + 1))
        case $mode in
        vm) (cd "$d" && exec "$B" run $t.bas) > "$tmp/out" 2>&1 & ;;
        jit) (cd "$d" && BOING_JIT=1 exec "$B" run $t.bas) > "$tmp/out" 2>&1 & ;;
        nat) (cd "$d" && exec "$tmp/$t") > "$tmp/out" 2>&1 & ;;
        esac
        p=$!
        i=0; while [ $i -lt 50 ] && ! grep -q running "$tmp/out" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
        sleep 0.2; kill -INT $p; wait $p; echo "rc=$?" >> "$tmp/out"
        if [ "$(cat "$tmp/out")" = "$(expect $t)" ]; then :; else echo "FAIL break $t ($mode)"; cat "$tmp/out"; fail=1; fi
    done
done
rm -rf "$tmp"
echo "break tests: $n run, $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail

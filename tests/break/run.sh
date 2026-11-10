#!/bin/sh
# Ctrl-C tests (make test): each program loops until it gets SIGINT; checks error 18 with a
# handler, "***Break" + exit 20 without, and On Error Resume Next not swallowing it.
# In the VM, with the JIT and native. Usage: sh tests/break/run.sh BOING
B=${1:-build/boing}; d=$(cd "$(dirname "$0")" && pwd); tmp=${TMP:-/tmp}/bb-break.$$
mkdir -p "$tmp"; fail=0; n=0
expect() {  # name expected-output-file-content
    case $1 in handler) printf 'running\ncleanup 18 User interrupt occurred\nrc=0\n' ;;
    nohandler) printf 'running\nnohandler.bas:5: ***Break\nrc=20\n' ;;
    resumenext) printf 'running\nouter caught 18 \nrc=0\n' ;;
    waiting) printf 'running\ncleanup 18 User interrupt occurred\nrc=0\n' ;; esac
}
for t in handler nohandler resumenext waiting; do
    (cd "$d" && "$B" build $t.bas -o "$tmp/$t" >/dev/null 2>&1) || { echo "FAIL break $t (build)"; fail=1; continue; }
    for mode in vm jit nat; do
        n=$((n + 1))
        # a fresh output file per run: with one shared file, "running" from the previous run could
        # be seen before the background shell had truncated it, and the SIGINT then arrived before
        # the exec, while the async shell still ignored SIGINT: lost, and the program looped forever
        out=$tmp/out.$t.$mode; rm -f "$out"
        case $mode in
        vm) (cd "$d" && exec "$B" run $t.bas) > "$out" 2>&1 & ;;
        jit) (cd "$d" && BOING_JIT=1 exec "$B" run $t.bas) > "$out" 2>&1 & ;;
        nat) (cd "$d" && exec "$tmp/$t") > "$out" 2>&1 & ;;
        esac
        p=$!
        i=0; while [ $i -lt 100 ] && ! grep -q running "$out" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
        sleep 0.2; kill -INT $p 2>/dev/null
        # it must end: SIGINT again every 2 s if it hasn't (counted as a failure), killed after 30 s
        i=0; resent=0
        while kill -0 $p 2>/dev/null && [ $i -lt 300 ]; do
            sleep 0.1; i=$((i + 1))
            if [ $((i % 20)) = 0 ] && kill -0 $p 2>/dev/null; then kill -INT $p 2>/dev/null; resent=$((resent + 1)); fi
        done
        if kill -0 $p 2>/dev/null; then kill -KILL $p 2>/dev/null; echo "FAIL break $t ($mode): no exit 30 s after SIGINT"; fail=1; fi
        wait $p; echo "rc=$?" >> "$out"
        [ $resent = 0 ] || { echo "FAIL break $t ($mode): the first SIGINT was missed ($resent more sent)"; fail=1; }
        if [ "$(cat "$out")" = "$(expect $t)" ]; then :; else echo "FAIL break $t ($mode)"; cat "$out"; fail=1; fi
    done
done
rm -rf "$tmp"
echo "break tests: $n run, $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail

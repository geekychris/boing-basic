#!/bin/sh
# os4-core-tests.sh [pattern] - run the single-file language tests (tests/*/*.bas with .out)
# through the cross-built boing (build/os4/boing, from tools/build-os4.sh) in the VM on the
# QEMU OS4 guest, via tools/os4guest.py (emulator lock + banner). Compares the output with
# the .out file. Skips projects (*.bbp dirs), compile-error tests, and tests that write files
# outside their directory. RUNFLAGS=--jit runs them with the PowerPC JIT.
root=$(cd "$(dirname "$0")/.." && pwd)
g="python3 $root/tools/os4guest.py"
[ -f "$root/build/os4/boing" ] || { echo "build/os4/boing missing: run tools/build-os4.sh" >&2; exit 10; }
$g push "$root/build/os4/boing" RAM:bbcore/boing || exit 20
pass=0 fail=0
for f in $(cd "$root/tests" && ls */*.bas | grep -v '^errors/\|^break/' | grep -e "${1:-}"); do
    d=$(dirname "$f"); b=$(basename "$f" .bas)
    ls "$root/tests/$d"/*.bbp >/dev/null 2>&1 && continue
    files="$root/tests/$f RAM:bbcore/$b.bas"
    in=""
    [ -f "$root/tests/$d/$b.in" ] && { files="$files $root/tests/$d/$b.in RAM:bbcore/$b.in"; in=" <$b.in"; }
    $g push $files >/dev/null || { echo "FAIL $f (push)"; fail=$((fail+1)); continue; }
    got=$($g dos "cd RAM:bbcore
boing run ${RUNFLAGS:-} $b.bas$in" 2>&1)
    if [ "$got" = "$(cat "$root/tests/$d/$b.out")" ]; then pass=$((pass+1)); echo "PASS $f"
    else fail=$((fail+1)); echo "FAIL $f"; printf '%s\n' "$got" | diff "$root/tests/$d/$b.out" - | head -10; fi
done
echo "os4 core tests: $pass passed, $fail failed"

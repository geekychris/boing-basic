#!/bin/sh
# Riffwright host tests: every tests/*.bbp through the VM, the VM with the JIT on, and a
# native build; each must print exactly its .out file. Usage: sh run.sh [boing]
cd "$(dirname "$0")" || exit 1
BOING=${1:-${BOING:-../../../build/boing}}
TMP=${TMP:-/tmp/riffwright-tests.$$}
mkdir -p "$TMP"
pass=0; fail=0
for p in *.bbp; do
    t=${p%.bbp}
    for mode in vm jit native; do
        case $mode in
            vm) "$BOING" run "$p" > "$TMP/$t.$mode" 2>&1 ;;
            jit) BOING_JIT=1 BOING_JIT_THRESHOLD=1 "$BOING" run "$p" > "$TMP/$t.$mode" 2>&1 ;;
            native) if "$BOING" build "$p" -o "$TMP/$t.bin" > "$TMP/$t.cc" 2>&1; then
                        "$TMP/$t.bin" > "$TMP/$t.$mode" 2>&1
                    else cp "$TMP/$t.cc" "$TMP/$t.$mode"; fi ;;
        esac
        if cmp -s "$TMP/$t.$mode" "$t.out"; then pass=$((pass + 1))
        else fail=$((fail + 1)); echo "FAIL riffwright $t ($mode)"; diff "$t.out" "$TMP/$t.$mode" | head -10; fi
    done
done
rm -rf "$TMP"
echo "riffwright tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/bin/sh
# Tincture host test (make test): the document model, tools, undo/redo, file round trips and
# the ARexx command language, off-screen, in the VM and as a native build.
dir=$(cd "$(dirname "$0")" && pwd); root=$(cd "$dir/../../.." && pwd)
BOING=${BOING:-$root/build/boing}
work=$root/build/tests/tincture; rm -rf "$work"; mkdir -p "$work"
cd "$dir" || exit 1
fail=0
( cd "$work" && "$BOING" run "$dir/ModelTest.bbp" < /dev/null > vm.txt 2>&1 )
tail -1 "$work/vm.txt" | grep -qx PASS || { echo "FAIL tincture model (VM)"; grep -v '^ok' "$work/vm.txt"; fail=1; }
if [ "${NATIVE:-1}" = 1 ]; then
    "$BOING" build "$dir/ModelTest.bbp" -o "$work/mt" > "$work/build.txt" 2>&1 || { echo "FAIL tincture model (build)"; cat "$work/build.txt"; exit 1; }
    ( cd "$work" && ./mt > native.txt 2>&1 )
    tail -1 "$work/native.txt" | grep -qx PASS || { echo "FAIL tincture model (native)"; grep -v '^ok' "$work/native.txt"; fail=1; }
fi
# the whole program, GUI included, on the headless forms backend: --smoke drives every tool
# through the real event handlers, undoes everything (hash back to the blank picture) and quits
( cd "$work" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=20 "$BOING" run "$dir/../Tincture.bbp" --smoke < /dev/null > smoke_vm.txt 2>&1 )
grep -q "SMOKE undo-all PASS" "$work/smoke_vm.txt" || { echo "FAIL tincture --smoke (VM, headless)"; tail -5 "$work/smoke_vm.txt"; fail=1; }
if [ "${NATIVE:-1}" = 1 ]; then
    "$BOING" build "$dir/../Tincture.bbp" -o "$work/Tincture" > "$work/build2.txt" 2>&1 || { echo "FAIL tincture (native build)"; cat "$work/build2.txt"; exit 1; }
    ( cd "$work" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=20 ./Tincture --smoke < /dev/null > smoke_native.txt 2>&1 )
    grep -q "SMOKE undo-all PASS" "$work/smoke_native.txt" || { echo "FAIL tincture --smoke (native, headless)"; tail -5 "$work/smoke_native.txt"; fail=1; }
fi
[ $fail = 0 ] && echo "tincture: model test and headless --smoke passed (VM$( [ "${NATIVE:-1}" = 1 ] && echo ' + native'))"
exit $fail

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
[ $fail = 0 ] && echo "tincture: model test passed (VM$( [ "${NATIVE:-1}" = 1 ] && echo ' + native'))"
exit $fail

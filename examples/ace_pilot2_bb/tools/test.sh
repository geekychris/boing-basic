#!/bin/sh
# Ace Pilot 2's rules on the host (make test): Trace.bbp in the VM, the VM with every loop
# JIT-compiled, and native must print tests/trace.out, which is the C original's output
# (tools/trace.sh; it is also compared when amiga_mcp is checked out beside boing_basic).
D=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(cd "$D/../.." && pwd)
BOING=${BOING:-$ROOT/build/boing}; T=${TMP:-$ROOT/build/tests}; mkdir -p "$T"
fail=0
check() { if cmp -s "$D/tests/trace.out" "$T/ap_$1.txt"; then echo "PASS ace_pilot2 $1"; else echo "FAIL ace_pilot2 $1"; diff "$D/tests/trace.out" "$T/ap_$1.txt" | head -5; fail=1; fi; }
( cd "$D" && "$BOING" run Trace.bbp > "$T/ap_vm.txt" 2>&1 ); check vm
( cd "$D" && BOING_JIT=1 BOING_JIT_THRESHOLD=1 "$BOING" run Trace.bbp > "$T/ap_jit.txt" 2>&1 ); check jit
if [ "${NATIVE:-1}" = 1 ]; then
    ( cd "$D" && "$BOING" build Trace.bbp -o "$T/ap_trace_bb" > "$T/ap_cc.txt" 2>&1 && "$T/ap_trace_bb" > "$T/ap_native.txt" 2>&1 ); check native
fi
M=$(cd "$ROOT/.." && pwd)/amiga_mcp
if [ -f "$M/examples/ace_pilot2/ap_core.c" ]; then
    TMPDIR="$T" AMIGA_MCP="$M" sh "$D/tools/trace.sh" > "$T/ap_c-original.txt" 2>&1; check c-original
fi
exit $fail

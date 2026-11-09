#!/bin/sh
# ScAIry Fun's rules on the host (make test): Trace.bbp in the VM, the VM with every loop
# JIT-compiled, and native must print tests/trace.out, which is the C original's output
# (tools/trace.sh; it is also compared when amiga_mcp is checked out beside boing_basic).
D=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(cd "$D/../.." && pwd)
BOING=${BOING:-$ROOT/build/boing}; T=${TMP:-$ROOT/build/tests}; mkdir -p "$T"
fail=0
check() { if cmp -s "$D/tests/trace.out" "$T/sc_$1.txt"; then echo "PASS scairy_fun $1"; else echo "FAIL scairy_fun $1"; diff "$D/tests/trace.out" "$T/sc_$1.txt" | head -5; fail=1; fi; }
( cd "$D" && "$BOING" run Trace.bbp > "$T/sc_vm.txt" 2>&1 ); check vm
( cd "$D" && BOING_JIT=1 BOING_JIT_THRESHOLD=1 "$BOING" run Trace.bbp > "$T/sc_jit.txt" 2>&1 ); check jit
if [ "${NATIVE:-1}" = 1 ]; then
    ( cd "$D" && "$BOING" build Trace.bbp -o "$T/sc_trace_bb" > "$T/sc_cc.txt" 2>&1 && "$T/sc_trace_bb" > "$T/sc_native.txt" 2>&1 ); check native
fi
M=$(cd "$ROOT/.." && pwd)/amiga_mcp
if [ -f "$M/examples/scairy_fun/world.c" ]; then
    TMPDIR="$T" AMIGA_MCP="$M" sh "$D/tools/trace.sh" > "$T/sc_c-original.txt" 2>&1; check c-original
fi
exit $fail

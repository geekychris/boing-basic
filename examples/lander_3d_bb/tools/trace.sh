#!/bin/sh
# build and run the C original's trace (needs amiga_mcp checked out beside boing_basic, or AMIGA_MCP=...)
M=${AMIGA_MCP:-$(cd "$(dirname "$0")/../../../.." && pwd)/amiga_mcp}
A=$M/examples/amiga3d; L=$M/examples/lander_3d
OUT=${TMPDIR:-/tmp}/ld_trace
cc -O2 -I"$A" -I"$L" -o "$OUT" "$(dirname "$0")/trace.c" "$L/ld_core.c" "$A/a3d_math.c" "$A/a3d_fix.c" && "$OUT"

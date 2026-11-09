#!/bin/sh
# build and run the C original's trace (needs amiga_mcp checked out beside boing_basic, or AMIGA_MCP=...)
M=${AMIGA_MCP:-$(cd "$(dirname "$0")/../../../.." && pwd)/amiga_mcp}
A=$M/examples/amiga3d; T=$M/examples/stack_tower
cc -O2 -I"$A" -I"$T" -I"$T/tests" -o "${TMPDIR:-/tmp}/st_trace" "$(dirname "$0")/trace.c" "$T/st_core.c" "$A/a3d_math.c" && "${TMPDIR:-/tmp}/st_trace"

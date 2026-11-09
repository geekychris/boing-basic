#!/bin/sh
# build and run the C original's trace (needs amiga_mcp checked out beside boing_basic, or AMIGA_MCP=...)
M=${AMIGA_MCP:-$(cd "$(dirname "$0")/../../../.." && pwd)/amiga_mcp}
A=$M/examples/amiga3d; T=$M/examples/orbit_docking
cc -O2 -I"$A" -I"$T" -I"$T/tests" -o "${TMPDIR:-/tmp}/od_trace" "$(dirname "$0")/trace.c" "$T/od_core.c" "$A/a3d_math.c" "$A/a3d_fix.c" && "${TMPDIR:-/tmp}/od_trace"

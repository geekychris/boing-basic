#!/bin/sh
# build and run the C original's trace (needs amiga_mcp checked out beside boing_basic, or AMIGA_MCP=...)
#   tools/trace.sh [games [steps]]
M=${AMIGA_MCP:-$(cd "$(dirname "$0")/../../../.." && pwd)/amiga_mcp}
A=$M/examples/amiga3d; P=$M/examples/boing_pinball
cc -O2 -include stdlib.h -I"$A" -I"$P" -o /tmp/pb_trace "$(dirname "$0")/trace.c" "$P/pb_core.c" "$P/pb_tables.c" "$A/a3d_math.c" "$A/a3d_fix.c" && /tmp/pb_trace "$@"

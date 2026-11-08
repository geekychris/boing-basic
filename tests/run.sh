#!/bin/sh
# Boing BASIC test runner (make test).
#   tests/<group>/<name>.bas   program; expected output in <name>.out, optional stdin <name>.in.
#                              Runs through the VM (boing run) and native (boing build + host cc);
#                              both must produce exactly <name>.out.
#   tests/errors/<name>.bas    compile errors: `boing check` output must equal <name>.err.
# Compared output is stdout + stderr; a non-zero exit code is appended as "[exit N]".
# Usage: sh tests/run.sh [grep-pattern]   env: JOBS (default 4), NATIVE=0 skips native builds
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOING="$ROOT/build/boing"; TMP="$ROOT/build/tests"; NATIVE=${NATIVE:-1}
export BOING TMP NATIVE
mkdir -p "$TMP"; rm -f "$TMP"/*.result "$TMP"/*.diff
find "$ROOT/tests" -name '*.bas' | sort | grep -e "${1:-}" | xargs -P "${JOBS:-4}" -n 1 sh "$ROOT/tests/run1.sh"
pass=$(cat "$TMP"/*.result 2>/dev/null | grep -c '^PASS')
fail=$(cat "$TMP"/*.result 2>/dev/null | grep -c '^FAIL')
cat "$TMP"/*.result 2>/dev/null | grep '^FAIL' | sort
echo "tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

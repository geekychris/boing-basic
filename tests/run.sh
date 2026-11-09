#!/bin/sh
# Boing BASIC test runner (make test).
#   tests/<group>/<name>.bas   program; expected output in <name>.out, optional stdin <name>.in.
#                              Runs through the VM (boing run) and native (boing build + host cc);
#                              both must produce exactly <name>.out.
#   tests/<group>/<proj>/<proj>.bbp  a multi-file project (modules, classes, forms), same rules
#   tests/errors/<name>.bas    compile errors: `boing check` output must equal <name>.err.
#   tests/break/               Ctrl-C tests, run by tests/break/run.sh (they loop until SIGINT)
# Compared output is stdout + stderr; a non-zero exit code is appended as "[exit N]".
# Usage: sh tests/run.sh [grep-pattern]   env: JOBS (default 4), NATIVE=0 skips native builds
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOING=${BOING:-$ROOT/build/boing}; TMP=${TMP:-$ROOT/build/tests}; NATIVE=${NATIVE:-1}
BOING_SETTINGS=${BOING_SETTINGS:-$TMP/settings}   # GetSetting/SaveSetting stay out of $HOME
export BOING TMP NATIVE BOING_SETTINGS
mkdir -p "$TMP"; rm -f "$TMP"/*.result "$TMP"/*.diff
# tests: every .bbp, and every .bas that is not part of a project directory
{ find "$ROOT/tests" -name '*.bbp'
  find "$ROOT/tests" -name '*.bas' | while read -r f; do ls "$(dirname "$f")"/*.bbp >/dev/null 2>&1 || echo "$f"; done
} | grep -v '/tests/break/' | sort | grep -e "${1:-}" | xargs -P "${JOBS:-4}" -n 1 sh "$ROOT/tests/run1.sh"
pass=$(cat "$TMP"/*.result 2>/dev/null | grep -c '^PASS')
fail=$(cat "$TMP"/*.result 2>/dev/null | grep -c '^FAIL')
cat "$TMP"/*.result 2>/dev/null | grep '^FAIL' | sort
echo "tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/bin/sh
# os4-build-check.sh - part of `make test`: cross-build boing and libboing.a for AmigaOS 4 when
# Docker is reachable (an OS4-only compile error must not reach main), else warn and skip.
# Set OS4_CHECK=0 to skip on purpose.
root=$(cd "$(dirname "$0")/.." && pwd)
[ "${OS4_CHECK:-1}" = 0 ] && { echo "os4 build check: skipped (OS4_CHECK=0)"; exit 0; }
if ! docker info >/dev/null 2>&1; then
    echo "os4 build check: WARNING: Docker not reachable, OS4 cross build not checked" >&2
    exit 0
fi
log=$(mktemp "${TMPDIR:-/tmp}/bbos4.XXXXXX")
if sh "$root/tools/build-os4.sh" check-cpu >"$log" 2>&1; then
    grep -q "dlmzb=[1-9]" "$log" && { cat "$log" >&2; echo "os4 build check: 440-only instructions" >&2; rm -f "$log"; exit 1; }
    echo "os4 build check: OK"
    rm -f "$log"
    exit 0
fi
grep -E "error|Error" "$log" | head -20 >&2
echo "os4 build check: FAILED (full log: $log)" >&2
exit 1

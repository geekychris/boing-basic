#!/bin/sh
# os4-check.sh - the OS4 checks that need no guest: cross build with the dlmzb check, then the
# binding proof (tools/bindproof: every slot and constant of bindings/*.bi against the SDK).
# Fails if either fails, so a genbind regression breaks it.
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/tools/build-os4.sh" check-cpu >/dev/null || { echo "os4-check: cross build / dlmzb check FAILED"; exit 1; }
"$root/tools/bindproof" | grep -E "^(bindproof|compiled|NO SUCH|ASSERTION|ARGC|HEADER|SDK XML)" || true
"$root/tools/bindproof" >/dev/null && echo "os4-check: PASS" || { echo "os4-check: bindproof FAILED"; exit 1; }

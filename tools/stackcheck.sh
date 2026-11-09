#!/bin/sh
# stackcheck.sh - fail if a function needs a big stack frame. AmigaOS 4 runs commands on as
# little as 64 KB of stack (the $STACK cookie is not always honoured), so nothing outside the
# host-only posix layer may use more than LIMIT bytes (a 112 KB frame in main once corrupted
# memory on every run on the guest).
root=$(cd "$(dirname "$0")/.." && pwd)
LIMIT=${LIMIT:-16384}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/bbstack.XXXXXX") || exit 1
bad=0
for f in "$root"/src/runtime/*.c "$root"/src/runtime/a3d/*.c "$root"/src/compiler/*.c "$root"/src/vm/*.c "$root"/src/main/*.c; do
    o="$tmp/$(basename "$f" .c).o"
    ${CC:-cc} -std=gnu99 -O2 -fstack-usage -I"$root/src" -I"$root/src/runtime" -c "$f" -o "$o" 2>/dev/null || continue
done
for su in "$tmp"/*.su; do
    awk -F'\t' -v lim="$LIMIT" '$2 + 0 > lim { print "stack frame too big: " $1 " " $2 " bytes"; bad = 1 } END { exit bad }' "$su" || bad=1
done
rm -rf "$tmp"
[ $bad -eq 0 ] && echo "stack check: no frame over $LIMIT bytes"
exit $bad

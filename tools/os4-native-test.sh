#!/bin/sh
# os4-native-test.sh TEST.c [...] - compile C tests ON the AmigaOS 4 guest with the SDK's
# native GCC (SDK:gcc/bin/gcc, as `boing build` does there) against build/os4/libboing.a,
# then run each one. Everything goes to RAM:boing (DH1 is nearly full). Exit 1 if any FAILs.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
G="$root/tools/os4guest.py"
[ -f "$root/build/os4/libboing.a" ] || "$root/tools/build-os4.sh" build/os4/libboing.a >/dev/null
export BB_BANNER=${BB_BANNER:-1}
# compiling on the guest is this script's job: os4guest.py allows it only when asked for, with a
# hard limit per build (GCC there ignores Ctrl-C)
export BB_GUEST_BUILD=1 BB_GUEST_BUILD_LIMIT=${BB_GUEST_BUILD_LIMIT:-600}
"$G" dos 'makedir RAM:boing RAM:boing/include RAM:boing/lib RAM:boing/t' >/dev/null 2>&1 || true
set -- "$@"
args="$root/build/os4/libboing.a RAM:boing/lib/libboing.a"
for h in "$root"/src/runtime/*.h; do args="$args $h RAM:boing/include/$(basename "$h")"; done
for t in "$@"; do args="$args $t RAM:boing/t/$(basename "$t")"; done
"$G" push $args >/dev/null
fail=0
for t in "$@"; do
    b=$(basename "$t" .c)
    echo "== $b (native SDK gcc)"
    "$G" dos "SDK:gcc/bin/gcc -mcrt=newlib -O2 -mcpu=powerpc -Wall -D__USE_OLD_TIMEVAL__ -DBB_PLATFORM_OS4 -IRAM:boing/include -o RAM:boing/t/$b RAM:boing/t/$b.c RAM:boing/lib/libboing.a -lauto -lm"
    out=$("$G" dos "RAM:boing/t/$b")
    echo "$out" | tail -3
    echo "$out" | grep -q PASS || fail=1
done
exit $fail

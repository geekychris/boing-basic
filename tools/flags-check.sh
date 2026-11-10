#!/bin/sh
# flags-check.sh (make test): objects rebuild when the build flags change. Builds libboing into
# build/flagscheck at -O0 (fast), checks that a second make rebuilds nothing and that a make
# with a different CFLAGS rebuilds every object.
cd "$(dirname "$0")/.." || exit 1
B=build/flagscheck
make -s -j4 B=$B CFLAGS=-O0 $B/libboing.a >/dev/null 2>&1 || { echo "flags check: build failed"; exit 1; }
# the runtime's sources now (objects of files that exist no more, e.g. from another branch, ignored)
objs=$(ls src/runtime/*.c src/runtime/a3d/*.c src/runtime/audio/*.c src/runtime/posix/*.c | sed "s#^src/#$B/obj/#; s#\.c\$#.o#")
n=$(echo "$objs" | wc -l | tr -d ' ')
touch $B/.mark; sleep 1
make -s -j4 B=$B CFLAGS=-O0 $B/libboing.a >/dev/null 2>&1
a=$(for o in $objs; do [ "$o" -nt $B/.mark ] && echo x; done | wc -l | tr -d ' ')
make -s -j4 B=$B "CFLAGS=-O0 -DBB_FLAGS_CHECK" $B/libboing.a >/dev/null 2>&1
b=$(for o in $objs; do [ "$o" -nt $B/.mark ] && echo x; done | wc -l | tr -d ' ')
make -s -j4 B=$B CFLAGS=-O0 $B/libboing.a >/dev/null 2>&1
if [ "$a" -eq 0 ] && [ "$b" -eq "$n" ]; then echo "flags check: OK"; exit 0; fi
echo "flags check: FAIL (same flags rebuilt $a objects; changed flags rebuilt $b of $n)"
exit 1

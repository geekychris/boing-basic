#!/bin/sh
# run one test (see tests/run.sh); env BOING, TMP, NATIVE
f="$1"
dir=$(dirname "$f"); base=$(basename "$f" .bas); group=$(basename "$dir")
id="$group-$base"
res="$TMP/$id.result"
cd "$dir" || exit 1
if [ "$group" = errors ]; then
    "$BOING" check "$base.bas" > "$TMP/$id.got" 2>&1
    if cmp -s "$TMP/$id.got" "$base.err"; then echo "PASS $id" > "$res"
    else echo "FAIL $id (check)" > "$res"; diff "$base.err" "$TMP/$id.got" > "$TMP/$id.diff"; fi
    exit 0
fi
input=/dev/null
[ -f "$base.in" ] && input="$PWD/$base.in"
work="$TMP/$id.work"
rm -rf "$work"; mkdir -p "$work"; cp -R ./ "$work/" 2>/dev/null
( cd "$work" && "$BOING" run "$base.bas" < "$input" > "$TMP/$id.vm" 2>&1; rc=$?; [ $rc -ne 0 ] && echo "[exit $rc]" >> "$TMP/$id.vm" )
vm=ok
cmp -s "$TMP/$id.vm" "$base.out" || { vm=bad; diff "$base.out" "$TMP/$id.vm" > "$TMP/$id.vm.diff"; }
nat=ok
if [ "$NATIVE" = 1 ]; then
    rm -rf "$work"; mkdir -p "$work"; cp -R ./ "$work/" 2>/dev/null
    if ( cd "$work" && "$BOING" build "$base.bas" -o "$TMP/$id.bin" > "$TMP/$id.cc" 2>&1 ); then
        ( cd "$work" && "$TMP/$id.bin" < "$input" > "$TMP/$id.nat" 2>&1; rc=$?; [ $rc -ne 0 ] && echo "[exit $rc]" >> "$TMP/$id.nat" )
        cmp -s "$TMP/$id.nat" "$base.out" || { nat=bad; diff "$base.out" "$TMP/$id.nat" > "$TMP/$id.nat.diff"; }
    else nat=build; fi
fi
rm -rf "$work"
if [ $vm = ok ] && [ $nat = ok ]; then echo "PASS $id" > "$res"
else echo "FAIL $id (vm=$vm native=$nat)" > "$res"; fi

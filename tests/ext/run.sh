#!/bin/sh
# linked extensions (make test, docs/extensions.md): the C and C++ samples and a CSource= with
# Declare ... Lib "C", natively and through a `boing vm` interpreter; plain `boing run` reports a
# missing extension / function; the compiler checks members and arguments against the .bbx.
# Usage: sh tests/ext/run.sh BOING
B=${1:-build/boing}; root=$(cd "$(dirname "$0")/../.." && pwd); tmp=${TMP:-/tmp}/bb-ext.$$
mkdir -p "$tmp"; fail=0
check() {  # name got want
    if [ "$2" = "$3" ]; then :; else echo "FAIL ext $1"; echo "--- want"; echo "$3"; echo "--- got"; echo "$2"; fail=1; fi
}
counter=$(printf 'value 55 count 10 \nset 100 Counter\nreset 0  0 \nclamp 10  0  7 ')
shapes=$(printf 'area 42  6x7\ndefault 1  1x1\ngcd 12  6 ')
clib=$(printf ' 20  25  5 positive not positive')
asnew=$(printf 'auto 5  5  2 \nrenew 1 Counter\nfield 9 ')
events=$(printf 'tick 1 tick 2 tick 3 | done, total 6 \nwatcher done 2 \nruns 2 ')
for t in "examples/ext_counter/demo.bbp:counter" "examples/ext_shapes/demo.bbp:shapes" "tests/ext/clib/clib.bbp:clib" "tests/ext/asnew/asnew.bbp:asnew" "tests/ext/events/events.bbp:events"; do
    proj=${t%%:*}; name=${t##*:}; d=$(dirname "$root/$proj"); f=$(basename "$proj")
    eval want=\$$name
    if (cd "$d" && "$B" build "$f" -o "$tmp/$name.nat" >/dev/null 2>&1); then check "$name native" "$(cd "$d" && "$tmp/$name.nat" 2>&1)" "$want"
    else echo "FAIL ext $name native (build)"; fail=1; fi
    if (cd "$d" && "$B" vm --project "$f" -o "$tmp/$name.vm" >/dev/null 2>&1); then
        check "$name vm" "$(cd "$d" && "$tmp/$name.vm" run "$f" 2>&1)" "$want"
        check "$name vm jit" "$(cd "$d" && BOING_JIT=1 BOING_JIT_THRESHOLD=1 "$tmp/$name.vm" run "$f" 2>&1)" "$want"
    else echo "FAIL ext $name vm (boing vm)"; fail=1; fi
done
# the plain interpreter: a missing extension stops before running; a missing C function is 453
got=$(cd "$root/examples/ext_counter" && "$B" run demo.bbp 2>&1; echo "rc=$?")
case $got in *"needs the extension 'counter', which is not linked"*"rc=20") ;; *) echo "FAIL ext missing extension: $got"; fail=1 ;; esac
got=$(cd "$root/tests/ext/clib" && "$B" run clib.bbp 2>&1; echo "rc=$?")
case $got in *"runtime error 453: function 'AddMul' is not linked"*"rc=20") ;; *) echo "FAIL ext missing C function: $got"; fail=1 ;; esac
# compile-time checks against the .bbx
got=$(cd "$root/tests/ext/bad" && "$B" check bad.bbp 2>&1)
want=$(printf "bad.bas:4:7: error: 'Ad' is not a member of Counter\nbad.bas:5:7: error: Counter.Count is read-only\nbad.bas:6:9: error: 'Clamp' takes 3 arguments, not 2")
check "bbx checks" "$got" "$want"
# WithEvents: a handler with the wrong parameter count; a class without events
got=$(cd "$root/tests/ext/evbad" && "$B" check evbad.bbp 2>&1)
want=$(printf "evbad.bas:2:5: error: WithEvents: the class Counter has no events\nevbad.bas:3:1: error: tk_Tick handles the event Ticker.Tick, which has 2 parameters, not 1")
check "event checks" "$got" "$want"
# members of an extension's classes
n=$(cd "$root/examples/ext_counter" && "$B" members --project demo.bbp Counter | wc -l | tr -d ' ')
[ "$n" = 4 ] || { echo "FAIL ext members --project: $n lines"; fail=1; }
# standard extensions: Extension=NAME found in $BOING_EXT; .bbx link lines per target (m and,
# on OS4, auto are always linked); a stock interpreter built with STD_EXTS runs it as is
sd=$root/tests/ext/stdproj
check "links host" "$(cd "$sd" && BOING_EXT=../std "$B" links stdproj.bbp)" "-lpthread"
check "links os4" "$(cd "$sd" && BOING_EXT=../std "$B" links stdproj.bbp os4)" ""
if (cd "$sd" && BOING_EXT=../std "$B" build stdproj.bbp -o "$tmp/std.nat" >/dev/null 2>&1); then check "std native" "$("$tmp/std.nat" 2>&1)" "cube 3 -2 "
else echo "FAIL ext std native (build)"; fail=1; fi
got=$(cd "$sd" && "$B" check stdproj.bbp 2>&1)
case $got in *"extension 'stdhello' not found"*) ;; *) echo "FAIL ext std not found: $got"; fail=1 ;; esac
if (cd "$root" && make -s STD_EXTS=stdhello STD_EXT_DIR=tests/ext/std BOING_EXE="$tmp/boing-std" "$tmp/boing-std" >/dev/null 2>&1); then
    check "std interpreter" "$(cd "$sd" && BOING_EXT=../std "$tmp/boing-std" run stdproj.bbp 2>&1)" "cube 3 -2 "
else echo "FAIL ext STD_EXTS interpreter (build)"; fail=1; fi
# the SQLite standard extension (ext/sqlite, Extension=sqlite): natively, and in a stock
# interpreter built with STD_EXTS=sqlite (as the kit's is)
sq=$root/tests/ext/sqlite
if (cd "$sq" && "$B" build sqltest.bbp -o "$tmp/sql.nat" >/dev/null 2>&1); then
    check "sqlite native" "$(cd "$sq" && "$tmp/sql.nat" 2>&1)" "$(cat "$sq/sqltest.out")"
else echo "FAIL ext sqlite native (build)"; fail=1; fi
check "sqlite links" "$(cd "$sq" && "$B" links sqltest.bbp)" "-lsqlite3"
if (cd "$root" && make -s STD_EXTS=sqlite BOING_EXE="$tmp/boing-sql" "$tmp/boing-sql" >/dev/null 2>&1); then
    check "sqlite std interpreter" "$(cd "$sq" && BOING_EXT="$root/ext" "$tmp/boing-sql" run sqltest.bbp 2>&1)" "$(cat "$sq/sqltest.out")"
else echo "FAIL ext STD_EXTS=sqlite interpreter (build)"; fail=1; fi
# examples/csvimport: Csv into SQLite in Timer slices (a form program, headless, natively)
ci=$root/examples/csvimport
if (cd "$ci" && "$B" build csvimport.bbp -o "$tmp/csvimport" >/dev/null 2>&1); then
    check "csvimport" "$(cd "$ci" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=60 "$tmp/csvimport" sample.csv "$tmp/ci.db" 2>&1)" "Imported 1000 records into data"
else echo "FAIL ext csvimport (build)"; fail=1; fi
rm -rf "$tmp"
echo "extension tests: $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail

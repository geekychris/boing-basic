#!/bin/sh
# the OpenGL standard extension (make test, docs/opengl.md): each tests/opengl/NAME/NAME.bbp
# natively, through a `boing vm` interpreter and with the JIT, against NAME.out; a stock
# interpreter built with STD_EXTS=opengl (as the kit's is) runs one too.
# Builds Mesa for the host first (`make opengl`, third_party/mesa: the source is downloaded once).
# Usage: sh tests/opengl/run.sh BOING
B=${1:-build/boing}; root=$(cd "$(dirname "$0")/../.." && pwd); tmp=${TMP:-/tmp}/bb-gl.$$
mkdir -p "$tmp"; fail=0
export BOING_EXT="$root/ext"
(cd "$root" && make -s opengl >/dev/null) || { echo "FAIL opengl: make opengl (Mesa) failed"; exit 1; }
check() {  # name got-file want-file
    if cmp -s "$2" "$3"; then :; else echo "FAIL opengl $1"; diff "$3" "$2" | head -20; fail=1; fi
}
for p in "$root"/tests/opengl/*/*.bbp; do
    d=$(dirname "$p"); f=$(basename "$p"); n=${f%.bbp}; want=$d/$n.out
    [ -f "$want" ] || continue
    if (cd "$d" && "$B" build "$f" -o "$tmp/$n.nat" >"$tmp/$n.log" 2>&1); then
        (cd "$d" && "$tmp/$n.nat" >"$tmp/$n.got" 2>&1); check "$n native" "$tmp/$n.got" "$want"
    else echo "FAIL opengl $n native (build)"; cat "$tmp/$n.log"; fail=1; fi
    if (cd "$d" && "$B" vm --project "$f" -o "$tmp/$n.vm" >"$tmp/$n.log" 2>&1); then
        (cd "$d" && "$tmp/$n.vm" run "$f" >"$tmp/$n.got" 2>&1); check "$n vm" "$tmp/$n.got" "$want"
        (cd "$d" && BOING_JIT=1 BOING_JIT_THRESHOLD=1 "$tmp/$n.vm" run "$f" >"$tmp/$n.got" 2>&1); check "$n vm jit" "$tmp/$n.got" "$want"
    else echo "FAIL opengl $n vm (boing vm)"; cat "$tmp/$n.log"; fail=1; fi
done
# the examples (examples/gl_*): each form program runs headless for 30 frames, natively and in
# the VM (the interpreter built for tests/opengl/basics); the last picture's hash must be the one
# in its tests/expected-hash.txt (UPDATE_GL_HASHES=1 rewrites them; an example without the file
# is not tested)
for p in "$root"/examples/gl_*/*.bbp; do
    d=$(dirname "$p"); f=$(basename "$p"); n=${f%.bbp}; hf=$d/tests/expected-hash.txt
    [ -f "$hf" ] || continue
    if (cd "$d" && "$B" build "$f" -o "$tmp/$n.nat" >"$tmp/$n.log" 2>&1); then
        nat=$(cd "$d" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=60 "$tmp/$n.nat" --frames 30 2>&1 | grep -o 'hash [0-9A-F]*')
    else echo "FAIL opengl example $n native (build)"; cat "$tmp/$n.log"; fail=1; continue; fi
    vm=$(cd "$d" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=60 "$tmp/basics.vm" run "$f" --frames 30 2>&1 | grep -o 'hash [0-9A-F]*')
    [ -n "$UPDATE_GL_HASHES" ] && echo "$nat" > "$hf"
    want=$(cat "$hf")
    [ -n "$nat" ] && [ "$nat" = "$want" ] || { echo "FAIL opengl example $n native: '$nat', want '$want'"; fail=1; }
    [ "$vm" = "$want" ] || { echo "FAIL opengl example $n vm: '$vm', want '$want'"; fail=1; }
done
# the stock interpreter with OpenGL linked in (STD_EXTS=opengl)
if (cd "$root" && make -s STD_EXTS=opengl BOING_EXE="$tmp/boing-gl" "$tmp/boing-gl" >/dev/null 2>&1); then
    (cd "$root/tests/opengl/basics" && "$tmp/boing-gl" run basics.bbp >"$tmp/std.got" 2>&1)
    check "std interpreter" "$tmp/std.got" "$root/tests/opengl/basics/basics.out"
else echo "FAIL opengl STD_EXTS=opengl interpreter (build)"; fail=1; fi
# the plain interpreter: a program that needs OpenGL stops before running
got=$(cd "$root/tests/opengl/basics" && "$B" run basics.bbp 2>&1; echo "rc=$?")
case $got in *"needs the extension 'opengl', which is not linked"*"rc=20") ;; *) echo "FAIL opengl missing extension: $got"; fail=1 ;; esac
rm -rf "$tmp"
echo "opengl tests: $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail

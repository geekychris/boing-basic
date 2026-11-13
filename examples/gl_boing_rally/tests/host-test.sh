#!/bin/sh
# Boing Rally (make test): the game built natively and run by a `boing vm` interpreter with the
# OpenGL extension, on the headless forms backend. The autopilot plays 300 frames (--bench 300);
# both must end in the same game state and the same picture, and match expected.txt (host Mesa:
# the picture hash is the host's; the OS4 guest's float rounding may differ).
dir=$(cd "$(dirname "$0")" && pwd); root=$(cd "$dir/../../.." && pwd); game=$(dirname "$dir")
BOING=${BOING:-$root/build/boing}
work=$root/build/tests/gl_boing_rally; rm -rf "$work"; mkdir -p "$work"
export BOING_EXT="$root/ext" BOING_SETTINGS="$work/settings" BOING_HEADLESS=1 BOING_HEADLESS_SECS=120
(cd "$root" && make -s opengl >/dev/null) || { echo "FAIL gl_boing_rally: make opengl"; exit 1; }
want=$(cat "$dir/expected.txt")
fail=0
if (cd "$game" && "$BOING" build BoingRally.bbp -o "$work/rally" >"$work/build.log" 2>&1); then
    got=$(cd "$game" && "$work/rally" --bench 300 --nosound < /dev/null 2>&1 | grep '^Boing Rally --bench')
    [ "$got" = "$want" ] || { echo "FAIL gl_boing_rally native: $got"; echo "  want: $want"; fail=1; }
else echo "FAIL gl_boing_rally native (build)"; cat "$work/build.log"; fail=1; fi
if (cd "$game" && "$BOING" vm --project BoingRally.bbp -o "$work/rallyvm" >"$work/vm.log" 2>&1); then
    got=$(cd "$game" && "$work/rallyvm" run BoingRally.bbp --bench 300 --nosound < /dev/null 2>&1 | grep '^Boing Rally --bench')
    [ "$got" = "$want" ] || { echo "FAIL gl_boing_rally vm: $got"; echo "  want: $want"; fail=1; }
    # the title screen (the autopilot demo behind it) runs a second without an error
    t=$(cd "$game" && BOING_HEADLESS_SECS=1 "$work/rallyvm" run BoingRally.bbp --nosound < /dev/null 2>&1; echo "exit $?")
    case $t in *error*|*"exit "[1-9]*) echo "FAIL gl_boing_rally title: $t"; fail=1 ;; esac
else echo "FAIL gl_boing_rally vm (boing vm)"; cat "$work/vm.log"; fail=1; fi
[ $fail = 0 ] && echo "gl_boing_rally: native and VM bench states and pictures match"
exit $fail

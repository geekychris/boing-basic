#!/bin/sh
# tests-os4/blit/run.sh [native|vm] - on an OS4 guest (BB_GUEST=m1b|m1c|local): the full-screen
# window shows the whole picture with no title bar, pixel for pixel. The expected picture comes
# from the same program on the host (Canvas.SavePNG); the guest's screen is a QEMU screendump.
# The other projects here (scale2, scale3big, clipped) are for old/new screenshot comparisons.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd); mode=${1:-native}; tmp=${TMPDIR:-/tmp}/bb-blit.$$
mkdir -p "$tmp"
(cd "$root/tests-os4/blit/fullscreen" && BOING_HEADLESS=1 "$root/build/boing" run fullscreen.bbp "$tmp/expected.png" >/dev/null)
m=":native"; [ "$mode" = vm ] && m=""
(cd "$root" && python3 examples/common/tools/guest_game.py tests-os4/blit/fullscreen/fullscreen.bbp "shot:$tmp/screen.png:8$m" >/dev/null)
python3 "$root/tests-os4/blit/check_screen.py" "$tmp/screen.png" "$tmp/expected.png" 2
rm -rf "$tmp"

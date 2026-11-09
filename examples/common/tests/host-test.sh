#!/bin/sh
# The amiga3d game ports' form programs on the headless forms backend (make test): each game
# plays 150 frames of its --bench (the autopilot, every frame drawn on Engine3D) and must end
# with the same state hash as its console bench; then a second on the title screen (the
# autopilot demo, title drawing, help text) must run without an error. The rules themselves
# are checked against the C originals in tests/programs/<game>.
dir=$(cd "$(dirname "$0")" && pwd); root=$(cd "$dir/../../.." && pwd)
BOING=${BOING:-$root/build/boing}
work=$root/build/tests/a3dgames; rm -rf "$work"; mkdir -p "$work"
fail=0; n=0
for p in tank_duel/TankDuel marble_tilt/MarbleTilt block_breaker_3d/BlockBreaker3D sphere_siege/SphereSiege \
         canyon_rail/CanyonRail ridge_runner/RidgeRunner drone_courier/DroneCourier harbour_crane/HarbourCrane; do
    g=$(dirname "$p"); src=$root/examples/$p.bbp; d=$root/examples/$g
    want=$(cd "$d" && "$BOING" run Bench.bbp --frames 150 < /dev/null 2>&1 | grep -o 'hash [0-9A-F]*' | head -1)
    got=$(cd "$work" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=30 "$BOING" run "$src" --bench 150 < /dev/null 2>&1)
    if [ -z "$want" ] || ! echo "$got" | grep -q "$want"; then
        echo "FAIL $g: headless --bench 150 (want $want)"; echo "$got" | tail -3; fail=1
    fi
    t=$(cd "$work" && BOING_HEADLESS=1 BOING_HEADLESS_SECS=1 "$BOING" run "$src" < /dev/null 2>&1; echo "exit $?")
    if echo "$t" | grep -q "error" || ! echo "$t" | grep -q "exit 0"; then
        echo "FAIL $g: headless title"; echo "$t" | tail -3; fail=1
    fi
    n=$((n + 1))
done
[ $fail = 0 ] && echo "amiga3d game ports: $n form programs ran headless (bench hashes match the console benches)"
exit $fail

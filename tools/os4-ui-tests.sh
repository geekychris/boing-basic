#!/bin/sh
# os4-ui-tests.sh [test ...] - run the docs/ui.md tests (tests/os4/ui_*_test) on the guest one by
# one (BB_GUEST picks it: m1b, m1c or local; never m1). Each run is its own lock session with a
# hard timeout (BB_TEST_TIMEOUT for the run itself; BB_WAIT bounds the wait for the lock as well); a test still running afterwards is stopped with Ctrl-C (its forms loop ends and
# closes its window), and Grim Reapers are reported and closed.
cd "$(dirname "$0")/.." || exit 2
tests=${*:-"ui_menu_test ui_mouse_test ui_bars_test ui_controls_test ui_forms2_test ui_load_test"}
fail=0
for t in $tests; do
    out=$(BB_TEST_TIMEOUT=${BB_TEST_TIMEOUT:-200} BB_KILL_REAPERS=1 timeout ${BB_WAIT:-3600} tools/os4guest.py test build/os4/tests/$t 2>&1)
    echo "$out" | grep -E "^(not ok|PASS|FAIL)|GRIM" | sed "s/^/$t: /"
    echo "$out" | grep -q "^PASS" || fail=1
    # still running (timed out or stuck): Ctrl-C it so no window is left behind
    cli=$(timeout 60 tools/os4guest.py dos status 2>/dev/null | grep "bbtest/$t" | sed -n 's/^Process *\([0-9]*\):.*/\1/p')
    if [ -n "$cli" ]; then
        # a requester it left open first gets Esc (only while it's the active window), then Ctrl-C
        timeout 120 tools/os4guest.py push build/os4/tests/ui_closereq RAM:bbtest/ui_closereq >/dev/null 2>&1
        timeout 60 tools/os4guest.py dos 'RAM:bbtest/ui_closereq "Bars test" "Bars test dialog" "forms_test" "Boing forms2 dialog"' 2>/dev/null | sed "s/^/$t: /"
    fi
    for c in $cli; do
        echo "$t: still running (CLI $c): sending Ctrl-C"
        timeout 60 tools/os4guest.py dos "break $c C" >/dev/null 2>&1
    done
done
exit $fail

#!/bin/sh
# run.sh - tests-os4/desk on the guest (BB_GUEST=m1b, m1c or local; never m1): desk.bas started
# in the background with arguments, the hotkey injected once it says READY, the results read
# from RAM:bbtest/desk.out. Needs build/os4/boing and build/os4/tests/desk_hotkey. PASS/FAIL.
cd "$(dirname "$0")/../.." || exit 2
G="timeout 300 tools/os4guest.py"
$G push build/os4/boing RAM:bbt/boing tests-os4/desk/desk.bas RAM:bbt/desk.bas \
    build/os4/tests/desk_hotkey RAM:bbt/desk_hotkey >/dev/null || exit 2
$G dos 'makedir RAM:bbtest' >/dev/null 2>&1
$G dos 'delete RAM:bbtest/desk.out QUIET' >/dev/null 2>&1
$G dos 'run >NIL: RAM:bbt/boing run RAM:bbt/desk.bas FILE=abc.txt SIZE=5 QUIET' >/dev/null || exit 2
out=""
for i in 1 2 3 4 5 6 7 8 9 10; do
    out=$($G dos 'type RAM:bbtest/desk.out' 2>/dev/null)
    echo "$out" | grep -q READY && break
    sleep 2
done
$G dos 'RAM:bbt/desk_hotkey' >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do
    out=$($G dos 'type RAM:bbtest/desk.out' 2>/dev/null)
    echo "$out" | grep -qE '^(PASS|FAIL)' && break
    sleep 2
done
echo "$out"
echo "$out" | grep -q '^PASS'

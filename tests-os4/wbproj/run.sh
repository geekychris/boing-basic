#!/bin/sh
# run.sh - boing as a project icon's default tool (BB_GUEST=m1b, m1c or local; never m1):
# RAM:bbt/wbproj.bas gets an icon with tooltypes and is opened through Workbench with a second
# icon selected. Needs build/os4/boing and build/os4/tests/wb_*. PASS/FAIL.
cd "$(dirname "$0")/../.." || exit 2
G="timeout 300 tools/os4guest.py"
$G push build/os4/boing RAM:bbt/boing tests-os4/wbproj/wbproj.bas RAM:bbt/wbproj.bas \
    build/os4/tests/wb_mkproj RAM:bbt/wb_mkproj build/os4/tests/wb_open RAM:bbt/wb_open >/dev/null || exit 2
$G dos 'delete RAM:bbtest/wbproj.out QUIET' >/dev/null 2>&1
$G dos 'makedir RAM:bbtest' >/dev/null 2>&1
$G dos 'echo >RAM:bbt/other.txt "x"' >/dev/null
$G dos 'RAM:bbt/wb_mkproj RAM:bbt/wbproj.bas RAM:bbt/boing SIZE=7 MODE=fast' || exit 2
$G dos 'RAM:bbt/wb_open RAM:bbt/wbproj.bas RAM:bbt/other.txt' || exit 2
# the program writes its results and ends; its console window (AUTO/WAIT) only opens if it prints
for i in 1 2 3 4 5 6 7 8 9 10; do
    out=$($G dos 'type RAM:bbtest/wbproj.out' 2>/dev/null)
    echo "$out" | grep -qE '^(PASS|FAIL)' && break
    sleep 3
done
echo "$out"
echo "$out" | grep -q '^PASS'

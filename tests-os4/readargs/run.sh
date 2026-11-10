#!/bin/sh
# run.sh - App.ReadArgs on the guest (BB_GUEST=m1b, m1c or local; never m1): readargs.bas with
# three command lines through build/os4/boing, output compared with expected.txt. PASS/FAIL.
cd "$(dirname "$0")/../.." || exit 2
G="timeout 300 tools/os4guest.py"
$G push build/os4/boing RAM:bbt/boing tests-os4/readargs/readargs.bas RAM:bbt/readargs.bas >/dev/null || exit 2
out=$(
  $G dos 'RAM:bbt/boing run RAM:bbt/readargs.bas FILE=a.txt SIZE=5 QUIET VERBOSE=ON NUMS 1 2 3'
  $G dos 'RAM:bbt/boing run RAM:bbt/readargs.bas SIZE=5'
  $G dos 'RAM:bbt/boing run RAM:bbt/readargs.bas b'
)
echo "$out"
if [ "$(echo "$out" | sed 's/ *$//')" = "$(sed 's/ *$//' tests-os4/readargs/expected.txt)" ]; then echo PASS; else echo FAIL; exit 1; fi

#!/bin/sh
# tests-net/os4-run.sh [vm|native|both] - the Http class tests on an OS4 guest (BB_GUEST, default
# local): tools/http_testserver.py runs on this Mac (or, for a remote guest, on that guest's
# host over ssh — not yet) and the guest reaches it through QEMU's gateway 192.168.101.2.
# Runs tests-net/httptest.bas with build/os4/boing and/or built natively for OS4, compares
# with httptest.out. Holds the guest's lock (tools/os4guest.py).
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-both}
cd "$root" || exit 20
[ -f build/os4/boing ] || tools/build-os4.sh >/dev/null || exit 20
exec python3 - "$mode" <<'PY'
import os, re, subprocess, sys, tempfile, time
sys.path.insert(0, "tools")
import os4guest as g
mode = sys.argv[1]
if g.SSH:
    sys.exit("os4-run.sh: remote guests need the test server on their host; use the local guest")
work = tempfile.mkdtemp()
pf = os.path.join(work, "ports")
srv = subprocess.Popen([sys.executable, "tools/http_testserver.py", "--ports-file", pf, "--certs", "build/net-certs"])
try:
    for _ in range(100):
        if os.path.exists(pf): break
        time.sleep(0.1)
    hp, sp, ca = open(pf).read().split()
    expected = open("tests-net/httptest.out").read()
    m = g.MCP(g.URL)
    ok = True
    with g.testing("Boing BASIC Http tests"):
        files = [("tests-net/httptest.bas", "RAM:bbnet/httptest.bas"), (ca, "RAM:bbnet/ca.pem")]
        if mode in ("vm", "both"): files.append(("build/os4/boing", "RAM:bbnet/boing"))
        if mode in ("native", "both"):
            subprocess.check_call(["build/boing", "build", "tests-net/httptest.bas", "--target", "os4", "-o", "build/os4/httptest"])
            files.append(("build/os4/httptest", "RAM:bbnet/httptest"))
        for a, b in files:
            print(g.push(m, a, b))
        gw = "192.168.101.2"
        args = "http://%s:%s https://%s:%s RAM:bbnet/ca.pem RAM:bbnet/" % (gw, hp, gw, sp)
        runs = []
        if mode in ("vm", "both"): runs.append(("vm", "RAM:bbnet/boing run RAM:bbnet/httptest.bas " + args))
        if mode in ("native", "both"): runs.append(("native", "RAM:bbnet/httptest " + args))
        for label, cmd in runs:
            out = g.run_bg(m, cmd, "RAM:bbnet/%s.out" % label, limit=300)
            got = "\n".join(l for l in out.replace("\r", "").split("\n") if re.match(r"^(ok|not ok|PASS|FAIL)", l)) + "\n"
            same = got == expected
            ok &= same
            print("== %s: %s" % (label, "PASS (output == httptest.out)" if same else "FAIL"))
            if not same: print(out)
        n = g.reapers(m)
        if n:
            print("GRIM REAPER: %d" % n); ok = False
    print("os4 http test:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
finally:
    srv.terminate()
PY

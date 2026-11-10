#!/bin/sh
# tests-net/os4-run.sh [vm|native|both] - the Http class tests on an OS4 guest (BB_GUEST, default
# local): tools/http_testserver.py runs on this Mac (or, for a remote guest, on that guest's
# host over ssh — not yet) and the guest reaches it through QEMU's gateway 192.168.101.2.
# Runs tests-net/httptest.bas and asynctest.bas with build/os4/boing and/or built natively for
# OS4, compares with the .out files. Holds the guest's lock (tools/os4guest.py).
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
    tests = ["httptest", "asynctest", "sessiontest", "asyncexit"]
    m = g.MCP(g.URL)
    ok = True
    with g.testing("Boing BASIC Http tests"):
        files = [(ca, "RAM:bbnet/ca.pem")]
        if mode in ("vm", "both"): files.append(("build/os4/boing", "RAM:bbnet/boing"))
        for t in tests:
            files.append(("tests-net/%s.bas" % t, "RAM:bbnet/%s.bas" % t))
            if mode in ("native", "both"):
                subprocess.check_call(["build/boing", "build", "tests-net/%s.bas" % t, "--target", "os4", "-o", "build/os4/" + t])
                files.append(("build/os4/" + t, "RAM:bbnet/" + t))
        for a, b in files:
            print(g.push(m, a, b))
        gw = "192.168.101.2"
        args = "http://%s:%s https://%s:%s RAM:bbnet/ca.pem RAM:bbnet/" % (gw, hp, gw, sp)
        for t in tests:
            expected = open("tests-net/%s.out" % t).read()
            runs = []
            if mode in ("vm", "both"): runs.append(("vm", "RAM:bbnet/boing run RAM:bbnet/%s.bas %s" % (t, args)))
            if mode in ("native", "both"): runs.append(("native", "RAM:bbnet/%s %s" % (t, args)))
            for label, cmd in runs:
                out = g.run_bg(m, cmd, "RAM:bbnet/%s-%s-%d.out" % (t, label, int(time.time())), limit=60 if t == "asyncexit" else 300)   # a fresh name: a hung earlier run keeps its file open
                got = "\n".join(l for l in out.replace("\r", "").split("\n") if re.match(r"^(ok|not ok|PASS|FAIL)", l)) + "\n"
                same = got == expected
                ok &= same
                print("== %s %s: %s" % (t, label, "PASS (output == %s.out)" % t if same else "FAIL"))
                if not same: print(out)
        if not os.path.exists("build/os4/tasklist"):
            subprocess.check_call(["tools/build-os4.sh", "build/os4/tasklist"])
        print(g.push(m, "build/os4/tasklist", "RAM:bbnet/tasklist"))
        time.sleep(3)                           # a crash at exit shows its requester a moment later
        n = g.reapers(m)
        if n:
            print("GRIM REAPER: %d" % n); ok = False
    # nothing may be left running: no worker process, no test program. Checked with the banner
    # down (g.quiet), since while it is up ended processes can't finish leaving.
    with g.quiet():
        for what in ("Boing BASIC worker", "RAM:bbnet/"):
            left = ""
            for _ in range(15):                 # a program may still be ending
                left = m.tool("amiga_dos_command", command='RAM:bbnet/tasklist "%s"' % what)
                if "0 task(s)" in left: break
                time.sleep(2)
            if "0 task(s)" not in left:
                print("LEFT RUNNING:", left.strip()); ok = False
            else:
                print("left running (%s): none" % what)
    print("os4 http test:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
finally:
    srv.terminate()
PY

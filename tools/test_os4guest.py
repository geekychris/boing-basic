#!/usr/bin/env python3
"""Host test of tools/os4guest.py (make test): each guest session gets a watchdog deadline
of its own (BB_SESSION_TIMEOUT counts from that session's lock, not from the process's
first one), the watchdog stops when its session ends, and monitor commands refuse the
user's m1 guest. No guest needed: the devbench URL points nowhere."""
import os, sys, time
os.environ["OS4_MCP"] = "http://127.0.0.1:9/mcp"       # status fetches fail quietly
os.environ["BB_SESSION_TIMEOUT"] = "1.0"
os.environ["BB_WATCHDOG_POLL"] = "0.05"
os.environ["BB_SILENT"] = "1000"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import os4guest as g  # noqa: E402

fired = []
g._give_up = lambda why: fired.append((time.time(), why))
ok = True


def check(cond, what):
    global ok
    print(("PASS " if cond else "FAIL ") + "os4guest " + what)
    ok &= bool(cond)


# two sequential 0.7 s sessions in one process: neither may hit the 1.0 s deadline
for i in (1, 2):
    done = g.watchdog()
    time.sleep(0.7)
    done.set()
    time.sleep(0.15)
check(not fired, "watchdog: two sequential sessions each get their own deadline")

# a session longer than the deadline is given up, about on time
t0 = time.time()
done = g.watchdog()
time.sleep(1.5)
check(len(fired) == 1 and 0.9 <= fired[0][0] - t0 <= 1.3 and "session longer" in fired[0][1],
      "watchdog: a session past BB_SESSION_TIMEOUT is given up (%s)" % [round(f[0] - t0, 2) for f in fired])
done.set()

# a stopped watchdog never fires later
n = len(fired)
done = g.watchdog()
done.set()
time.sleep(1.3)
check(len(fired) == n, "watchdog: stops with its session")

# the default cap is 300 s
del os.environ["BB_SESSION_TIMEOUT"]
import inspect
check('"BB_SESSION_TIMEOUT", "300"' in inspect.getsource(g.watchdog), "watchdog: default cap 300 s")

# m1 is the user's guest: monitor commands refuse it without --user-ok
g.GUEST = "m1"
try:
    g.hmp("info status")
    refused = False
except SystemExit:
    refused = True
check(refused, "hmp/mouse/shot refuse BB_GUEST=m1 without --user-ok")
g.GUEST = "m1b"
check(g.GUESTS["m1b"]["hmp"] == 2448 and g.GUESTS["m1c"]["hmp"] == 2548 and g.GUESTS["local"]["hmp"] == 2348,
      "monitor ports per guest")
sys.exit(0 if ok else 1)

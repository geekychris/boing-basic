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

# m1 is the user's guest: screenshots and monitor input exit before any socket or ssh,
# whatever the environment says
import socket, subprocess
opened = []
real_conn, real_run = socket.create_connection, subprocess.run
socket.create_connection = lambda *a, **k: opened.append(("socket", a)) or (_ for _ in ()).throw(OSError("blocked"))
subprocess.run = lambda *a, **k: opened.append(("subprocess", a)) or (_ for _ in ()).throw(OSError("blocked"))
os.environ["OS4_HMP_PORT"] = "2348"
os.environ["BB_USER_OK"] = "1"
g.GUEST, g._G, g.SSH = "m1", g.GUESTS["m1"], g.GUESTS["m1"]["ssh"]
for name, call in (("shot", lambda: g.shot(None, "/tmp/never.png", True)), ("mouse", lambda: g.mouse(1, 0, True)),
                   ("hmp", lambda: g.hmp("info status", True))):
    try:
        call()
        refused = False
    except SystemExit as e:
        refused = "BB_GUEST=m1" in str(e)
    check(refused and not opened, "%s on m1 exits before any socket or ssh (even with OS4_HMP_PORT, BB_USER_OK)" % name)
check("hmp" not in g.GUESTS["m1"], "the m1 profile has no monitor port")
# a guest without a monitor port in its profile gets no default
g.GUEST, g._G = "nohmp", {"url": "", "ssh": None}
del os.environ["OS4_HMP_PORT"]
try:
    g.hmp("info status")
    nodef = False
except SystemExit:
    nodef = True
check(nodef and not opened, "no default monitor port for a profile without one")
socket.create_connection, subprocess.run = real_conn, real_run
check(g.GUESTS["m1b"]["hmp"] == 2448 and g.GUESTS["m1c"]["hmp"] == 2548 and g.GUESTS["local"]["hmp"] == 2348
      and g.GUESTS["spark"]["hmp"] == 2348, "monitor ports per guest")

# bbfetch attempts: a stalled connection is retried once on the same gateway, then the next
# gateway; each attempt carries its MAXSECONDS (size at 1 MB/s + 30 s)
import time as _time
_time.sleep = lambda s: None


class FetchGuest:
    def __init__(self, answers, size=24000000):
        self.answers, self.calls, self.size, self.breaks = list(answers), [], size, 0

    def tool(self, name, **a):
        c = a.get("command", "")
        if "bbfetch" in c and c.startswith(g.FETCH):
            self.calls.append((c, a.get("timeout")))
            return self.answers.pop(0)
        if c == "status":
            return "Process  9: Loaded as command: DH1:bbtools/bbfetch\n" if self.breaks == 0 else ""
        if c.startswith("break"):
            self.breaks += 1
            return ""
        if c.startswith("list"):
            return str(self.size)
        return ""


urls = ["http://gw1/f", "http://gw2/f"]
fg = FetchGuest(["FAIL too slow (still running after MAXSECONDS)", "OK 24000000 0abc"])
out = g._fetch(fg, urls, "RAM:x", 24000000, "0abc")
check("OK 24000000" in out and [c[0].split()[1] for c in fg.calls] == ["http://gw1/f", "http://gw1/f"]
      and fg.breaks >= 1, "fetch: a stalled attempt is stopped and retried on the same gateway (new connection)")
check(all(c[0].split()[-1] == "54" and abs(c[1] - 69.0) < 0.01 for c in fg.calls),
      "fetch: each attempt has MAXSECONDS = size at 1 MB/s + 30 s (%s)" % [c[0].split()[-1] for c in fg.calls])
fg = FetchGuest(["FAIL too slow", "FAIL receive timeout (no data for 30 s)", "OK 24000000 0abc"])
out = g._fetch(fg, urls, "RAM:x", 24000000, "0abc")
check("OK" in out and [c[0].split()[1] for c in fg.calls] == ["http://gw1/f", "http://gw1/f", "http://gw2/f"],
      "fetch: two failed attempts on a gateway, then the next gateway")
fg = FetchGuest(["FAIL too slow", "FAIL too slow", "FAIL connect", "OK 24000000 0abc"])
out = g._fetch(fg, urls, "RAM:x", 24000000, "0abc")
check("OK" in out and [c[0].split()[1] for c in fg.calls] == ["http://gw1/f"] * 2 + ["http://gw2/f", "http://gw1/f"]
      and fg.calls[-1][0].split()[-1] == str(int(g._slow_timeout(24000000))),
      "fetch: after the fast attempts, one slow attempt on the gateway that connected (%s)"
      % [(c[0].split()[1], c[0].split()[-1]) for c in fg.calls])
fg = FetchGuest(["FAIL connect", "OK 24000000 0abc"])
out = g._fetch(fg, urls, "RAM:x", 24000000, "0abc")
check("OK" in out and [c[0].split()[1] for c in fg.calls] == ["http://gw1/f", "http://gw2/f"],
      "fetch: a gateway that doesn't connect is left at once")
fg = FetchGuest(["[RUNNING] still going after 30s"])
out = g._fetch(fg, urls, "RAM:x", 24000000, "0abc")
check("OK 24000000" in out and len(fg.calls) == 1, "fetch: a bbfetch still running is waited for until its file is complete")
# the programs a session starts: recorded at the start, Ctrl-C at the end, survivors reported
class ProcGuest:
    """status: the base processes plus whatever runs; 'run >NIL: X' starts X as the next CLI;
    'break N C' ends N unless it is stubborn."""
    def __init__(self, stubborn=()):
        self.procs = {1: "DH1:amiga-bridge", 3: "DH1:launcher"}
        self.stubborn, self.breaks, self.next = set(stubborn), [], 7

    def tool(self, name, **a):
        c = a.get("command", "")
        if c == "status":
            return "".join("Process %2d: Loaded as command: %s\n" % kv for kv in sorted(self.procs.items())) + \
                "Process %2d: Loaded as command: status\n" % (self.next + 50)
        if c.startswith("run >NIL: "):
            self.procs[self.next] = c[len("run >NIL: "):].split()[0]
            self.next += 1
            return "[OK]"
        mm = re.match(r"break (\d+) (\S+)", c)
        if mm:
            n = int(mm.group(1))
            self.breaks.append((n, mm.group(2)))
            if n not in self.stubborn:
                self.procs.pop(n, None)
            return ""
        return ""


import re
pg = ProcGuest()
g.SESSION["procs"] = {}
g.run_bg_cmd(pg, "RAM:bbt/boing run x.bbp")
g.run_bg_cmd(pg, "execute RAM:bbkit/install.dos", protect=True)
check(g.SESSION["procs"] == {7: ("RAM:bbt/boing", False), 8: ("execute", True)},
      "session: background starts are recorded with their CLI numbers (%s)" % g.SESSION["procs"])
import io
err, sys.stderr = sys.stderr, io.StringIO()
left = g.end_session(pg)
warned, sys.stderr = sys.stderr.getvalue(), err
check((7, "C") in pg.breaks and 7 not in pg.procs and (8, "C") not in pg.breaks and list(left) == [8]
      and "protected" in warned, "session end: Ctrl-C to its programs, a protected one is left and reported")
check(g.SESSION["procs"] == {}, "session end: the record is cleared")
pg = ProcGuest(stubborn={7})
g.run_bg_cmd(pg, "RAM:bbtest/hang")
err, sys.stderr = sys.stderr, io.StringIO()
left = g.end_session(pg)
warned, sys.stderr = sys.stderr.getvalue(), err
check((7, "C") in pg.breaks and (7, "ALL") in pg.breaks and 7 in left and "WARNING" in warned and "CLI 7" in warned,
      "session end: a program that ignores Ctrl-C gets a full break and is reported loudly")
pg = ProcGuest()
pg.procs[5] = "C:Copy"                  # not this session's
g.run_bg_cmd(pg, "RAM:bbt/boing run y.bbp")
g.end_session(pg)
check(all(n != 5 for n, _ in pg.breaks), "session end: other sessions' processes are left alone")
# the give-up path cleans up too (not when the bridge is silent)
import importlib.util
spec = importlib.util.spec_from_file_location("og2", os.path.join(os.path.dirname(os.path.abspath(__file__)), "os4guest.py"))
og2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(og2)            # an untouched copy: the real _give_up
calls, real_exit = [], os._exit
og2.end_session = lambda m: calls.append("end")
og2.MCP = lambda url, timeout=600: None
os._exit = lambda c: calls.append("exit %d" % c)
err, sys.stderr = sys.stderr, io.StringIO()
og2.SESSION["procs"] = {9: ("RAM:bbt/boing", False)}
og2._give_up("session longer than 300s")
og2._give_up("bridge silent (200 s) or disconnected")
warned, sys.stderr = sys.stderr.getvalue(), err
os._exit = real_exit
check(calls == ["end", "exit 3", "exit 3"] and "may still run" in warned and "CLI 9" in warned,
      "give-up: a session that ran too long is cleaned up before leaving; with a silent bridge its programs are listed (%s)" % calls)
# the session-start snapshot: busy leftovers
listing = """TASKS 9 READY 5 (this tasklist is the running one)
READY pri=   0 proc pid= 12 ppid=  0 cli= 0 cmd=[] name=[dos_signal_server]
READY pri=   0 task pid=  0 ppid=  0 cli= 0 cmd=[] name=[idle.task]
READY pri= -10 proc pid= 40 ppid= 31 cli= 5 cmd=[] name=[Background CLI]
READY pri=   0 proc pid= 77 ppid= 31 cli= 6 cmd=[RAM:bbg/boing] name=[Background CLI]
READY pri=   1 proc pid= 78 ppid= 31 cli= 7 cmd=[DH1:tincture/Tincture] name=[Tincture]
wait  pri=   0 proc pid= 31 ppid=  0 cli= 1 cmd=[DH1:amiga-bridge] name=[amiga-bridge]
"""
bad = g.suspect_tasks(listing)
check(sorted(b[1] for b in bad) == ["DH1:tincture/Tincture", "RAM:bbg/boing"],
      "snapshot: busy programs READY at priority >= 0 are flagged, also in a Background CLI (%s)" % bad)
sys.exit(0 if ok else 1)

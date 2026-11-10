#!/usr/bin/env python3
"""os4guest.py - push files to the AmigaOS 4 QEMU guest and run commands there, through the
amiga_mcp devbench MCP server, holding the emulator lock and the "CLAUDE IS TESTING" banner
(the guest is shared with the user and other agents).

    tools/os4guest.py push LOCAL AMIGA_PATH [LOCAL AMIGA_PATH ...]
    tools/os4guest.py dos 'AmigaDOS command'
    tools/os4guest.py shot OUT.png                     screenshot of the selected guest (wakes the blanker
                                                      with a 1-pixel move; shot(m, png) in scripts)
    tools/os4guest.py mouse DX DY                      move the selected guest's mouse (through its devbench;
                                                      QEMU monitor commands: hmp(cmd) in scripts). Both
                                                      always refuse m1 (the user's guest)
    tools/os4guest.py test LOCAL_TEST_BINARY [args]   push to RAM:bbtest/ and run it, exit 1 on FAIL; a
                                                      "# HMP: cmd; sleep s; cmd" line it prints is run on
                                                      the QEMU monitor (buttons, held keys)
    tools/os4guest.py bas PROJECT.bbp|PROG.bas [vm|jit|native|both|all]
                                                      run a BASIC test with build/os4/boing (VM)
                                                      and/or natively built; exit 1 unless PASS
    tools/os4guest.py outtest PROG.bas [vm|native|both] run a test whose expected output is PROG.out
                                                      (VM with build/os4/boing, native built
                                                      for OS4) and compare; exit 1 on a difference
    tools/os4guest.py tool NAME '{json args}'          any devbench MCP tool
    tools/os4guest.py setup                            once per guest disk: build DH1:bbtools/bbfetch
                                                      (on the guest, SDK GCC) and copy ptr there
    tools/os4guest.py reapers                          report (and with --kill, close) Grim Reapers

Fast deploy: files bigger than BB_HTTP_MIN (16 KB) go over HTTP, not the serial bridge: this
script serves them from the Mac on 127.0.0.1 (QEMU's user-mode network makes that the guest's
gateway, 192.168.101.2) and DH1:bbtools/bbfetch fetches them, checking length and CRC-32. The
bridge only carries the command. Without bbfetch on the guest (run `setup`) big files are
refused rather than pushed through the bridge (big bridge pushes have killed the guest).
Parent directories are created.

Sharing the guest: every command takes a FIFO ticket (/tmp/amiga-emu.queue, oldest first) and
then amiga_mcp's emulator lock + banner, holds it only for that command, and gives it up when
the bridge stops answering (BB_SILENT, 90 s of no heartbeat) or the session is too long
(BB_SESSION_TIMEOUT, 600 s). After `test`/`bas` runs it looks for Grim Reaper windows and
reports them (BB_KILL_REAPERS=1 closes them).

Guests: BB_GUEST=local (default, devbench :3010), m1 (:3020, QEMU on m1.local), m1b (:3030) and
m1c (:3040), the second and third QEMU guests on m1.local, spark (:3032, QEMU on spark.local): each
its own lock and queue (/tmp/amiga-emu[-m1|-m1b|-m1c|-spark].lock/.queue); for remote ones the
fast-deploy HTTP server runs on that machine over ssh (on its loopback: port 18780, 18781 for m1b,
18782 for m1c).
Overrides: OS4_MCP, OS4_LOCK, OS4_QUEUE, OS4_SSH, OS4_REMOTE_HTTP_PORT. On remote guests every
push goes over HTTP once bbfetch is there (their devbench reads amiga_push_file/amiga_pull_file
paths on the remote machine; bridge pushes copy the file there first).

Env: OS4_MCP (default http://localhost:3010/mcp; :3000 can be shadowed, see amiga_mcp memory),
AMIGA_MCP (the amiga_mcp checkout, for scripts/claude_busy.py), BB_BANNER=0 to skip the banner
and the lock (read-only probes only).
"""
import contextlib
import json
import re
import os
import shutil
import sys
import tempfile
import urllib.request

# Which OS4 guest: BB_GUEST=local (default) | m1 | m1b | m1c | spark; each has its own devbench URL, emulator
# lock and FIFO queue on this Mac, and (remote ones) the ssh login of the machine QEMU runs on,
# where the HTTP server for fast deploys must run (the guest only reaches its own host).
GUESTS = {
    "local": {"url": "http://localhost:3010/mcp", "lock": "/tmp/amiga-emu.lock",
              "queue": "/tmp/amiga-emu.queue", "ssh": None, "hmp": 2348},
    "m1": {"url": "http://localhost:3020/mcp", "lock": "/tmp/amiga-emu-m1.lock",
           "queue": "/tmp/amiga-emu-m1.queue", "ssh": "chriscollins@m1.local"},   # the USER's guest: no "hmp" (no screenshots/input)
    # the second guest on m1 (~/retro/os4b.sh there, devbench :3003; tunnel localhost:3030 -> m1:3003)
    "m1b": {"url": "http://localhost:3030/mcp", "lock": "/tmp/amiga-emu-m1b.lock",
            "queue": "/tmp/amiga-emu-m1b.queue", "ssh": "chriscollins@m1.local", "http_port": 18781,
            "hmp": 2448},
    # the third guest on m1 (~/retro/os4c.sh there, devbench :3004; tunnel localhost:3040 -> m1:3004)
    "m1c": {"url": "http://localhost:3040/mcp", "lock": "/tmp/amiga-emu-m1c.lock",
            "queue": "/tmp/amiga-emu-m1c.queue", "ssh": "chriscollins@m1.local", "http_port": 18782,
            "hmp": 2548},
    "spark": {"url": "http://127.0.0.1:3032/mcp", "lock": "/tmp/amiga-emu-spark.lock",
              "queue": "/tmp/amiga-emu-spark.queue", "ssh": "chris@spark.local", "hmp": 2348},
}
GUEST = os.environ.get("BB_GUEST", "local")
if GUEST not in GUESTS:
    sys.exit("os4guest: unknown BB_GUEST %r (local, m1, m1b, m1c, spark)" % GUEST)
_G = GUESTS[GUEST]
URL = os.environ.get("OS4_MCP", _G["url"])
LOCK = os.environ.get("OS4_LOCK", _G["lock"])
SSH = os.environ.get("OS4_SSH", _G["ssh"] or "") or None
REMOTE_PORT = int(os.environ.get("OS4_REMOTE_HTTP_PORT", _G.get("http_port", 18780)))
AMIGA_MCP = os.environ.get("AMIGA_MCP", os.path.expanduser("~/code/claude_world/amiga_mcp"))


class MCP:
    def __init__(self, url, timeout=600):
        self.url, self.sid, self.timeout = url, None, timeout

    def _post(self, body):
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["mcp-session-id"] = self.sid
        with urllib.request.urlopen(urllib.request.Request(self.url, json.dumps(body).encode(), h),
                                    timeout=self.timeout) as r:
            raw = r.read().decode()
            self.sid = r.headers.get("mcp-session-id") or self.sid
        msgs = [json.loads(l[5:]) for l in raw.splitlines() if l.startswith("data:")]
        return msgs or ([json.loads(raw)] if raw.strip() else [])

    def tool(self, name, **args):
        if self.sid is None:
            self._post({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {
                "protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "os4guest", "version": "1"}}})
            self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        res = self._post({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                          "params": {"name": name, "arguments": args}})
        r = res[-1].get("result", res[-1]) if res else {}
        text = "\n".join(c.get("text", "") for c in r.get("content", []))
        if r.get("isError"):
            raise RuntimeError(text)
        return text


QUEUE = os.environ.get("OS4_QUEUE", _G["queue"])


@contextlib.contextmanager
def fifo_ticket():
    """Wait until our ticket is the oldest live one (flock alone isn't FIFO: new jobs jumped
    the queue). Tickets of dead processes are dropped."""
    import time
    os.makedirs(QUEUE, exist_ok=True)
    me = os.path.join(QUEUE, "%015.3f-%d" % (time.time(), os.getpid()))
    open(me, "w").write(" ".join(sys.argv) + "\n")
    try:
        while True:
            live = []
            for t in sorted(os.listdir(QUEUE)):
                try:
                    pid = int(t.rsplit("-", 1)[1])
                    os.kill(pid, 0)
                    live.append(t)
                except (ValueError, ProcessLookupError, IndexError):
                    try:
                        os.unlink(os.path.join(QUEUE, t))
                    except OSError:
                        pass
                except PermissionError:
                    live.append(t)
            if not live or os.path.join(QUEUE, live[0]) == me:
                break
            time.sleep(2)
        yield
    finally:
        try:
            os.unlink(me)
        except OSError:
            pass


def _give_up(why):
    """leave the process (which releases the emulator lock); tests replace this. The programs this
    session started go first (Ctrl-C), unless the bridge is silent (then they're only listed)."""
    sys.stderr.write("os4guest: giving up the guest: %s\n" % why)
    try:
        if "silent" in why or "disconnected" in why:
            if SESSION["procs"]:
                sys.stderr.write("os4guest: WARNING: the bridge is silent, so these programs of this session may "
                                 "still run on the guest: %s\n" % _proc_list(SESSION["procs"]))
        else:
            end_session(MCP(URL, timeout=20))
    except Exception as e:
        sys.stderr.write("os4guest: cleaning up the session failed: %s\n" % e)
    sys.stderr.flush()
    os._exit(3)


def watchdog():
    """Give up the guest if the bridge goes silent or this session holds it too long
    (BB_SESSION_TIMEOUT, default 300 s). Timed from this session's lock: returns a
    threading.Event that the session sets when it ends, which stops this watchdog, so every
    testing() session in a process gets a deadline of its own."""
    import threading
    import time
    silent_max = float(os.environ.get("BB_SILENT", "150"))
    session_max = float(os.environ.get("BB_SESSION_TIMEOUT", "300"))
    poll = float(os.environ.get("BB_WATCHDOG_POLL", "10"))
    status_url = URL.rsplit("/mcp", 1)[0] + "/api/status"
    t0 = time.time()
    done = threading.Event()

    def run():
        while not done.wait(poll):
            why = None
            if time.time() - t0 > session_max:
                why = "session longer than %ds" % session_max
            else:
                try:
                    d = json.load(urllib.request.urlopen(status_url, timeout=5))
                    s = d.get("bridgeSilentSec")
                    if s is None:       # devbench gives null after a reconnect: use the heartbeat
                        import datetime
                        hb = (d.get("lastHeartbeat") or {}).get("timestamp")
                        if hb:
                            t = datetime.datetime.fromisoformat(hb.replace("Z", "+00:00"))
                            s = (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()
                    if not d.get("connected") or (s is not None and s > silent_max):
                        why = "bridge silent (%s s) or disconnected" % (int(s) if s is not None else "?")
                except Exception:
                    pass
            if why and not done.is_set():
                _give_up(why)
                return
    threading.Thread(target=run, daemon=True).start()
    return done


def bridge_alive(max_age=150):
    import datetime
    try:
        d = json.load(urllib.request.urlopen(URL.rsplit("/mcp", 1)[0] + "/api/status", timeout=5))
    except Exception:
        return False
    hb = (d.get("lastHeartbeat") or {}).get("timestamp")
    if not d.get("connected") or not hb:
        return False
    t = datetime.datetime.fromisoformat(hb.replace("Z", "+00:00"))
    return (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds() < max_age


# --- the programs a session starts ---------------------------------------------------------
# A program started in the background (run >NIL:) keeps running after its session gives up the
# guest, and a busy leftover starves the next session (TCP at ~100 KB/s, heartbeats stalled,
# the bridge dead in the end). So every background start goes through run_bg_cmd(), which
# records the CLI numbers it added; end_session() sends them Ctrl-C (then a full break), checks
# `status` and warns about any that survive. protect=True (the kit's swap script: breaking it
# half-way is worse than letting it finish) is only reported.
SESSION = {"procs": {}}         # CLI number -> (command, protected)


def status_procs(m):
    """CLI number -> command of the guest's CLI processes (`status`)."""
    out = m.tool("amiga_dos_command", command="status")
    return {int(n): c.strip() for n, c in re.findall(r"Process\s+(\d+): Loaded as command: (.*)", out)}


def _proc_list(procs):
    return ", ".join("CLI %d (%s)" % (n, c[0] if isinstance(c, tuple) else c) for n, c in sorted(procs.items()))


def run_bg_cmd(m, cmdline, protect=False):
    """`run >NIL: cmdline` on the guest, remembering the processes it started for end_session().
    Returns their CLI numbers."""
    before = status_procs(m)
    out = m.tool("amiga_dos_command", command="run >NIL: " + cmdline)
    after = status_procs(m)
    new = {n: c for n, c in after.items() if n not in before or before[n] != c}
    for n, c in new.items():
        if c.lower() != "status":
            SESSION["procs"][n] = (c, protect)
    return out


def end_session(m):
    """Ctrl-C to every process this session started that still runs, then a full break to any
    that ignore it; warn loudly about survivors (and about protected ones, which aren't broken).
    Returns the survivors."""
    import time
    mine = dict(SESSION["procs"])
    SESSION["procs"] = {}
    if not mine:
        return {}
    running = status_procs(m)
    alive = {n: v for n, v in mine.items() if running.get(n) == v[0]}
    for sig in ("C", "ALL"):
        targets = [n for n, v in alive.items() if not v[1]]
        if not targets:
            break
        for n in targets:
            m.tool("amiga_dos_command", command="break %d %s" % (n, sig))
        time.sleep(3)
        running = status_procs(m)
        alive = {n: v for n, v in alive.items() if running.get(n) == v[0]}
    if alive:
        sys.stderr.write("os4guest: WARNING: still running on the guest after this session: %s%s\n" % (
            _proc_list(alive), " (protected: left to finish)" if all(v[1] for v in alive.values()) else ""))
    return alive


# ready tasks other than these, at priority >= 0, at the start of a session are suspect
# (infra-m1b's tasklist; an idle guest shows about 3-7 READY)
TASKS_OK = ("dos_signal_server", "dos_appdir_server", "idle.task", "AmiDock", "amiga-bridge",
            "Background CLI", "tasklist", "input.device", "Workbench", "RinghioServer")
CMDS_OK = ("amiga-bridge", "tasklist")     # a CLI running one of these is fine
# (claude_busy, the testing banner, is deliberately on neither list: it once spun at priority 0
# and starved every command the bridge runs, fixed in amiga_mcp #71; if it is ever busy again,
# the snapshot says so)


def suspect_tasks(listing):
    """(name, cmd, priority) of READY tasks at priority >= 0 that aren't the usual ones."""
    out = []
    for m_ in re.finditer(r"^READY\s+pri=\s*(-?\d+)\s+\S+\s+pid=\s*\d+\s+ppid=\s*\d+\s+cli=\s*\d+\s+"
                          r"cmd=\[(.*?)\]\s+name=\[(.*?)\]", listing, re.M):
        pri, cmd, name = int(m_.group(1)), m_.group(2), m_.group(3)
        if pri < 0:
            continue
        # a CLI process is judged by the command it runs (a Background CLI running boing at
        # priority 0 is a busy leftover); a task without one by its name
        ok_ = any(k.lower() in cmd.lower() for k in CMDS_OK) if cmd else \
            any(k.lower() in name.lower() for k in TASKS_OK)
        if not ok_:
            out.append((name, cmd, pri))
    return out


def task_snapshot(m):
    """At a session's start: warn about busy leftovers (READY at priority >= 0) on the guest."""
    out = m.tool("amiga_dos_command", command="DH1:bbtools/tasklist")
    if "TASKS" not in out:
        return None                     # no tasklist on this guest (os4guest.py setup installs it)
    bad = suspect_tasks(out)
    if bad:
        sys.stderr.write("os4guest: WARNING: busy on the guest before this session (READY, priority >= 0): %s\n"
                         % "; ".join("%s%s pri %d" % (n, " [%s]" % c if c else "", p) for n, c, p in bad))
    return bad


@contextlib.contextmanager
def testing(message):
    if os.environ.get("BB_BANNER") == "0":
        yield
        return
    sys.path.insert(0, os.path.join(AMIGA_MCP, "scripts"))
    import claude_busy
    claude_busy.LOCK = LOCK          # this guest's lock (claude_busy reads it at call time)
    from claude_busy import claude_testing
    with fifo_ticket():
        with claude_testing(URL, message):
            done = watchdog()   # timed from getting this lock, not from queueing
            SESSION["procs"] = {}
            try:
                if not bridge_alive():
                    sys.stderr.write("os4guest: the guest's bridge isn't answering (no heartbeat): not starting\n")
                    os._exit(3)
                try:
                    task_snapshot(MCP(URL, timeout=60))
                except Exception as e:
                    sys.stderr.write("os4guest: task snapshot failed: %s\n" % e)
                yield
            finally:
                try:
                    end_session(MCP(URL, timeout=60))
                except Exception as e:
                    sys.stderr.write("os4guest: cleaning up the session failed: %s\n" % e)
                done.set()      # this session's deadline ends with it


HTTP_MIN = int(os.environ.get("BB_HTTP_MIN", "16384"))
BRIDGE_MAX = int(os.environ.get("BB_BRIDGE_MAX", "100000"))
FETCH = "DH1:bbtools/bbfetch"
GATEWAYS = ("192.168.101.2", "192.168.100.2")
_server = None
_made = set()


def _serve():
    """A one-directory HTTP server on 127.0.0.1 (the guest's gateway), started on demand."""
    global _server
    if _server:
        return _server
    import http.server
    import threading
    d = tempfile.mkdtemp(prefix="os4serve-")

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=d, **k)

        def log_message(self, *a):
            pass
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    _server = (srv, d)
    return _server


def mkdirs(m, dest):
    """Create the parent directories of an Amiga path (push to a missing directory hangs)."""
    parent = dest.rsplit("/", 1)[0] if "/" in dest else None
    if not parent or parent.endswith(":") or parent in _made:
        return
    parts, cur = [], parent
    vol, rest = cur.split(":", 1)
    acc = vol + ":"
    for seg in rest.split("/"):
        if not seg:
            continue
        acc = acc + seg if acc.endswith(":") else acc + "/" + seg
        parts.append(acc)
    m.tool("amiga_dos_command", command="makedir " + " ".join('"%s"' % x for x in parts))   # OS4's MakeDir has no QUIET
    _made.add(parent)


def _ssh(cmd, timeout=60):
    import subprocess
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", SSH, cmd],
                          capture_output=True, text=True, timeout=timeout)


def _remote_serve():
    """The guest's QEMU runs on another machine: serve from a directory there (started once,
    left running, bound to that machine's loopback, which is what its guest reaches)."""
    d = "/tmp/os4serve-%s" % os.environ.get("USER", "bb")
    py = ("import socket,sys;s=socket.socket();s.settimeout(1);"
          "sys.exit(0 if s.connect_ex(('127.0.0.1',%d))==0 else 1)" % REMOTE_PORT)
    cmd = ('mkdir -p %s; python3 -c "%s" || (cd %s && nohup python3 -m http.server %d --bind 127.0.0.1 '
           '>/dev/null 2>&1 &) ; sleep 1' % (d, py, d, REMOTE_PORT))
    r = _ssh(cmd)
    if r.returncode not in (0, 1):
        raise RuntimeError("can't start the HTTP server on %s: %s" % (SSH, r.stderr.strip()))
    return d


def _fetch_timeout(size):
    """Seconds one bbfetch attempt may take: the guest fetches at several MB/s, so size at 1 MB/s
    plus 30 s; a slower one is a stalled TCP connection (they trickle at ~100 KB/s while a new
    connection runs at full speed: retry instead of waiting)."""
    return 30.0 + size / 1000000.0


def _wait_fetch(m, dest, size, limit):
    """bbfetch is still running (the bridge answers "[RUNNING]" after its own wait): wait for the
    file to appear with its full size (bbfetch renames it into place only when the CRC matched)."""
    import time
    t0 = time.time()
    while time.time() - t0 < limit:
        time.sleep(5)
        out = m.tool("amiga_dos_command", command='list "%s" LFORMAT "%%L"' % dest)
        if out.strip().split("\n")[-1].strip() == str(size):
            return "OK %d (finished late)" % size
    return "FAIL still running after %d s" % limit


def _stop_fetches(m):
    """Ctrl-C to every bbfetch still running (an older bbfetch has no deadline of its own); it
    deletes its .part file."""
    import time
    for _ in range(6):
        st = m.tool("amiga_dos_command", command="status")
        procs = re.findall(r"Process\s+(\d+): Loaded as command: \S*bbfetch", st)
        if not procs:
            return
        for p in procs:
            m.tool("amiga_dos_command", command="break %s C" % p)
        time.sleep(3)


def _slow_timeout(size):
    """The last attempt's limit, after the fast ones: a busy guest can fetch at a few hundred KB/s
    on every connection, and is then slow rather than stalled (100 KB/s plus 60 s)."""
    return 60.0 + size / 100000.0


def _fetch(m, urls, dest, size, crc):
    """Fetch with bbfetch: each URL (one per gateway) gets two attempts, the second on a new
    connection, each limited to _fetch_timeout(size) (bbfetch's own MAXSECONDS, and a wait on this
    side for an older bbfetch without one); then one slow attempt (_slow_timeout) on the first
    gateway that connected. Returns bbfetch's last answer."""
    def attempt(url, limit):
        out = m.tool("amiga_dos_command", command='%s %s "%s" %s %d' % (FETCH, url, dest, crc, int(limit)),
                     timeout=limit + 15)
        if "[RUNNING]" in out:
            out = _wait_fetch(m, dest, size, limit)
        return out

    out, reached = "", []
    for url in urls:
        for n in (1, 2):
            out = attempt(url, _fetch_timeout(size))
            if "OK %d" % size in out:
                return out
            if "FAIL connect" in out:
                break                   # this gateway isn't the guest's: the next one
            if url not in reached:
                reached.append(url)
            _stop_fetches(m)
            sys.stderr.write("os4guest: fetch attempt %d of %s: %s; %s\n" % (
                n, url, out.strip()[:110], "retrying on a new connection" if n == 1 else "next gateway"))
    if reached:
        sys.stderr.write("os4guest: one slow attempt on %s (the guest may just be busy)\n" % reached[0])
        out = attempt(reached[0], _slow_timeout(size))
        if "OK %d" % size not in out:
            _stop_fetches(m)
    return out


def http_push(m, local, dest):
    import zlib
    data = open(local, "rb").read()
    crc = "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)
    name = "%d-%s" % (os.getpid(), re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(local)))
    if SSH:
        import subprocess
        d = _remote_serve()
        subprocess.run(["scp", "-q", "-o", "BatchMode=yes", local, "%s:%s/%s" % (SSH, d, name)], check=True)
        try:
            out = _fetch(m, ["http://%s:%d/%s" % (gw, REMOTE_PORT, name) for gw in GATEWAYS], dest, len(data), crc)
            if "OK %d" % len(data) in out:
                return "pushed %s (%d bytes, HTTP via %s, crc %s)" % (dest, len(data), SSH, crc)
            raise RuntimeError("HTTP push of %s failed: %s" % (local, out.strip()))
        finally:
            _ssh("rm -f %s/%s" % (d, name))
    srv, d = _serve()
    shutil.copy(local, os.path.join(d, name))
    port = srv.server_address[1]
    try:
        out = _fetch(m, ["http://%s:%d/%s" % (gw, port, name) for gw in GATEWAYS], dest, len(data), crc)
        if "OK %d" % len(data) in out:
            return "pushed %s (%d bytes, HTTP, crc %s)" % (dest, len(data), crc)
        raise RuntimeError("HTTP push of %s failed: %s" % (local, out.strip()))
    finally:
        os.unlink(os.path.join(d, name))


_have_fetch = None


def have_fetch(m):
    global _have_fetch
    if _have_fetch is None:
        import time
        out = ""
        for _ in range(12):         # a busy guest answers "[RUNNING] ..." first: ask again
            try:
                out = m.tool("amiga_dos_command", command="list DH1:bbtools")
            except RuntimeError as e:
                out = str(e)
            if re.search(r"^bbfetch\s+\d+", out, re.M):
                _have_fetch = True
                break
            if "Directory" in out or "No information" in out or "not found" in out.lower():
                _have_fetch = False
                break
            time.sleep(5)
        else:
            raise RuntimeError("the guest doesn't answer (checking for bbfetch): %s" % out.strip()[:200])
    return _have_fetch


def push(m, local, dest):
    mkdirs(m, dest)
    size = os.path.getsize(local)
    # a remote guest's devbench reads amiga_push_file's local_path on ITS machine: use HTTP for
    # every size there (bridge_push copies the file over first when it has to)
    if (size >= HTTP_MIN or SSH) and have_fetch(m):
        return http_push(m, local, dest)
    if size > BRIDGE_MAX and os.environ.get("BB_FORCE_BRIDGE") != "1":
        raise RuntimeError("%s is %d bytes: too big for the serial bridge (it has killed the guest); "
                           "run `tools/os4guest.py setup` once to enable HTTP deploys" % (local, size))
    return bridge_push(m, local, dest)


def pull(m, amiga_path, local):
    """A (small) file from the guest to `local` over the bridge (CRC-checked); for a guest on
    another machine the devbench writes it there and it comes back with scp."""
    import subprocess
    if SSH:
        remote = "/tmp/os4pull-%d-%s" % (os.getpid(), re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(local)))
        out = m.tool("amiga_pull_file", amiga_path=amiga_path, local_path=remote)
        try:
            subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "%s:%s" % (SSH, remote), local], check=True, timeout=60)
        finally:
            _ssh("rm -f %s" % remote)
        return out
    return m.tool("amiga_pull_file", amiga_path=amiga_path, local_path=os.path.abspath(local))


def bridge_push(m, local, dest):
    # ELF files padded to a 1 KB multiple: the bridge's push can wedge on a tiny last chunk
    # (AmiForge tools/m1push.sh); trailing zeros don't matter to the ELF loader.
    src = local
    with open(local, "rb") as f:
        elf = f.read(4) == b"\x7fELF"
    tmp = None
    if elf:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.basename(local))
        tmp.close()
        shutil.copy(local, tmp.name)
        pad = (1024 - os.path.getsize(tmp.name) % 1024) % 1024
        with open(tmp.name, "ab") as f:
            f.write(b"\0" * pad)
        src = tmp.name
    try:
        path = os.path.abspath(src)
        if SSH:
            # devbench runs on the remote machine and reads the file there
            import subprocess
            d = "/tmp/os4serve-%s" % os.environ.get("USER", "bb")
            rpath = "%s/bridge-%d-%s" % (d, os.getpid(), os.path.basename(local))
            _ssh("mkdir -p %s" % d)
            subprocess.run(["scp", "-q", "-o", "BatchMode=yes", path, "%s:%s" % (SSH, rpath)], check=True)
            try:
                return m.tool("amiga_push_file", local_path=rpath, amiga_path=dest)
            finally:
                _ssh("rm -f %s" % rpath)
        return m.tool("amiga_push_file", local_path=path, amiga_path=dest)
    finally:
        if tmp:
            os.unlink(tmp.name)


ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def run_bg(m, cmd, outf, limit=None):
    """Run cmd in the background on the guest (its output to outf) and poll until a PASS/FAIL line."""
    import time
    limit = limit or float(os.environ.get("BB_TEST_TIMEOUT", "180"))
    m.tool("amiga_dos_command", command="delete %s QUIET" % outf)
    run_bg_cmd(m, "%s >%s *>%s.err" % (cmd, outf, outf))
    t0, out = time.time(), ""
    while time.time() - t0 < limit:
        time.sleep(2)
        out = m.tool("amiga_dos_command", command="type %s" % outf)
        if re.search(r"^(PASS|FAIL)\b", out, re.M):
            return out
        err = m.tool("amiga_dos_command", command="type %s.err" % outf)
        if "runtime error" in err or "error:" in err:
            return out + "\n" + err + "\nFAIL (error)"
    return out + "\nFAIL (timed out after %ds; still running on the guest)" % limit


def bas(m, src, mode):
    """Push a project (files beside it + the Module= paths, kept relative to the repo) to
    RAM:bbt/ and run it."""
    import subprocess
    src = os.path.abspath(src)
    rel = os.path.relpath(src, ROOT)
    files = []
    d = os.path.dirname(src)
    for f in sorted(os.listdir(d)):
        if os.path.splitext(f)[1].lower() in (".bas", ".bbp", ".afg", ".cls", ".bi", ".in"):
            files.append(os.path.join(d, f))
    if src.endswith(".bbp"):
        for line in open(src, encoding="latin-1"):
            mm = re.match(r"\s*(Module|Form|Class)\s*=\s*(\S+)", line, re.I)
            if mm:
                p = os.path.normpath(os.path.join(d, mm.group(2)))
                if p not in files and os.path.exists(p):
                    files.append(p)
    amiga = lambda p: "RAM:bbt/" + os.path.relpath(p, ROOT)
    dirs = sorted({os.path.dirname(amiga(p)) for p in files})
    m.tool("amiga_dos_command", command="makedir RAM:bbt " + " ".join(
        sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
    ok = True
    for f in files:
        push(m, f, amiga(f))
    rdir = os.path.dirname(amiga(src))
    if mode in ("vm", "both", "jit", "all"):
        push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing")
    if mode in ("vm", "both", "all"):
        out = run_bg(m, "RAM:bbt/boing run %s" % amiga(src), "RAM:bbt/vm.out")
        print("== vm\n" + out)
        ok &= bool(re.search(r"^PASS", out, re.M))
    if mode in ("jit", "all"):
        out = run_bg(m, "RAM:bbt/boing run --jit %s" % amiga(src), "RAM:bbt/jit.out")
        print("== jit\n" + out)
        ok &= bool(re.search(r"^PASS", out, re.M))
    if mode in ("native", "both", "all"):
        exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
        subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
        push(m, exe, rdir + "/native")
        out = run_bg(m, rdir + "/native", "RAM:bbt/native.out")
        print("== native\n" + out)
        ok &= bool(re.search(r"^PASS", out, re.M))
    return ok


def _check_user_guest(user_ok=False):
    """m1 is the user's own guest: no screenshots or monitor input there, ever (user_ok is
    ignored; it is kept so old callers still work). The kit install on m1 uses Workbench ARexx."""
    if GUEST == "m1":
        sys.exit("os4guest: no screenshots/input on BB_GUEST=m1 (the user's guest)")


def _hmp_port():
    if "hmp" not in _G:
        sys.exit("os4guest: guest %r has no QEMU monitor port (\"hmp\") in its profile" % GUEST)
    return int(os.environ.get("OS4_HMP_PORT", _G["hmp"]))


def hmp(cmd, user_ok=False, wait=1.0):
    """Send a command to the selected guest's QEMU monitor (its profile's port: local 2348
    here; m1b 2448, m1c 2548 on m1.local over ssh; never m1, the user's). Returns the reply."""
    import socket
    import subprocess
    import time
    _check_user_guest(user_ok)
    port = _hmp_port()
    if SSH:
        py = ("import socket,time;s=socket.create_connection(('127.0.0.1',%d),10);time.sleep(0.5);s.recv(65536);"
              "s.sendall(%r);time.sleep(%s);print(s.recv(65536).decode('latin-1','replace'));s.close()"
              % (port, (cmd + "\n").encode(), wait))
        r = subprocess.run(["ssh", SSH, "python3", "-c", '"%s"' % py.replace('"', '\\"')],
                           capture_output=True, text=True, timeout=60)
        return r.stdout
    sk = socket.create_connection(("127.0.0.1", port), timeout=10)
    time.sleep(0.5)
    sk.recv(65536)
    sk.sendall((cmd + "\n").encode())
    time.sleep(wait)
    out = sk.recv(65536).decode("latin-1", "replace")
    sk.close()
    return out


def mouse(dx, dy, user_ok=False, m=None):
    """Move the selected guest's mouse by (dx, dy) through its devbench (input.device on the
    guest: amiga_input_mouse_move). QEMU's monitor mouse_move does not reach the guest's
    pointer (seen on m1c), so it is not used. Refuses m1 like everything here."""
    _check_user_guest(user_ok)
    m = m or MCP(URL)
    return str(m.tool("amiga_input_mouse_move", dx=int(dx), dy=int(dy)))


def shot(m, png, user_ok=False):
    """A screenshot of the selected guest's screen as PNG (or .ppm without Pillow): wakes the
    screen blanker with a 1-pixel mouse move (the guests' blankers stay as the user set them),
    waits, then QEMU's `screendump` on that guest's monitor. Call it while holding the guest
    (inside testing()); m is its MCP client (None: one is made)."""
    import subprocess
    import time
    _check_user_guest(user_ok)
    mouse(1, 0, user_ok, m)            # wake the blanker (through the devbench, not the monitor)
    mouse(-1, 0, user_ok, m)
    time.sleep(1.5)
    if SSH:
        remote = "/tmp/bb_shot_%d.ppm" % os.getpid()
        hmp("screendump %s" % remote, user_ok, wait=2.0)
        tmp = tempfile.mktemp(suffix=".ppm")
        subprocess.run(["scp", "-q", "%s:%s" % (SSH, remote), tmp], check=True, timeout=60)
        subprocess.run(["ssh", SSH, "rm", "-f", remote], timeout=30)
    else:
        tmp = tempfile.mktemp(suffix=".ppm")
        hmp("screendump %s" % tmp, user_ok, wait=2.0)
    try:
        from PIL import Image
        Image.open(tmp).save(png)
        os.unlink(tmp)
        return png
    except ImportError:
        out = os.path.splitext(png)[0] + ".ppm"
        shutil.move(tmp, out)
        return out


def reapers(m, kill=False):
    """Grim Reaper requesters on the guest (crashed tasks): returns how many; closes them with kill."""
    out = m.tool("amiga_dos_command", command="status")
    n = out.count("GrimReaper")
    if n and kill:
        for _ in range(n):
            m.tool("amiga_dos_command", command="DH1:bbtools/ptr reaper")
    return n


def setup(m):
    """Install DH1:bbtools/bbfetch, ptr and tasklist (infra-m1b's ready-task lister, for the
    session-start snapshot): the cross-built ones (build/os4, tools/build-os4.sh)
    over the bridge when they exist (no SDK needed on the guest), else built on the guest with
    the SDK's GCC."""
    src = os.path.join(ROOT, "tools/os4/bbfetch.c")
    m.tool("amiga_dos_command", command="makedir DH1:bbtools")
    built = [os.path.join(ROOT, "build/os4", t) for t in ("bbfetch", "ptr", "tasklist")]
    if all(os.path.exists(b) for b in built):
        for b in built:
            print(bridge_push(m, b, "DH1:bbtools/" + os.path.basename(b)))
        _self_test(m)
        return
    bridge_push(m, src, "DH1:bbtools/bbfetch.c")
    bridge_push(m, os.path.join(ROOT, "tools/os4/ptr.c"), "DH1:bbtools/ptr.c")
    bridge_push(m, os.path.join(ROOT, "tools/os4/tasklist.c"), "DH1:bbtools/tasklist.c")
    # compile in the background (GCC takes longer than the bridge's 30 s command timeout)
    import time
    for tool in ("bbfetch", "ptr", "tasklist"):
        m.tool("amiga_dos_command", command="delete DH1:bbtools/%s QUIET" % tool)
        run_bg_cmd(m, "SDK:gcc/bin/gcc -mcrt=newlib -mcpu=powerpc -O2 "
               "-o DH1:bbtools/%s DH1:bbtools/%s.c -lauto >RAM:%s.log" % (tool, tool, tool))
        t0 = time.time()
        while time.time() - t0 < 900:       # GCC on the guest: 15 s to several minutes
            time.sleep(10)
            out = m.tool("amiga_dos_command", command="list DH1:bbtools/%s LFORMAT %%n" % tool)
            if out.strip().endswith(tool):
                time.sleep(3)           # let the linker close the file
                break
        else:
            print(m.tool("amiga_dos_command", command="type RAM:%s.log" % tool))
            raise RuntimeError("building %s on the guest failed" % tool)
    print(m.tool("amiga_dos_command", command="list DH1:bbtools"))
    _self_test(m)


def _self_test(m):
    global _have_fetch
    _have_fetch = None
    # self-test: a 300 KB file through HTTP, checked by CRC
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".bin")
    tmp.write(os.urandom(300000))
    tmp.close()
    import time
    t0 = time.time()
    print(http_push(m, tmp.name, "RAM:bbfetch-selftest.bin"), "in %.1f s" % (time.time() - t0))
    m.tool("amiga_dos_command", command="delete RAM:bbfetch-selftest.bin QUIET")
    os.unlink(tmp.name)


def run_script(m, cmd, outf, limit=300):
    """Run cmd in the background with its output in outf, followed by an end marker; return the
    output (without the marker) once the marker is there."""
    import time
    script = outf + ".script"
    tmp = tempfile.NamedTemporaryFile("w", delete=False, suffix=".script")
    tmp.write("%s >%s *>%s.err\necho \"__BB_DONE__\" >>%s\n" % (cmd, outf, outf, outf))
    tmp.close()
    try:
        bridge_push(m, tmp.name, script)
    finally:
        os.unlink(tmp.name)
    m.tool("amiga_dos_command", command="delete %s QUIET" % outf)
    run_bg_cmd(m, "execute %s" % script)
    t0, out = time.time(), ""
    while time.time() - t0 < limit:
        time.sleep(2)
        out = m.tool("amiga_dos_command", command="type %s" % outf)
        if "__BB_DONE__" in out:
            err = m.tool("amiga_dos_command", command="type %s.err" % outf)
            body = out.split("__BB_DONE__")[0].replace("\r", "")
            if err.strip() and "[OK]" not in err:
                body += err.replace("\r", "")
            return body
    return out + "\n(timed out after %ds)" % limit


def outtest(m, src, mode):
    import subprocess
    src = os.path.abspath(src)
    expected = open(os.path.splitext(src)[0] + ".out", encoding="latin-1").read()
    base = os.path.splitext(os.path.basename(src))[0]
    d = "RAM:bbt/" + base
    push(m, src, d + "/" + base + ".bas")
    for extra in (".in",):
        if os.path.exists(os.path.splitext(src)[0] + extra):
            push(m, os.path.splitext(src)[0] + extra, d + "/" + base + extra)
    ok = True
    runs = []
    if mode in ("vm", "both"):
        push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbt/boing")
        runs.append(("vm", "RAM:bbt/boing run %s/%s.bas" % (d, base)))
    if mode in ("native", "both"):
        exe = os.path.join(ROOT, "build/os4", base + ".exe")
        subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
        push(m, exe, d + "/" + base)
        runs.append(("native", "%s/%s" % (d, base)))
    for label, cmd in runs:
        got = run_script(m, cmd, "%s/%s.%s.out" % (d, base, label))
        g2 = "\n".join(l.rstrip() for l in got.strip("\n").split("\n"))
        e2 = "\n".join(l.rstrip() for l in expected.strip("\n").split("\n"))
        same = g2 == e2
        ok &= same
        print("== %s %s: %s" % (base, label, "PASS (== %s.out)" % base if same else "FAIL"))
        if not same:
            import difflib
            print("\n".join(difflib.unified_diff(e2.split("\n"), g2.split("\n"), "expected", "guest", lineterm="", n=1)))
    return ok


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd, args = sys.argv[1], sys.argv[2:]
    m = MCP(URL)
    if cmd == "tool":
        print(m.tool(args[0], **(json.loads(args[1]) if len(args) > 1 else {})))
        return 0
    with testing("Boing BASIC tests"):
        if cmd == "push":
            for i in range(0, len(args), 2):
                print(push(m, args[i], args[i + 1]))
        elif cmd == "dos":
            print(m.tool("amiga_dos_command", command=args[0]))
        elif cmd == "shot":
            print("screenshot", shot(m, args[0]))
        elif cmd == "mouse":
            print(mouse(args[0], args[1], m=m).strip())
        elif cmd == "setup":
            setup(m)
        elif cmd == "reapers":
            n = reapers(m, kill="--kill" in args)
            print("%d Grim Reaper requester(s)%s" % (n, " closed" if n and "--kill" in args else ""))
            return 1 if n else 0
        elif cmd == "outtest":
            ok = outtest(m, args[0], args[1] if len(args) > 1 else "both")
            n = reapers(m, kill=os.environ.get("BB_KILL_REAPERS") == "1")
            if n:
                print("GRIM REAPER: %d crashed task(s) on the guest" % n)
                return 1
            return 0 if ok else 1
        elif cmd == "bas":
            ok = bas(m, args[0], args[1] if len(args) > 1 else "both")
            n = reapers(m, kill=os.environ.get("BB_KILL_REAPERS") == "1")
            if n:
                print("GRIM REAPER: %d crashed task(s) on the guest" % n)
                return 1
            return 0 if ok else 1
        elif cmd == "test":
            # run it in the background with its output in a file, and poll: a test stuck in a
            # requester must not block the bridge's shell
            import time
            name = os.path.basename(args[0])
            outf = "RAM:bbtest/%s.out" % name
            m.tool("amiga_dos_command", command="makedir RAM:bbtest")
            push(m, args[0], "RAM:bbtest/" + name)
            m.tool("amiga_dos_command", command="delete %s QUIET" % outf)
            if os.environ.get("BB_SYNC") == "1":
                # in the bridge's own shell (its stack, no background CLI); a hang blocks the bridge
                print(m.tool("amiga_dos_command", command=" ".join(["RAM:bbtest/" + name] + args[1:])))
                return 0
            run_bg_cmd(m, "%s >%s" % (" ".join(["RAM:bbtest/" + name] + args[1:]), outf))
            limit = float(os.environ.get("BB_TEST_TIMEOUT", "180"))
            t0, out, hmp_done = time.time(), "", 0
            while time.time() - t0 < limit:
                time.sleep(2)
                out = m.tool("amiga_dos_command", command="type %s" % outf)
                # "# HMP: cmd; sleep 1.5; cmd" lines: input at the QEMU level (mouse buttons, held
                # keys), which a test can't inject safely itself while a menu is up. A whole
                # sequence is one line, so nothing is polled through the bridge in between.
                lines = re.findall(r"^# HMP: (.*)$", out, re.M)
                for line in lines[hmp_done:]:
                    for c in [x.strip() for x in line.split(";") if x.strip()]:
                        if c.startswith("sleep "):
                            time.sleep(float(c.split()[1]))
                        else:
                            hmp(c, wait=0.2)
                hmp_done = len(lines)
                if re.search(r"^(PASS|FAIL)\b", out, re.M):
                    break
            else:
                out += "\nFAIL (timed out after %ds; the test is still running on the guest)" % limit
            print(out)
            n = reapers(m, kill=os.environ.get("BB_KILL_REAPERS") == "1")
            if n:
                print("GRIM REAPER: %d crashed task(s) on the guest%s" % (n, " (closed)" if os.environ.get("BB_KILL_REAPERS") == "1" else " - close them (reapers --kill)"))
                return 1
            return 0 if re.search(r"^PASS\b", out, re.M) else 1
        else:
            print(__doc__)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

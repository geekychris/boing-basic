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
    tools/os4guest.py test LOCAL_TEST_BINARY [args]   push to RAM:bbtest/ and run it, exit 1 on FAIL
    tools/os4guest.py bas PROJECT.bbp|PROG.bas [vm|jit|native|both|all]
                                                      run a BASIC test with build/os4/boing (VM)
                                                      and/or natively built; exit 1 unless PASS
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
    def __init__(self, url):
        self.url, self.sid = url, None

    def _post(self, body):
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["mcp-session-id"] = self.sid
        with urllib.request.urlopen(urllib.request.Request(self.url, json.dumps(body).encode(), h),
                                    timeout=600) as r:
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
    """leave the process (which releases the emulator lock); tests replace this"""
    sys.stderr.write("os4guest: giving up the guest: %s\n" % why)
    sys.stderr.flush()
    os._exit(3)


def watchdog():
    """Give up the guest if the bridge goes silent or this session holds it too long
    (BB_SESSION_TIMEOUT, default 300 s). Timed from this session's lock: returns a
    threading.Event that the session sets when it ends, which stops this watchdog, so every
    testing() session in a process gets a deadline of its own."""
    import threading
    import time
    silent_max = float(os.environ.get("BB_SILENT", "90"))
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


def bridge_alive(max_age=60):
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
            try:
                if not bridge_alive():
                    sys.stderr.write("os4guest: the guest's bridge isn't answering (no heartbeat): not starting\n")
                    os._exit(3)
                yield
            finally:
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
    m.tool("amiga_dos_command", command="makedir " + " ".join('"%s"' % x for x in parts) + " QUIET")
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


def http_push(m, local, dest):
    import zlib
    if SSH:
        import subprocess
        d = _remote_serve()
        name = "%d-%s" % (os.getpid(), re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(local)))
        subprocess.run(["scp", "-q", "-o", "BatchMode=yes", local, "%s:%s/%s" % (SSH, d, name)], check=True)
        data = open(local, "rb").read()
        crc = "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)
        try:
            out = ""
            for gw in GATEWAYS:
                out = m.tool("amiga_dos_command", command='%s http://%s:%d/%s "%s" %s' %
                             (FETCH, gw, REMOTE_PORT, name, dest, crc))
                if "OK %d" % len(data) in out:
                    return "pushed %s (%d bytes, HTTP via %s, crc %s)" % (dest, len(data), SSH, crc)
            raise RuntimeError("HTTP push of %s failed: %s" % (local, out.strip()))
        finally:
            _ssh("rm -f %s/%s" % (d, name))
    srv, d = _serve()
    name = "%d-%s" % (os.getpid(), re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(local)))
    shutil.copy(local, os.path.join(d, name))
    data = open(local, "rb").read()
    crc = "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)
    port = srv.server_address[1]
    try:
        out = ""
        for gw in GATEWAYS:
            out = m.tool("amiga_dos_command", command='%s http://%s:%d/%s "%s" %s' % (FETCH, gw, port, name, dest, crc))
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
    m.tool("amiga_dos_command", command="run >NIL: %s >%s *>%s.err" % (cmd, outf, outf))
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
    """Install DH1:bbtools/bbfetch and ptr: the cross-built ones (build/os4, tools/build-os4.sh)
    over the bridge when they exist (no SDK needed on the guest), else built on the guest with
    the SDK's GCC."""
    src = os.path.join(ROOT, "tools/os4/bbfetch.c")
    m.tool("amiga_dos_command", command="makedir DH1:bbtools QUIET")
    built = [os.path.join(ROOT, "build/os4", t) for t in ("bbfetch", "ptr")]
    if all(os.path.exists(b) for b in built):
        for b in built:
            print(bridge_push(m, b, "DH1:bbtools/" + os.path.basename(b)))
        _self_test(m)
        return
    bridge_push(m, src, "DH1:bbtools/bbfetch.c")
    bridge_push(m, os.path.join(ROOT, "tools/os4/ptr.c"), "DH1:bbtools/ptr.c")
    # compile in the background (GCC takes longer than the bridge's 30 s command timeout)
    import time
    for tool in ("bbfetch", "ptr"):
        m.tool("amiga_dos_command", command="delete DH1:bbtools/%s QUIET" % tool)
        m.tool("amiga_dos_command", command="run >NIL: SDK:gcc/bin/gcc -mcrt=newlib -mcpu=powerpc -O2 "
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
            m.tool("amiga_dos_command", command="run >NIL: %s >%s" % (" ".join(["RAM:bbtest/" + name] + args[1:]), outf))
            limit = float(os.environ.get("BB_TEST_TIMEOUT", "180"))
            t0, out = time.time(), ""
            while time.time() - t0 < limit:
                time.sleep(2)
                out = m.tool("amiga_dos_command", command="type %s" % outf)
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

#!/usr/bin/env python3
"""Host test of the kit tools' guards for m1, the user's guest (make test): no screenshots or
monitor input there, ever. No guest needed: the devbench URL points nowhere, and sockets and
subprocesses are blocked while the m1 checks run.

  - tools/kit/test-flow.py BB_GUEST=m1 refuses at once
  - tools/install-kit.py on m1: no screenshots (CAN_SHOOT false, screenshot() exits before any
    socket/ssh), and verify checks the desktop icon through Workbench ARexx alone
  - on m1c the installer may take screenshots (its profile has a monitor port)
"""
import os
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
os.environ["OS4_MCP"] = "http://127.0.0.1:9/mcp"
ok = True


def check(cond, what):
    global ok
    print(("PASS " if cond else "FAIL ") + "kit " + what)
    ok &= bool(cond)


# 1. the flow test refuses m1 before it does anything
t0 = time.time()
r = subprocess.run([sys.executable, os.path.join(HERE, "test-flow.py"), "BB_GUEST=m1", "glimmerfield"],
                   capture_output=True, text=True, timeout=30)
check(r.returncode != 0 and "not on BB_GUEST=m1" in r.stderr and time.time() - t0 < 10,
      "test-flow refuses BB_GUEST=m1 (rc %d: %s)" % (r.returncode, r.stderr.strip()[:80]))

# 2. on m1c the installer may take screenshots
r = subprocess.run([sys.executable, "-c", "import sys,importlib.util; sys.argv=['x','BB_GUEST=m1c'];"
                    "s=importlib.util.spec_from_file_location('ik', %r); m=importlib.util.module_from_spec(s);"
                    "s.loader.exec_module(m); print(m.CAN_SHOOT)" % os.path.join(TOOLS, "install-kit.py")],
                   capture_output=True, text=True, timeout=30)
check(r.stdout.strip() == "True", "install-kit: screenshots allowed on m1c (%s)" % r.stdout.strip())

# 3. the installer on m1: a kit directory with a manifest, then the guards
kit = tempfile.mkdtemp()
open(os.path.join(kit, "BoingBASIC.lha"), "wb").write(b"x")
open(os.path.join(kit, "KIT-MANIFEST.txt"), "w").write(
    "bb=1111111111\naf=2222222222\nentry=AmiForge\nexample=glimmerfield|Glimmerfield|game|Glimmerfield.afp|Glimmerfield.bbp|-\n")
sys.argv = ["install-kit.py", "BB_GUEST=m1", "--kit", os.path.join(kit, "BoingBASIC.lha")]
import importlib.util  # noqa: E402
spec = importlib.util.spec_from_file_location("ik", os.path.join(TOOLS, "install-kit.py"))
ik = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ik)
check(ik.CAN_SHOOT is False, "install-kit: no screenshots on m1")

opened, shots = [], []
socket.create_connection = lambda *a, **k: opened.append(("socket", a)) or (_ for _ in ()).throw(OSError("blocked"))
subprocess.run = lambda *a, **k: opened.append(("subprocess", a)) or (_ for _ in ()).throw(OSError("blocked"))
subprocess.call = subprocess.run
ik.g.shot = lambda *a, **k: shots.append(a)
ik.g.hmp = lambda *a, **k: shots.append(a)

try:
    ik.screenshot(None, os.path.join(kit, "x.png"))
    exited = False
except SystemExit:
    exited = True
check(exited and not opened and not shots, "install-kit: screenshot() on m1 exits before any socket/ssh/monitor")


class FakeGuest:
    """Answers the devbench tools the verify step uses on m1."""
    def __init__(self):
        self.calls = []

    def tool(self, name, **a):
        self.calls.append((name, a))
        if name == "amiga_arexx_send":
            c = a["command"]
            answers = {"HELP": "ACTIVATEWINDOW ICON MENU WINDOW",
                       "GETATTR OBJECT WINDOW.SCREEN.WIDTH NAME ROOT": "1280",
                       "GETATTR OBJECT WINDOW.SCREEN.HEIGHT NAME ROOT": "720",
                       "GETATTR OBJECT WINDOW.ICONS.ALL.COUNT NAME ROOT": "2",
                       "GETATTR OBJECT WINDOW.ICONS.ALL.0.NAME NAME ROOT": "chris",
                       "GETATTR OBJECT WINDOW.ICONS.ALL.1.NAME NAME ROOT": "AmiForge",
                       "GETATTR OBJECT WINDOW.ICONS.ALL.1.LEFT NAME ROOT": "1160",
                       "GETATTR OBJECT WINDOW.ICONS.ALL.1.TOP NAME ROOT": "468"}
            return "[OK] " + answers[c] if c in answers else "[RC=10] Command failed"
        if name == "amiga_dos_command":
            c = a["command"]
            if c.startswith("version"):
                return "AmiForge 0.3.1 (11/08/2026)"
            if "KIT-MANIFEST" in c:
                return "bb=1111111111\naf=2222222222\n"
            if ".backdrop" in c:
                return ":BoingBASIC/AmiForge\n"
            if c == "status":
                return "Process  1: Loaded as command: DH1:amiga-bridge\n"
        return ""


fake = FakeGuest()
ik.script = lambda m, name, lines, limit=0: "Boing BASIC 0.1 CHECK-OK"
good = ik.verify(fake)
check(good and not shots and not opened, "install-kit: verify on m1 passes with Workbench ARexx alone (no screenshot)")
asked = [c[1]["command"] for c in fake.calls if c[0] == "amiga_arexx_send"]
check(any("ICONS.ALL.1.LEFT" in c for c in asked), "install-kit: verify on m1 reads the icon's place from Workbench")
check(not any(c[0].startswith("amiga_input") or c[0] == "amiga_screenshot" for c in fake.calls),
      "install-kit: verify on m1 sends no input and takes no screenshot through the bridge")

# the icon off the screen fails the check
fake2 = FakeGuest()
real = fake2.tool
fake2.tool = lambda name, **a: ("[OK] 1900" if a.get("command", "").endswith("ALL.1.LEFT NAME ROOT") else real(name, **a))
check(not ik.icon_on_screen(fake2), "install-kit: an icon outside the screen fails the check")

# the installer doesn't start on a guest with a Grim Reaper or a silent Workbench
class SickGuest(FakeGuest):
    def __init__(self, reaper, wb):
        FakeGuest.__init__(self)
        self.reaper, self.wb = reaper, wb

    def tool(self, name, **a):
        if name == "amiga_dos_command" and a["command"] == "status":
            return "Process  5: Loaded as command: SYS:System/GrimReaper\n" if self.reaper else ""
        if name == "amiga_arexx_send" and not self.wb:
            return "Timeout waiting for ARexx result"
        if name == "amiga_dos_command" and a["command"].startswith("info"):
            raise AssertionError("got past the preflight")
        return FakeGuest.tool(self, name, **a)


for reaper, wb, what in ((True, True, "a Grim Reaper"), (False, False, "a silent Workbench")):
    sick = SickGuest(reaper, wb)
    try:
        ik.install(sick, "prepare")
        refused = False
    except RuntimeError as e:
        refused = "not installing" in str(e)
    except AssertionError:
        refused = False
    check(refused and not opened, "install-kit: refuses to start on a guest with %s" % what)

# the swap script, run by a small AmigaDOS model (Rename/If EXISTS/Set/Quit/Echo/MakeDir/Delete):
# a normal swap, an old file in use, a new file that won't move in -> the old install stays whole
def run_dos(lines, fs, locked=(), stuck=(), failcopy=(), unpack=None):
    """fs: set of paths (dirs and files, 'DH1:a/b'). locked: old paths Rename can't move;
    stuck: new paths Rename can't move. Returns the Echo output."""
    out, env, stack, rc = [], {}, [], [0]
    def active():
        return all(stack)
    def exists(p):
        p = p.strip('"')
        return p in fs or any(x.startswith(p + "/") for x in fs)
    for raw in lines:
        t = raw.strip()
        w = t.split()
        if not w:
            continue
        cmd = w[0].lower()
        if cmd == "if":
            if not active():
                stack.append(False); continue
            if w[1] == "WARN":
                stack.append(rc[0] >= 5)
            elif w[1] == "EXISTS":
                stack.append(exists(w[2]))
            elif w[1] == "NOT":
                stack.append(not exists(w[3]))
            else:
                var = w[1].strip('"').lstrip("$")
                stack.append(env.get(var) == w[3].strip('"'))
            continue
        if cmd == "else":
            parent = all(stack[:-1])
            stack[-1] = parent and not stack[-1]
            continue
        if cmd == "endif":
            stack.pop(); continue
        if not active():
            continue
        if cmd == "set":
            env[w[1]] = w[2]
        elif cmd == "echo" and len(w) > 1 and w[1].startswith(">"):
            fs.add(w[1].lstrip(">"))
        elif cmd == "echo":
            out.append(t[5:].strip('"'))
        elif cmd == "quit":
            break
        elif cmd == "makedir":
            fs.add(w[1])
        elif cmd == "delete":
            d = w[1].strip('"')
            if d == "RAM:bbkit/kitbad":
                fs.discard(d)
            for x in [x for x in fs if x == d or x.startswith(d + "/")]:
                fs.discard(x)
        elif cmd == "copy" and "TO" in w:
            a, b = w[1].strip('"'), w[w.index("TO") + 1].strip('"')
            if not exists(a) or any(b.startswith(f) for f in failcopy):
                rc[0] = 10
                continue
            rc[0] = 0
            for x in [x for x in fs if x == a or x.startswith(a + "/")]:
                fs.add(b + x[len(a):])
        elif cmd == "xadunfile":
            dest = [x for x in w if x.startswith("DEST=")][0][5:]
            fs.update(dest + "/" + x for x in (unpack or []))
        elif cmd == "rename":
            a, b = w[1].strip('"'), w[2].strip('"')
            if a in locked or a in stuck or not exists(a):
                continue
            for x in [x for x in fs if x == a or x.startswith(a + "/")]:
                fs.discard(x)
                fs.add(b + x[len(a):])
    return out


OLD = ["AmiForge", "AmiForge.info", "Examples", "boing", "MyProjects"]
NEW = ["AmiForge", "AmiForge.info", "Examples", "boing", "lib", "KIT-MANIFEST.txt"]
check("KIT-MANIFEST.txt" in ik.new_entries(), "install-kit: the manifest is one of the entries it moves in")


def disk():
    fs = {"DH1:BoingBASIC"} | {"DH1:BoingBASIC/" + e for e in OLD} | {"DH1:BoingBASIC/Examples/old.afp",
                                                                      "DH1:BoingBASIC/MyProjects/mine.bas"}
    fs |= {"DH1:BBkit-new", "DH1:BBkit-new/BoingBASIC"} | {"DH1:BBkit-new/BoingBASIC/" + e for e in NEW}
    fs.add("DH1:BBkit-new/BoingBASIC/Examples/new.afp")
    return fs


fs = disk()
out = run_dos(ik.swap_lines(OLD, NEW), fs)
check(not any("FAIL" in o for o in out) and "DH1:BoingBASIC/Examples/new.afp" in fs and
      "DH1:BoingBASIC/Examples/old.afp" not in fs and "DH1:BoingBASIC/MyProjects/mine.bas" in fs and
      all("DH1:BoingBASIC/" + e in fs for e in NEW),
      "install-kit swap: the new kit moves in, MyProjects stays")

fs = disk()
out = run_dos(ik.swap_lines(OLD, NEW), fs, locked={"DH1:BoingBASIC/boing"})
check(any("rolled back" in o for o in out) and "DH1:BoingBASIC/Examples/old.afp" in fs and
      all("DH1:BoingBASIC/" + e in fs for e in OLD) and "DH1:BoingBASIC/lib" not in fs,
      "install-kit swap: an old file in use rolls back to the old install, whole")

fs = disk()
out = run_dos(ik.swap_lines(OLD, NEW), fs, stuck={"DH1:BBkit-new/BoingBASIC/lib"})
check(any("rolled back" in o for o in out) and "DH1:BoingBASIC/Examples/old.afp" in fs and
      all("DH1:BoingBASIC/" + e in fs for e in OLD) and "DH1:BoingBASIC/KIT-MANIFEST.txt" not in fs and
      "DH1:BBkit-new/BoingBASIC/KIT-MANIFEST.txt" in fs,
      "install-kit swap: a new file that won't move in rolls back to the old install, whole")

# staging in RAM: (DH1 short): old contents backed up to RAM:, replaced on DH1, rolled back on failure
NEWTREE = ["BoingBASIC"] + ["BoingBASIC/" + e for e in NEW] + ["BoingBASIC/Examples/new.afp"]


def disk_ram():
    fs = {"DH1:BoingBASIC"} | {"DH1:BoingBASIC/" + e for e in OLD} | {"DH1:BoingBASIC/Examples/old.afp",
                                                                      "DH1:BoingBASIC/MyProjects/mine.bas"}
    return fs


fs = disk_ram()
out = run_dos(ik.ram_swap_lines(OLD, NEW, True), fs, unpack=NEWTREE)
check(not any("FAIL" in o for o in out) and "INSTALL-OK" in out and "DH1:BoingBASIC/Examples/new.afp" in fs
      and "DH1:BoingBASIC/Examples/old.afp" not in fs and "DH1:BoingBASIC/MyProjects/mine.bas" in fs
      and all("DH1:BoingBASIC/" + e in fs for e in NEW) and not any(x.startswith("RAM:BoingBASIC-old") for x in fs)
      and not any(x.startswith("RAM:BBkit-new") for x in fs),
      "install-kit RAM: staging: the new kit replaces the old on DH1, MyProjects stays, RAM: is cleaned up")
fs = disk_ram()
out = run_dos(ik.ram_swap_lines(OLD, NEW, True), fs, unpack=NEWTREE, failcopy={"DH1:BoingBASIC/lib"})
check(any("rolled back" in o for o in out) and "DH1:BoingBASIC/Examples/old.afp" in fs
      and all("DH1:BoingBASIC/" + e in fs for e in OLD) and "DH1:BoingBASIC/lib" not in fs
      and "DH1:BoingBASIC/KIT-MANIFEST.txt" not in fs and "DH1:BoingBASIC/MyProjects/mine.bas" in fs,
      "install-kit RAM: staging: a copy that fails (disk full) rolls back to the old install from RAM:")
fs = disk_ram()
out = run_dos(ik.ram_swap_lines(OLD, NEW, True), fs, unpack=NEWTREE, failcopy={"RAM:BoingBASIC-old/Examples"})
check(any("nothing changed" in o for o in out) and "DH1:BoingBASIC/Examples/old.afp" in fs
      and all("DH1:BoingBASIC/" + e in fs for e in OLD) and "DH1:BoingBASIC/lib" not in fs,
      "install-kit RAM: staging: a backup that fails stops before DH1 is touched")
fs = set()
out = run_dos(ik.ram_swap_lines([], NEW, False), fs, unpack=NEWTREE)
check("INSTALL-OK" in out and all("DH1:BoingBASIC/" + e in fs for e in NEW), "install-kit RAM: staging: a first install")


# where to stage: DH1 when it has room for a second kit, else RAM:
class SpaceGuest(FakeGuest):
    def __init__(self, free_mb, old_mb, ram_mb=980):
        FakeGuest.__init__(self)
        self.free, self.old, self.ram = free_mb, old_mb, ram_mb

    def tool(self, name, **a):
        c = a.get("command", "")
        if c.startswith("info"):
            return "DH1: 511M 400,000 %d,000  %d%%  0 Read/Write chris" % (self.free, 100 - self.free * 100 // 511)
        if c.startswith('list "DH1:BoingBASIC" LFORMAT'):
            return "AmiForge\nExamples\nMyProjects\n"
        if c.startswith("avail"):
            return "Type  Available    In-Use   Maximum   Largest\nfast  %d  1000  2000  3000\n" % (self.ram << 20)
        return FakeGuest.tool(self, name, **a)


ik.unpacked_size = lambda: 64 << 20
_pull_size = {}
ik.g.pull = lambda m, amiga_path, local: open(local, "w").write("%d\n%d\n" % (m.old << 19, m.old << 19))
ik.free_bytes = lambda info: int(info.split()[3].split(",")[0]) << 20     # "DH1: 511M used free,000 ..."
mode_disk = ik.choose_mode(SpaceGuest(100, 57))[0]
mode_ram, need_ram = ik.choose_mode(SpaceGuest(51, 57))
try:
    ik.choose_mode(SpaceGuest(10, 57))
    refused = False
except RuntimeError as e:
    refused = "even staged in RAM" in str(e)
check(mode_disk == "disk" and mode_ram == "ram" and need_ram == (7 + 16) << 20 and refused,
      "install-kit: DH1 staging with room for a second kit, RAM: staging when short (needs new - old + 16 MB), "
      "a refusal below that (%s, %s %d MB)" % (mode_disk, mode_ram, need_ram >> 20))

print("PASS kit guards" if ok else "FAIL kit guards")
sys.exit(0 if ok else 1)

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
    "bb=1111111111\naf=2222222222\nexample=glimmerfield|Glimmerfield|game|Glimmerfield.afp|Glimmerfield.bbp|-\n")
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
        ik.install(sick)
        refused = False
    except RuntimeError as e:
        refused = "not installing" in str(e)
    except AssertionError:
        refused = False
    check(refused and not opened, "install-kit: refuses to start on a guest with %s" % what)

print("PASS kit guards" if ok else "FAIL kit guards")
sys.exit(0 if ok else 1)

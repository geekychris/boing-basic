#!/usr/bin/env python3
"""test-flow.py BB_GUEST=NAME [PROJECT ...] - the user's flow with an installed kit, on the guest:
start AmiForge from its desktop icon (Workbench ARexx ICON ... OPEN; if that doesn't start it,
WBRun DH1:BoingBASIC/AmiForge, which starts it as Workbench does, with the icon's stack), show
Project > Browse Projects (Amiga-U), open each example project, Run it interpreted for a while,
stop it, and quit AmiForge. Screenshots of each step go to build/kit/flow-<guest>/.

PROJECT: an example drawer name (default: glimmerfield stack_tower_bb tincture riffwright).
Projects are split over sessions of BB_FLOW_PER_SESSION (1) (each a FIFO ticket + lock, AmiForge started and quit in
each), so no session runs much over BB_SESSION_TIMEOUT (300 s). Exit 0 when every project opened
and ran, AmiForge quit, and there is no Grim Reaper.
"""
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
names = []
for a in sys.argv[1:]:
    if a.startswith("BB_GUEST="):
        os.environ["BB_GUEST"] = a.split("=", 1)[1]
    else:
        names.append(a)
if os.environ.get("BB_GUEST", "local") == "m1":
    # m1 is the user's guest: this test starts AmiForge and programs there and needs screenshots
    sys.exit("flow: not on BB_GUEST=m1 (the user's guest); run it on m1b or m1c")
os.environ.setdefault("BB_SESSION_TIMEOUT", "330")
sys.path.insert(0, os.path.dirname(HERE))
import os4guest as g  # noqa: E402

RUN_SECONDS = int(os.environ.get("BB_FLOW_RUN", "25"))
OUT = os.path.join(ROOT, "build", "kit", "flow-%s" % g.GUEST)
DEST = "DH1:BoingBASIC"
names = names or ["glimmerfield", "stack_tower_bb", "tincture", "riffwright"]


def log(*a):
    print("flow:", *a, flush=True)


def amiga_key(m, *codes):
    """Raw keys through the bridge's input.device injection (it keeps the qualifier state, so
    0x67 down, 0x16 down/up, 0x67 up is Right-Amiga+U); codes > 0xff are only pressed, then
    released after the others."""
    held = []
    for c in codes:
        m.tool("amiga_input_key", rawkey="%02x" % (c & 0xff), direction="down")
        if c > 0xff:
            held.append(c & 0xff)
        else:
            m.tool("amiga_input_key", rawkey="%02x" % c, direction="up")
    for c in reversed(held):
        m.tool("amiga_input_key", rawkey="%02x" % c, direction="up")


RAMIGA, KEY_U, ESC = 0x167, 0x16, 0x45


def shot(m, name):
    os.makedirs(OUT, exist_ok=True)
    out = g.shot(m, os.path.join(OUT, name + ".png"))     # os4guest refuses m1
    log("screenshot", out)
    return out


def af(m, cmd):
    try:
        return m.tool("amiga_arexx_send", port="AMIFORGE", command=cmd)
    except RuntimeError as e:
        return "[ERR] %s" % e


def has_port(m, name):
    try:
        return re.search(r"^\s*%s\s*$" % name, m.tool("amiga_arexx_ports"), re.M) is not None
    except RuntimeError:
        return False


def tasks(m):
    return m.tool("amiga_dos_command", command="status")


def start_amiforge(m):
    if has_port(m, "AMIFORGE"):
        raise RuntimeError("an AmiForge is already running on the guest (someone else's?): not touching it")
    ways = [("Workbench ARexx ICON OPEN", lambda: m.tool("amiga_arexx_send", port="WORKBENCH",
                                                        command="ICON WINDOW ROOT NAMES AmiForge SELECT OPEN")),
            ("WBRun (as Workbench starts it)", lambda: g.run_bg_cmd(m, "C:WBRun %s/AmiForge" % DEST))]
    for (what, do), wait in zip(ways, (10, 30)):
        log("start AmiForge: %s: %s" % (what, do()))
        for _ in range(wait):
            time.sleep(2)
            if has_port(m, "AMIFORGE"):
                time.sleep(3)
                log("AmiForge is up (%s)" % what)
                return what
    raise RuntimeError("AmiForge didn't open its ARexx port")


def quit_amiforge(m):
    af(m, "QUIT FORCE")
    for _ in range(20):
        time.sleep(2)
        if not has_port(m, "AMIFORGE"):
            log("AmiForge quit")
            return True
    log("AmiForge did NOT quit")
    return False


def run_project(m, d, afp):
    path = "%s/Examples/%s/%s" % (DEST, d, afp)
    r = af(m, "OPENPROJECT %s" % path)
    log("OPENPROJECT %s: %s" % (path, r))
    if "[OK]" not in r:
        return False
    time.sleep(2)
    before = tasks(m)
    r = af(m, "RUN")
    log("RUN (interpreted):", r)
    time.sleep(RUN_SECONDS)
    shot(m, "run-%s" % d)
    during = tasks(m)
    running = "boing" in during.lower() and during.lower().count("boing") > before.lower().count("boing")
    log("boing running during the run: %s" % ("yes" if running else "NO"))
    r = af(m, "STOPPROGRAM")
    log("STOPPROGRAM:", r)
    for _ in range(10):
        time.sleep(2)
        if tasks(m).lower().count("boing") <= before.lower().count("boing"):
            break
    else:
        log("the program didn't stop: closing it with Esc")
        amiga_key(m, ESC)
        time.sleep(3)
    after = tasks(m)
    stopped = after.lower().count("boing") <= before.lower().count("boing")
    log("stopped: %s" % ("yes" if stopped else "NO"))
    return running and stopped


def main():
    man = {}
    for line in open(os.path.join(ROOT, "build", "kit", "KIT-MANIFEST.txt"), encoding="latin-1"):
        if line.startswith("example="):
            d, name, kind, afp, bbp, nat = line.strip().split("=", 1)[1].split("|")
            man[d] = afp
    ok = True
    m = g.MCP(g.URL)
    per = int(os.environ.get("BB_FLOW_PER_SESSION", "1"))
    if len(names) > per:
        # one process per guest session: os4guest's watchdog thread is timed from the first lock
        for i in range(0, len(names), per):
            env = dict(os.environ, BB_FLOW_FIRST="1" if i == 0 else "0")
            ok &= subprocess.call([sys.executable, os.path.abspath(__file__), "BB_GUEST=" + g.GUEST]
                                  + names[i:i + per], env=env) == 0
        log("ALL OK" if ok else "SOME STEPS FAILED")
        return 0 if ok else 1
    for i in range(0, len(names), per):
        group = names[i:i + per]
        with g.testing("AmiForge + Boing BASIC: user flow (%s)" % ", ".join(group)):
            try:
                start_amiforge(m)
                shot(m, "amiforge-%d" % i)
                if os.environ.get("BB_FLOW_FIRST", "1") == "1":
                    # a click in AmiForge's status bar makes its window the active one (WBRun leaves
                    # another window active), then Project > Browse Projects (Right-Amiga+U)
                    m.tool("amiga_input_mouse_move", dx=-3000, dy=-3000)
                    m.tool("amiga_input_mouse_move", dx=600, dy=667)
                    m.tool("amiga_input_click", button="left", direction="down")
                    m.tool("amiga_input_click", button="left", direction="up")
                    time.sleep(1)
                    amiga_key(m, RAMIGA, KEY_U)
                    time.sleep(4)
                    shot(m, "browse-projects")
                    amiga_key(m, ESC)
                    time.sleep(2)
                for d in group:
                    if d not in man:
                        log("%s isn't in the kit" % d)
                        ok = False
                        continue
                    good = run_project(m, d, man[d])
                    log("%s: %s" % (d, "OK" if good else "FAILED"))
                    ok &= good
            finally:
                ok &= quit_amiforge(m)
                n = g.reapers(m)
                log("Grim Reapers: %d" % n)
                ok &= n == 0
    log("ALL OK" if ok else "SOME STEPS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as e:
        sys.exit("flow: %s" % e)

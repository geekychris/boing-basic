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
os.environ.setdefault("BB_SESSION_TIMEOUT", "330")
sys.path.insert(0, os.path.dirname(HERE))
import os4guest as g  # noqa: E402

RUN_SECONDS = int(os.environ.get("BB_FLOW_RUN", "25"))
HMP_PORT = int(os.environ.get("OS4_HMP_PORT", {"m1b": "2349"}.get(g.GUEST, "2348")))
OUT = os.path.join(ROOT, "build", "kit", "flow-%s" % g.GUEST)
DEST = "DH1:BoingBASIC"
names = names or ["glimmerfield", "stack_tower_bb", "tincture", "riffwright"]


def log(*a):
    print("flow:", *a, flush=True)


def hmp(lines):
    data = "".join(l + "\n" for l in lines)
    cmd = (["ssh", "-o", "BatchMode=yes", g.SSH, "nc -w 3 127.0.0.1 %d >/dev/null" % HMP_PORT] if g.SSH
           else ["sh", "-c", "nc -w 3 127.0.0.1 %d >/dev/null" % HMP_PORT])
    subprocess.run(cmd, input=data.encode(), timeout=30, check=True)


def keys(*ks):
    hmp(["sendkey %s" % k for k in ks])


def shot(m, name):
    os.makedirs(OUT, exist_ok=True)
    try:
        m.tool("amiga_input_mouse_move", dx=1, dy=0)
        m.tool("amiga_input_mouse_move", dx=-1, dy=0)
    except RuntimeError:
        pass
    time.sleep(1)
    tmp = "/tmp/bbflow-%d.ppm" % os.getpid()
    out = os.path.join(OUT, name + ".png")
    hmp(["screendump %s" % tmp])
    time.sleep(1)
    if g.SSH:
        subprocess.run(["ssh", "-o", "BatchMode=yes", g.SSH, "sips -s format png %s --out %s.png >/dev/null; rm -f %s"
                        % (tmp, tmp, tmp)], check=True, timeout=60)
        subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "%s:%s.png" % (g.SSH, tmp), out], check=True)
        subprocess.run(["ssh", "-o", "BatchMode=yes", g.SSH, "rm -f %s.png" % tmp], timeout=30)
    else:
        subprocess.run(["sips", "-s", "format", "png", tmp, "--out", out], check=True, capture_output=True)
        os.unlink(tmp)
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
            ("WBRun (as Workbench starts it)", lambda: m.tool("amiga_dos_command",
                                                              command="run >NIL: C:WBRun %s/AmiForge" % DEST))]
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
        keys("esc")
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
    for i in range(0, len(names), per):
        group = names[i:i + per]
        with g.testing("AmiForge + Boing BASIC: user flow (%s)" % ", ".join(group)):
            try:
                start_amiforge(m)
                shot(m, "amiforge-%d" % i)
                if i == 0:
                    keys("meta_r-u")          # Project > Browse Projects
                    time.sleep(4)
                    shot(m, "browse-projects")
                    keys("esc")
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

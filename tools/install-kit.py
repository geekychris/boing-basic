#!/usr/bin/env python3
"""install-kit.py BB_GUEST=NAME [options] - install the Boing BASIC kit (tools/make-kit.sh) on an
AmigaOS 4 guest as DH1:BoingBASIC, put the AmiForge icon on the Workbench desktop, and verify.

    tools/install-kit.py BB_GUEST=m1                      install build/kit/BoingBASIC.lha, verify
    tools/install-kit.py BB_GUEST=m1 --verify-only        only the checks and the screenshot
    tools/install-kit.py BB_GUEST=m1 --icon-only          only the desktop icon (then the checks)
    options: --kit PATH.lha   --shot OUT.png   --no-icon   --keep-previous

Install (one guest session, FIFO ticket + emulator lock + banner, at most BB_SESSION_TIMEOUT s,
300 by default):
  - refuses while AmiForge or a program from DH1:BoingBASIC runs; checks DH1's free space
  - pushes the archive to RAM: over HTTP (os4guest.py; never the serial bridge), unpacks it to
    DH1:BBkit-new with xadUnFile, then swaps it in: the old drawer becomes DH1:BoingBASIC-previous
    (deleted unless --keep-previous; a still older one is always deleted), and the old drawer's
    MyProjects (the user's own projects) moves into the new one
  - the desktop icon: Workbench ARexx (put the left-out AmiForge away before the swap, leave the
    new one out and snapshot it after); without a usable WORKBENCH port it writes the entry
    ":BoingBASIC/AmiForge" into DH1:.backdrop itself (Workbench shows it after a reboot)
Verify (a second, short session): AmiForge's version string, `boing --version`, `boing check` of
one example, the KIT-MANIFEST revisions, the .backdrop entry, Grim Reapers, and a screenshot of the
desktop (QEMU HMP screendump; the screen blanker is woken by a 1-pixel mouse move first).

Exit status 0 when everything checks. Never touches anything outside DH1:BoingBASIC*, DH1:BBkit-new,
DH1:BoingBASIC.info, DH1:.backdrop and RAM:bbkit.
"""
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

args = []
for a in sys.argv[1:]:
    if a.startswith("BB_GUEST="):
        os.environ["BB_GUEST"] = a.split("=", 1)[1]
    else:
        args.append(a)
if "BB_GUEST" not in os.environ:
    sys.exit("install-kit: say which guest: BB_GUEST=m1 (or local, m1b, spark)")
os.environ.setdefault("BB_SESSION_TIMEOUT", "300")
sys.path.insert(0, HERE)
import os4guest as g  # noqa: E402


def opt(name, default=None):
    if name in args:
        i = args.index(name)
        return args[i + 1]
    return default


KIT = os.path.abspath(opt("--kit", os.path.join(ROOT, "build", "kit", "BoingBASIC.lha")))
SHOT = os.path.abspath(opt("--shot", os.path.join(os.path.dirname(KIT), "desktop-%s.png" % g.GUEST)))
HMP_PORT = int(os.environ.get("OS4_HMP_PORT", {"m1b": "2349"}.get(g.GUEST, "2348")))
DEST = "DH1:BoingBASIC"
ENTRY = ":BoingBASIC/AmiForge"
WB = "WORKBENCH"


def log(*a):
    print("install-kit:", *a, flush=True)


def manifest():
    p = os.path.join(os.path.dirname(KIT), "KIT-MANIFEST.txt")
    out = {"examples": []}
    if os.path.exists(p):
        for line in open(p, encoding="latin-1"):
            k, _, v = line.strip().partition("=")
            if k == "example":
                d, name, kind, afp, bbp, nat = v.split("|")
                out["examples"].append({"dir": d, "name": name, "kind": kind, "afp": afp, "bbp": bbp, "native": nat})
            elif k and not k.startswith("#"):
                out[k] = v
    return out


def unpacked_size():
    stage = os.path.join(os.path.dirname(KIT), "stage")
    if os.path.isdir(stage):
        return sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(stage) for f in fs)
    return os.path.getsize(KIT) * 3


def dos(m, cmd):
    for _ in range(6):        # a busy guest answers "[RUNNING] ..." first
        out = m.tool("amiga_dos_command", command=cmd)
        if not out.startswith("[RUNNING]"):
            return out
        time.sleep(3)
    return out


def rexx(m, cmd):
    try:
        return m.tool("amiga_arexx_send", port=WB, command=cmd)
    except RuntimeError as e:
        return "[ERR] %s" % e


def script(m, name, lines, limit=240):
    """Run an AmigaDOS script in the background on the guest (its own CLI with a real stack, so a
    long step doesn't hold the bridge's shell) and wait for its last line."""
    outf = "RAM:bbkit/%s.log" % name
    control = {"if", "else", "endif", "quit", "failat", "stack", "cd", "skip", "lab"}
    body = []
    for line in lines + ['Echo "SCRIPT-END"']:
        # output of a script started with run goes to NIL:: every command appends to the log itself
        # (AmigaDOS wants the redirection right after the command name)
        ind = line[:len(line) - len(line.lstrip())]
        parts = line.strip().split(None, 1)
        if parts and parts[0].lower() not in control and not (len(parts) > 1 and parts[1].startswith(">")):
            line = ind + parts[0] + " >>" + outf + (" " + parts[1] if len(parts) > 1 else "")
        body.append(line)
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".dos", encoding="latin-1") as f:
        f.write("FailAt 21\nStack 262144\n" + "\n".join(body) + "\n")
        local = f.name
    try:
        g.push(m, local, "RAM:bbkit/%s.dos" % name)
    finally:
        os.unlink(local)
    dos(m, "delete %s QUIET" % outf)
    dos(m, "run >NIL: execute RAM:bbkit/%s.dos" % name)
    t0, out = time.time(), ""
    while time.time() - t0 < limit:
        time.sleep(3)
        out = dos(m, "type %s" % outf)
        if "SCRIPT-END" in out:
            return out.replace("SCRIPT-END", "").strip()
    raise RuntimeError("%s: no end after %ds (still running on the guest?): %s" % (name, limit, out[-400:]))


def free_bytes(info):
    # info DH1:  ->  "DH1: 511M 398,898 124,758  76%  0 Read/Write chris" (Used/Free in blocks):
    # free = Size x (100 - Full) %
    units = {"": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30}
    for line in info.splitlines():
        if line.startswith("DH1"):
            cols = line.split()
            sz = re.match(r"([\d.]+)([KMG]?)$", cols[1]) if len(cols) > 4 else None
            full = re.match(r"(\d+)%$", cols[4]) if len(cols) > 4 else None
            if sz and full:
                return float(sz.group(1)) * units[sz.group(2)] * (100 - int(full.group(1))) / 100
    return None


def running_from_kit(m):
    st = dos(m, "status")
    hits = [l.strip() for l in st.splitlines()
            if re.search(r"AmiForge|BoingBASIC|-native\b", l, re.I)]
    return hits


def backdrop(m):
    out = dos(m, "type DH1:.backdrop")
    return out if "not found" not in out.lower() and "object not found" not in out.lower() else ""


def put_away(m):
    """The left-out AmiForge icon goes back into its drawer (Workbench drops the .backdrop entry and
    its lock on the old drawer, so the drawer can be swapped)."""
    if ENTRY.lower() not in backdrop(m).lower():
        return True
    if not wb_alive(m):
        return False
    r1 = rexx(m, "ICON WINDOW ROOT NAMES AmiForge SELECT")
    r2 = rexx(m, "MENU WINDOW ROOT INVOKE ICONS.PUTAWAY")
    time.sleep(2)
    ok = ENTRY.lower() not in backdrop(m).lower()
    log("put away the old desktop icon: %s (%s / %s)" % ("ok" if ok else "NOT done", r1, r2))
    return ok


def wb_alive(m):
    r = rexx(m, "HELP")
    if "ICON" not in r:
        log("Workbench's ARexx port doesn't answer (%s)" % r.strip()[:60])
        return False
    return True


def leave_out(m):
    """LEAVEOUT through Workbench's ARexx port; returns how it was done, or None."""
    if not wb_alive(m):
        return None
    rexx(m, "WINDOW \"%s\" OPEN" % DEST)
    time.sleep(3)
    r1 = rexx(m, "ICON WINDOW \"%s\" NAMES AmiForge SELECT" % DEST)
    r2 = rexx(m, "MENU WINDOW \"%s\" INVOKE ICONS.LEAVEOUT" % DEST)
    time.sleep(2)
    rexx(m, "WINDOW \"%s\" CLOSE" % DEST)
    if ENTRY.lower() in backdrop(m).lower():
        rexx(m, "ICON WINDOW ROOT NAMES AmiForge SELECT")
        r3 = rexx(m, "MENU WINDOW ROOT INVOKE ICONS.SNAPSHOT")
        rexx(m, "ICON WINDOW ROOT NAMES AmiForge UNSELECT")
        log("desktop icon left out through Workbench ARexx (snapshot: %s)" % r3)
        return "arexx"
    log("Workbench ARexx LEAVEOUT didn't take (%s / %s)" % (r1, r2))
    return None


def backdrop_entry(m):
    """Fallback: add the entry to DH1:.backdrop ourselves (Workbench reads it at start-up)."""
    if ENTRY.lower() in backdrop(m).lower():
        return "already"
    script(m, "backdrop", ['If EXISTS DH1:.backdrop', '  Copy DH1:.backdrop RAM:bbkit/backdrop.old QUIET', 'EndIf',
                           'Echo >>DH1:.backdrop "%s"' % ENTRY], limit=60)
    return "backdrop" if ENTRY.lower() in backdrop(m).lower() else None


def install(m):
    lha_size = os.path.getsize(KIT)
    need = lha_size + unpacked_size() + (8 << 20)
    hits = running_from_kit(m)
    if hits:
        raise RuntimeError("these run from the kit on the guest; quit them first: %s" % "; ".join(hits))
    info = dos(m, "info DH1:")
    free = free_bytes(info)
    log("DH1: free %s, the install needs about %d MB" % ("%.0f MB" % (free / 2**20) if free else "?", need >> 20))
    if free is None:
        raise RuntimeError("can't read DH1's free space: %s" % info.strip()[:300])
    if free < need:
        raise RuntimeError("DH1 has %.0f MB free, the kit needs about %.0f MB" % (free / 2**20, need / 2**20))
    dos(m, "makedir RAM:bbkit")
    t0 = time.time()
    log(g.push(m, KIT, "RAM:bbkit/BoingBASIC.lha"))
    log("pushed in %.0f s" % (time.time() - t0))
    if "--no-icon" not in args:
        put_away(m)
        rexx(m, "WINDOW \"%s\" CLOSE" % DEST)
    keep_prev = "--keep-previous" in args
    lines = [
        'If EXISTS DH1:BBkit-new', '  Delete DH1:BBkit-new ALL QUIET FORCE', 'EndIf',
        'MakeDir DH1:BBkit-new',
        'xadUnFile RAM:bbkit/BoingBASIC.lha DEST=DH1:BBkit-new QUIET',
        'If NOT EXISTS DH1:BBkit-new/BoingBASIC/AmiForge', '  Echo "INSTALL-FAIL unpack"', '  Quit 20', 'EndIf',
        'If NOT EXISTS DH1:BBkit-new/BoingBASIC/KIT-MANIFEST.txt', '  Echo "INSTALL-FAIL unpack"', '  Quit 20', 'EndIf',
        'If EXISTS DH1:BoingBASIC-previous', '  Delete DH1:BoingBASIC-previous ALL QUIET FORCE', 'EndIf',
        'If EXISTS DH1:BoingBASIC', '  Rename DH1:BoingBASIC DH1:BoingBASIC-previous', 'EndIf',
        'If EXISTS DH1:BoingBASIC', '  Echo "INSTALL-FAIL the old drawer is in use (Rename failed)"', '  Quit 20', 'EndIf',
        'Rename DH1:BBkit-new/BoingBASIC DH1:BoingBASIC',
        'Copy DH1:BBkit-new/BoingBASIC.info DH1:BoingBASIC.info CLONE QUIET',
        'If EXISTS DH1:BoingBASIC-previous/MyProjects',
        '  Rename DH1:BoingBASIC-previous/MyProjects DH1:BoingBASIC/MyProjects',
        '  If EXISTS DH1:BoingBASIC-previous/MyProjects.info',
        '    Rename DH1:BoingBASIC-previous/MyProjects.info DH1:BoingBASIC/MyProjects.info',
        '  EndIf',
        '  Echo "kept MyProjects"',
        'Else',
        '  MakeDir DH1:BoingBASIC/MyProjects',
        'EndIf',
        'If NOT EXISTS DH1:BoingBASIC/MyProjects.info',
        '  Copy DH1:BoingBASIC/Templates.info DH1:BoingBASIC/MyProjects.info CLONE QUIET',
        'EndIf',
        'Delete DH1:BBkit-new ALL QUIET FORCE',
    ]
    if not keep_prev:
        lines += ['If EXISTS DH1:BoingBASIC-previous', '  Delete DH1:BoingBASIC-previous ALL QUIET FORCE', 'EndIf']
    lines += ['Delete RAM:bbkit/BoingBASIC.lha QUIET', 'Echo "INSTALL-OK"']
    t0 = time.time()
    out = script(m, "install", lines, limit=240)
    log("unpacked and swapped in %.0f s: %s" % (time.time() - t0, " ".join(out.split())[-300:]))
    if "INSTALL-OK" not in out:
        raise RuntimeError("install failed: %s" % out[-500:])
    if "--no-icon" not in args:
        how = leave_out(m) or backdrop_entry(m)
        if how == "backdrop":
            log("wrote %s into DH1:.backdrop (the icon shows after the next Workbench start)" % ENTRY)
        elif not how:
            raise RuntimeError("couldn't put the AmiForge icon on the desktop")


def hmp(lines):
    data = "".join(l + "\n" for l in lines)
    if g.SSH:
        cmd = ["ssh", "-o", "BatchMode=yes", g.SSH, "nc -w 3 127.0.0.1 %d >/dev/null" % HMP_PORT]
    else:
        cmd = ["sh", "-c", "nc -w 3 127.0.0.1 %d >/dev/null" % HMP_PORT]
    subprocess.run(cmd, input=data.encode(), timeout=30, check=True)


def screenshot(m, out):
    try:
        m.tool("amiga_input_mouse_move", dx=1, dy=0)     # wake the screen blanker
        time.sleep(0.3)
        m.tool("amiga_input_mouse_move", dx=-1, dy=0)
    except RuntimeError:
        pass
    time.sleep(2)
    tmp = "/tmp/bbkit-shot-%d.ppm" % os.getpid()
    hmp(["screendump %s" % tmp])
    time.sleep(1)
    if g.SSH:
        subprocess.run(["ssh", "-o", "BatchMode=yes", g.SSH,
                        "sips -s format png %s --out %s.png >/dev/null 2>&1 || "
                        "python3 -c \"from PIL import Image; Image.open(\"%s\").save('%s.png')\"; rm -f %s"
                        % (tmp, tmp, tmp, tmp, tmp)], check=True, timeout=60)
        subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "%s:%s.png" % (g.SSH, tmp), out], check=True)
        subprocess.run(["ssh", "-o", "BatchMode=yes", g.SSH, "rm -f %s.png" % tmp], timeout=30)
    else:
        subprocess.run(["sips", "-s", "format", "png", tmp, "--out", out], check=True, capture_output=True)
        os.unlink(tmp)
    return out


def verify(m):
    man = manifest()
    ok = True
    v = dos(m, "version %s/AmiForge FULL" % DEST)
    log("AmiForge: %s" % " ".join(v.split())[:200])
    ok &= "AmiForge" in v
    ex = next((e for e in man["examples"] if e["dir"] == "glimmerfield"), None) or \
        (man["examples"][0] if man["examples"] else None)
    lines = ['%s/boing --version' % DEST]
    if ex:
        lines += ['CD %s/Examples/%s' % (DEST, ex["dir"]),
                  '%s/boing check %s' % (DEST, ex["bbp"]),
                  'If WARN', '  Echo "CHECK-FAIL"', 'Else', '  Echo "CHECK-OK"', 'EndIf']
    out = script(m, "verify", lines, limit=180)
    log("boing: %s" % " ".join(out.split())[:300])
    ok &= bool(re.search(r"boing|Boing", out))
    if ex:
        good = "CHECK-OK" in out and "CHECK-FAIL" not in out
        log("boing check %s/%s: %s" % (ex["dir"], ex["bbp"], "ok" if good else "FAILED"))
        ok &= good
    gm = dos(m, "type %s/KIT-MANIFEST.txt" % DEST)
    same = man.get("bb", "?") in gm and man.get("af", "?") in gm
    log("KIT-MANIFEST on the guest matches the kit (bb %s, af %s): %s"
        % (man.get("bb", "?")[:10], man.get("af", "?")[:10], "yes" if same else "NO"))
    ok &= same
    if "--no-icon" not in args:
        bd = backdrop(m)
        has = ENTRY.lower() in bd.lower()
        log("DH1:.backdrop has %s: %s" % (ENTRY, "yes" if has else "NO"))
        ok &= has
    n = g.reapers(m)
    log("Grim Reapers: %d" % n)
    ok &= n == 0
    try:
        log("desktop screenshot: %s" % screenshot(m, SHOT))
    except Exception as e:
        log("screenshot failed: %s" % e)
        ok = False
    return ok


def main():
    if "-h" in args or "--help" in args:
        print(__doc__)
        return 0
    if not os.path.exists(KIT):
        sys.exit("install-kit: no %s (run tools/make-kit.sh)" % KIT)
    m = g.MCP(g.URL)
    if "--icon-only" in args:
        with g.testing("Boing BASIC: desktop icon"):
            how = leave_out(m) or backdrop_entry(m)
            log("desktop icon: %s" % (how or "FAILED"))
        args.append("--verify-only")
    if "--verify-only" not in args:
        with g.testing("Installing Boing BASIC + AmiForge"):
            install(m)
    with g.testing("Checking the Boing BASIC install"):
        ok = verify(m)
    log("ALL OK" if ok else "SOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as e:
        sys.exit("install-kit: %s" % e)

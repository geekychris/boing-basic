#!/usr/bin/env python3
"""install-kit.py BB_GUEST=NAME [options] - install the Boing BASIC kit (tools/make-kit.sh) on an
AmigaOS 4 guest as DH1:BoingBASIC, put the AmiForge icon on the Workbench desktop, and verify.

    tools/install-kit.py BB_GUEST=m1                      install build/kit/BoingBASIC.lha, verify
    tools/install-kit.py BB_GUEST=m1 --verify-only        only the checks and the screenshot
    tools/install-kit.py BB_GUEST=m1 --icon-only          only the desktop icon (then the checks)
    options: --kit PATH.lha   --shot OUT.png   --no-icon   --check-all (boing check of every example)

Install (three guest sessions, each a FIFO ticket + emulator lock + banner, at most
BB_SESSION_TIMEOUT s, 300 by default: checks + leftovers + space, the push, then unpack + swap +
icon from the archive in RAM:; each phase re-checks the guest):
  - refuses on a guest with a Grim Reaper or a Workbench that doesn't answer ARexx, and while
    AmiForge or a program from DH1:BoingBASIC runs; deletes leftovers of an interrupted install
    (DH1:BoingBASIC-previous, DH1:BBkit-new); checks DH1's free space
  - pushes the archive to RAM: over HTTP (os4guest.py; never the serial bridge), unpacks it to
    DH1:BBkit-new with xadUnFile, then replaces the contents of DH1:BoingBASIC (the drawer itself
    stays: a left-out icon holds a lock on it), keeping the user's MyProjects
  - the desktop icon: left out through Workbench ARexx (or, re-installing, still out), then placed
    at the right edge and snapshotted; without a usable WORKBENCH port it writes the entry
    ":BoingBASIC/AmiForge" into DH1:.backdrop itself (Workbench shows it after a reboot)
Verify (a second, short session): AmiForge's version string, `boing --version`, `boing check` of
one example, the KIT-MANIFEST revisions, the .backdrop entry, Grim Reapers, and a screenshot of the
desktop (os4guest.shot; never on m1, the user's guest, where the icon's place is read through
Workbench ARexx instead).

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
# a guest script may take what the session allows, less a margin for the rest of the session
# (a slow guest needs BB_SESSION_TIMEOUT=900: unpacking alone took over 4 minutes on m1b)
SCRIPT_MAX = max(240, int(float(os.environ["BB_SESSION_TIMEOUT"])) - 90)
sys.path.insert(0, HERE)
import os4guest as g  # noqa: E402


def opt(name, default=None):
    if name in args:
        i = args.index(name)
        return args[i + 1]
    return default


KIT = os.path.abspath(opt("--kit", os.path.join(ROOT, "build", "kit", "BoingBASIC.lha")))
SHOT = os.path.abspath(opt("--shot", os.path.join(os.path.dirname(KIT), "desktop-%s.png" % g.GUEST)))
# Screenshots (QEMU monitor) only on guests whose os4guest.py profile has a monitor port; never on
# m1, the user's guest: there the icon is checked through Workbench ARexx alone.
CAN_SHOOT = g.GUEST != "m1" and "hmp" in g._G
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
            if k == "entry":
                out.setdefault("entries", []).append(v)
            elif k == "example":
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
    control = {"if", "else", "endif", "quit", "failat", "stack", "cd", "skip", "lab", "set"}
    body = []
    ended = []
    for line in lines:
        if line.strip().lower().startswith("quit"):      # a failure path still says it ended
            ended.append(line[:len(line) - len(line.lstrip())] + 'Echo "SCRIPT-END"')
        ended.append(line)
    for line in ended + ['Echo "SCRIPT-END"']:
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


def new_entries():
    """The new drawer's top-level entries: from KIT-MANIFEST (entry=), else the local stage."""
    e = manifest().get("entries")
    if e:
        return sorted(set(e) | {"KIT-MANIFEST.txt"})
    top = os.path.join(os.path.dirname(KIT), "stage", "BoingBASIC")
    if os.path.isdir(top):
        return sorted(os.listdir(top))
    raise RuntimeError("the kit's KIT-MANIFEST.txt has no entry= lines and there is no stage: rebuild the kit")


def guest_entries(m, drawer):
    """Top-level entries of a drawer on the guest (names only)."""
    out = dos(m, 'list "%s" LFORMAT "%%N" NOHEAD QUICK' % drawer)
    if "not found" in out.lower() or "no information" in out.lower():
        return []
    return [l.strip() for l in out.splitlines() if l.strip() and not l.startswith("[")]


KEEP = ("MyProjects", "MyProjects.info")        # the user's own: never moved


def q(p):
    return '"%s"' % p


def swap_lines(old, new):
    """Swap DH1:BoingBASIC's contents for DH1:BBkit-new/BoingBASIC's, reversibly: the old entries
    move to DH1:BBkit-old, the new ones move in (Rename: the same disk, no copies; the drawer
    itself stays, Workbench's left-out icon holds a lock on it); a step that doesn't take rolls
    everything back and the script ends with INSTALL-FAIL, leaving the old install as it was."""
    old = [e for e in old if e not in KEEP]
    new = [e for e in new if e not in KEEP]
    D, O, N = "DH1:BoingBASIC/", "DH1:BBkit-old/", "DH1:BBkit-new/BoingBASIC/"
    back_old = sum((['  If EXISTS %s' % q(O + e), '    Rename %s %s' % (q(O + e), q(D + e)), '  EndIf'] for e in old), [])
    back_new = sum((['  If EXISTS %s' % q(D + e), '    Rename %s %s' % (q(D + e), q(N + e)), '  EndIf'] for e in new), [])
    L = ['Delete RAM:bbkit/kitbad QUIET', 'If EXISTS DH1:BBkit-old', '  Delete DH1:BBkit-old ALL QUIET FORCE', 'EndIf', 'MakeDir DH1:BBkit-old']
    L += ['Rename %s %s' % (q(D + e), q(O + e)) for e in old]
    L += sum((['If EXISTS %s' % q(D + e), '  Echo >RAM:bbkit/kitbad "1"', 'EndIf'] for e in old), [])
    L += ['If EXISTS RAM:bbkit/kitbad'] + back_old + ['  Echo "INSTALL-FAIL an old file is in use: rolled back"', '  Quit 20', 'EndIf']
    L += ['Rename %s %s' % (q(N + e), q(D + e)) for e in new]
    L += sum((['If NOT EXISTS %s' % q(D + e), '  Echo >RAM:bbkit/kitbad "1"', 'EndIf'] for e in new), [])
    L += ['If EXISTS RAM:bbkit/kitbad'] + back_new + back_old + ['  Echo "INSTALL-FAIL a new file didn\'t move in: rolled back"',
                                                         '  Quit 20', 'EndIf']
    return L


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
        log("desktop icon left out through Workbench ARexx")
        place(m)
        return "arexx"
    log("Workbench ARexx LEAVEOUT didn't take (%s / %s)" % (r1, r2))
    return None


def place(m):
    """Put the left-out icon where it's seen (right edge, below the window area; a fresh
    AmiForge.info carries no position, and the Launcher covers the default place) and snapshot it."""
    w, h = screen_size(m)
    x, y = w - 120, int(h * 0.65)
    r = [rexx(m, "ICON WINDOW ROOT NAMES AmiForge X %d Y %d" % (x, y)),
         rexx(m, "ICON WINDOW ROOT NAMES AmiForge MAKEVISIBLE"),
         rexx(m, "ICON WINDOW ROOT NAMES AmiForge SELECT"),
         rexx(m, "MENU WINDOW ROOT INVOKE ICONS.SNAPSHOT"),
         rexx(m, "ICON WINDOW ROOT NAMES AmiForge UNSELECT")]
    log("desktop icon placed at %d,%d on a %dx%d screen and snapshotted (%s)" % (x, y, w, h, " ".join(r)))
    PLACED[:] = [x, y]
    return all(v.startswith("[OK]") for v in r)


PLACED = []


def wb_attr(m, obj, name="ROOT"):
    r = rexx(m, "GETATTR OBJECT %s NAME %s" % (obj, name))
    return r[4:].strip() if r.startswith("[OK]") else None


def screen_size(m):
    """The Workbench screen's size (Workbench ARexx: no screenshot needed)."""
    try:
        return int(wb_attr(m, "WINDOW.SCREEN.WIDTH")), int(wb_attr(m, "WINDOW.SCREEN.HEIGHT"))
    except (TypeError, ValueError):
        log("screen size unknown: using 1280x720")
        return 1280, 720


def icon_position(m):
    """(left, top) of the AmiForge icon on the Workbench backdrop, from Workbench ARexx; None if
    it isn't there."""
    try:
        n = int(wb_attr(m, "WINDOW.ICONS.ALL.COUNT"))
    except (TypeError, ValueError):
        return None
    for i in range(n):
        if wb_attr(m, "WINDOW.ICONS.ALL.%d.NAME" % i) == "AmiForge":
            try:
                return int(wb_attr(m, "WINDOW.ICONS.ALL.%d.LEFT" % i)), int(wb_attr(m, "WINDOW.ICONS.ALL.%d.TOP" % i))
            except (TypeError, ValueError):
                return None
    return None


def icon_on_screen(m):
    """The icon is on the backdrop and inside the screen (Workbench ARexx only)."""
    pos = icon_position(m)
    w, h = screen_size(m)
    ok = pos is not None and 0 <= pos[0] <= w - 32 and 0 <= pos[1] <= h - 32
    log("AmiForge icon on the Workbench backdrop at %s on a %dx%d screen: %s"
        % (pos, w, h, "yes" if ok else "NO"))
    return ok


def icon_visible(png, xy=None):
    """Is AmiForge's icon image on the screenshot (near xy when given)? Compares the opaque pixels
    of the true-colour image in the kit's AmiForge.info with every place on the screen."""
    import struct
    import zlib
    import numpy as np
    from PIL import Image
    info = os.path.join(os.path.dirname(KIT), "stage", "BoingBASIC", "AmiForge.info")
    d = open(info, "rb").read()
    images, i = [], d.find(b"ARGB")
    while i >= 0:                       # the normal and the selected image
        n = struct.unpack(">I", d[i + 4:i + 8])[0]
        raw = np.frombuffer(zlib.decompress(d[i + 18:i + 8 + n]), np.uint8).reshape(64, 64, 4)
        images.append((raw[:, :, 0] > 200, raw[:, :, 1:4].astype(np.int16)))
        i = d.find(b"ARGB", i + 8 + n)
    scr = np.asarray(Image.open(png).convert("RGB")).astype(np.int16)
    H, W = scr.shape[:2]
    if xy:
        xs, ys = range(max(0, xy[0] - 40), min(W - 64, xy[0] + 40)), range(max(0, xy[1] - 40), min(H - 64, xy[1] + 40))
    else:
        xs, ys = range(0, W - 64, 2), range(0, H - 64, 2)
    best = (1e9, None)
    for alpha, rgb in images:
        for y in ys:
            for x in xs:
                diff = np.abs(scr[y:y + 64, x:x + 64][alpha] - rgb[alpha]).mean()
                if diff < best[0]:
                    best = (diff, (x, y))
    return best[0] < 25, best


def backdrop_entry(m):
    """Fallback: add the entry to DH1:.backdrop ourselves (Workbench reads it at start-up)."""
    if ENTRY.lower() in backdrop(m).lower():
        return "already"
    script(m, "backdrop", ['If EXISTS DH1:.backdrop', '  Copy DH1:.backdrop RAM:bbkit/backdrop.old QUIET', 'EndIf',
                           'Echo >>DH1:.backdrop "%s"' % ENTRY], limit=60)
    return "backdrop" if ENTRY.lower() in backdrop(m).lower() else None


def install(m, phase):
    """Each phase is a guest session of its own (on a slow guest a cleanup or the push alone can take
    3 minutes): "prepare" the checks, leftovers of an interrupted install, the space check; "push"
    the checks and the push to RAM:; "swap" the checks, then unpack, swap and the icon from the
    archive the push left in RAM:."""
    lha_size = os.path.getsize(KIT)
    need = unpacked_size() + (8 << 20)      # the archive goes to RAM:; the old drawer goes after the swap
    # a guest with crashed tasks or a Workbench that doesn't answer ARexx has hung the swap
    # half-way before (a Copy and WBRun waiting forever): don't start on one
    n = g.reapers(m)
    if n:
        raise RuntimeError("the guest has %d Grim Reaper requester(s) (a crashed task): not installing; "
                           "restart the guest first" % n)
    if "--no-icon" not in args and not wb_alive(m):
        raise RuntimeError("Workbench doesn't answer ARexx (the desktop icon needs it): not installing; "
                           "restart the guest first")
    hits = running_from_kit(m)
    if hits:
        raise RuntimeError("these run from the kit on the guest; quit them first: %s" % "; ".join(hits))
    if phase == "swap":
        if dos(m, 'list RAM:bbkit/BoingBASIC.lha LFORMAT "%l"').strip() != str(lha_size):
            raise RuntimeError("RAM:bbkit/BoingBASIC.lha isn't there (or not this kit): the push session didn't finish")
        return swap(m)
    if phase == "push":
        return push_kit(m, lha_size, need)
    # leftovers of an interrupted install (the old drawer kept as -previous, a half-unpacked
    # BBkit-new) are deleted first: they can hold most of the space the install needs
    saved = guest_entries(m, "DH1:BBkit-old")
    if saved:
        if "AmiForge" not in guest_entries(m, DEST):
            # a swap was interrupted after the old install moved aside: put it back first
            out = script(m, "restore", ['Rename %s %s' % (q("DH1:BBkit-old/" + e), q("DH1:BoingBASIC/" + e))
                                        for e in saved], limit=120)
            log("restored the old install from DH1:BBkit-old (an interrupted swap) %s" % " ".join(out.split())[:120])
        if not guest_entries(m, "DH1:BBkit-old") or "AmiForge" in guest_entries(m, DEST):
            script(m, "oldaside", ['If EXISTS DH1:BBkit-old', '  Delete DH1:BBkit-old ALL QUIET FORCE', 'EndIf'], limit=270)
    out = script(m, "leftovers", ['If EXISTS DH1:BoingBASIC-previous', '  Delete DH1:BoingBASIC-previous ALL QUIET FORCE',
                                  '  Echo "LEFTOVER BoingBASIC-previous"', 'EndIf',
                                  'If EXISTS DH1:BBkit-new', '  Delete DH1:BBkit-new ALL QUIET FORCE',
                                  '  Echo "LEFTOVER BBkit-new"', 'EndIf'], limit=SCRIPT_MAX)   # a slow guest: 3 min
    if "LEFTOVER" in out:
        log("leftovers of an earlier install: %s%s" % (" ".join(out.split())[:160],
            " (still locked: Workbench lets go at its next start; the next install deletes it)" if "in use" in out else ""))
    check_space(m, need)


def check_space(m, need):
    info = dos(m, "info DH1:")
    free = free_bytes(info)
    log("DH1: free %s, the install needs about %d MB" % ("%.0f MB" % (free / 2**20) if free else "?", need >> 20))
    if free is None:
        raise RuntimeError("can't read DH1's free space: %s" % info.strip()[:300])
    if free < need:
        raise RuntimeError("DH1 has %.0f MB free, the kit needs about %.0f MB" % (free / 2**20, need / 2**20))


def push_kit(m, lha_size, need):
    check_space(m, need)
    dos(m, "makedir RAM:bbkit")
    t0 = time.time()
    # bbfetch renames its .part file only after the length and CRC check, so an archive of the
    # right length already in RAM:bbkit is this kit (a push that outlived its bridge command)
    if dos(m, 'list RAM:bbkit/BoingBASIC.lha LFORMAT "%l"').strip() == str(lha_size):
        log("RAM:bbkit/BoingBASIC.lha is already there (%d bytes)" % lha_size)
    else:
        log(g.push(m, KIT, "RAM:bbkit/BoingBASIC.lha"))
        log("pushed in %.0f s" % (time.time() - t0))


def swap(m):
    have = guest_entries(m, DEST)
    exists = bool(have) or "Directory" in dos(m, "list %s DIRS QUICK" % DEST)
    if "MyProjects" in have:
        log("DH1:BoingBASIC/MyProjects stays as it is (the user's projects)")
    lines = [
        'If EXISTS DH1:BBkit-new', '  Delete DH1:BBkit-new ALL QUIET FORCE', 'EndIf',
        'MakeDir DH1:BBkit-new',
        'xadUnFile RAM:bbkit/BoingBASIC.lha DEST=DH1:BBkit-new QUIET']
    # the staged kit must be complete before anything of the old install is touched
    lines += sum((['If NOT EXISTS %s' % q("DH1:BBkit-new/BoingBASIC/" + e), '  Echo "INSTALL-FAIL unpack (%s missing)"' % e,
                   '  Quit 20', 'EndIf'] for e in new_entries()), [])
    if exists:
        lines += swap_lines(guest_entries(m, DEST), new_entries())
    else:
        lines += ['Rename DH1:BBkit-new/BoingBASIC DH1:BoingBASIC']
    lines += [
        'If NOT EXISTS DH1:BoingBASIC/KIT-MANIFEST.txt', '  Echo "INSTALL-FAIL swap"', '  Quit 20', 'EndIf',
        'Copy DH1:BBkit-new/BoingBASIC.info DH1:BoingBASIC.info CLONE QUIET',
        'If NOT EXISTS DH1:BoingBASIC/MyProjects', '  MakeDir DH1:BoingBASIC/MyProjects', 'EndIf',
        'If NOT EXISTS DH1:BoingBASIC/MyProjects.info',
        '  Copy DH1:BoingBASIC/Templates.info DH1:BoingBASIC/MyProjects.info CLONE QUIET',
        'EndIf',
        'Delete DH1:BBkit-new ALL QUIET FORCE',
        'If EXISTS DH1:BBkit-old', '  Delete DH1:BBkit-old ALL QUIET FORCE', 'EndIf',
        'Delete RAM:bbkit/BoingBASIC.lha QUIET', 'Echo "INSTALL-OK"']
    t0 = time.time()
    out = script(m, "install", lines, limit=SCRIPT_MAX)
    log("unpacked and swapped in %.0f s: %s" % (time.time() - t0, " ".join(out.split())[-300:]))
    if "INSTALL-OK" not in out:
        raise RuntimeError("install failed: %s" % out[-500:])
    if "--no-icon" not in args:
        if ENTRY.lower() in backdrop(m).lower() and wb_alive(m):
            how = "placed" if place(m) else None     # still left out: its .info is new, so place it again
        else:
            how = leave_out(m) or backdrop_entry(m)
        if how == "backdrop":
            log("wrote %s into DH1:.backdrop (the icon shows after the next Workbench start)" % ENTRY)
        elif not how:
            raise RuntimeError("couldn't put the AmiForge icon on the desktop")


def screenshot(m, out):
    """A screenshot through os4guest.shot (it refuses m1, the user's guest)."""
    if not CAN_SHOOT:
        sys.exit("install-kit: no screenshots on BB_GUEST=%s" % g.GUEST)
    return g.shot(m, out)


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
    if "--check-all" in args:
        # every example with the guest's own (the kit's) boing
        for e in man["examples"]:
            lines += ['CD %s/Examples/%s' % (DEST, e["dir"]), '%s/boing check %s' % (DEST, e["bbp"]),
                      'If WARN', '  Echo "ALLCHECK-FAIL %s"' % e["dir"], 'Else', '  Echo "ALLCHECK-OK %s"' % e["dir"], 'EndIf']
        lines += ['CD RAM:']
    out = script(m, "verify", lines, limit=SCRIPT_MAX)
    log("boing: %s" % " ".join(out.split())[:300])
    ok &= bool(re.search(r"boing|Boing", out))
    if ex:
        good = "CHECK-OK" in out and "CHECK-FAIL" not in out
        log("boing check %s/%s: %s" % (ex["dir"], ex["bbp"], "ok" if good else "FAILED"))
        ok &= good
    if "--check-all" in args:
        good_all = re.findall(r"ALLCHECK-OK (\S+)", out)
        bad_all = re.findall(r"ALLCHECK-FAIL (\S+)", out)
        log("boing check of every example on the guest: %d ok%s" % (len(good_all),
            ", FAILED: " + " ".join(bad_all) if bad_all else ""))
        ok &= not bad_all and len(good_all) == len(man["examples"])
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
    if "--no-icon" not in args and wb_alive(m):
        ok &= icon_on_screen(m)
    if not CAN_SHOOT:
        log("no screenshot on BB_GUEST=%s (the user's guest): the icon was checked through Workbench ARexx"
            % g.GUEST)
        return ok
    try:
        log("desktop screenshot: %s" % screenshot(m, SHOT))
        if "--no-icon" not in args:
            seen, (diff, where) = icon_visible(SHOT)
            log("AmiForge icon visible on the desktop: %s (best match at %s, difference %.0f)"
                % ("yes" if seen else "NO", where, diff))
            ok &= seen
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
            if ENTRY.lower() in backdrop(m).lower() and wb_alive(m):
                how = "placed" if place(m) else None
            else:
                how = leave_out(m) or backdrop_entry(m)
            log("desktop icon: %s" % (how or "FAILED"))
        args.append("--verify-only")
    if "--verify-only" not in args:
        with g.testing("Installing Boing BASIC + AmiForge (checks)"):
            install(m, "prepare")
        with g.testing("Installing Boing BASIC + AmiForge (copying the kit)"):
            install(m, "push")
        with g.testing("Installing Boing BASIC + AmiForge"):
            install(m, "swap")
    if "--verify-only" not in sys.argv[1:]:
        # a new process for the second guest session: os4guest's watchdog thread is timed from the
        # first lock and would end this session early
        sys.stdout.flush()
        os.execv(sys.executable, [sys.executable, os.path.abspath(__file__), "BB_GUEST=" + g.GUEST, "--verify-only"]
                 + [a for a in args if a not in ("--icon-only", "--verify-only")])
    with g.testing("Checking the Boing BASIC install"):
        ok = verify(m)
    log("ALL OK" if ok else "SOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as e:
        sys.exit("install-kit: %s" % e)

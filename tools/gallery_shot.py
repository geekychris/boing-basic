#!/usr/bin/env python3
"""gallery_shot.py - screenshots of an example on an AmigaOS 4 guest, for docs/gallery.md.

    tools/gallery_shot.py EXAMPLE [SHOT ...] [--keep-full]

Reads examples/EXAMPLE/gallery.toml and, for each [[shot]] that has a `run` table (or the
SHOTs named), on the guest (BB_GUEST=m1b preferred; never the guest the user plays on):
  - takes a FIFO ticket, the emulator lock and the "CLAUDE IS TESTING" banner (os4guest.py),
    one ticket per shot, the session capped at 5 minutes;
  - pushes the project's files to RAM:bbdoc/<path in the repo> (its Module=/Form=/Class=
    files, the example's .bas/.bbp/.afg/.cls/.mod/.ppm files and `run.files` globs);
  - wakes the screen blanker (a 1-pixel mouse move through QEMU's monitor) and dumps the screen;
  - starts the program with `stack 1048576`: `boing run PROJECT args` (the VM) or, with
    `run.native = true`, the executable built by `boing build --target os4`;
  - waits `run.secs`, types `run.keys` (QEMU sendkey names, "sleep:N" waits N seconds),
    wakes the blanker again and dumps the screen;
  - stops the program with Ctrl-C (the runtime ends cleanly on it), checks that none of its
    processes are left and that no Grim Reaper appeared;
  - crops to the program's window: `run.crop = [x, y, w, h]`, or "auto" (the box of the pixels
    that changed between the two dumps), or "full"; and saves examples/EXAMPLE/<shot.file>.

The [[shot]] keys used: file, and run = {project, args, secs, keys, native, crop, files, cmd}.
`run.cmd` replaces the whole command line (for console programs: e.g. a NewShell running one).
"""
import fnmatch
import glob
import os
import re
import subprocess
import sys
import tempfile
import time
import tomllib

os.environ.setdefault("BB_GUEST", "m1b")
os.environ.setdefault("BB_SESSION_TIMEOUT", "300")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import os4guest as g  # noqa: E402

if g.GUEST == "m1":
    sys.exit("gallery_shot: not on BB_GUEST=m1 (the user's guest); use m1b, m1c or local")
# QEMU's monitor of the selected guest through os4guest (its profile's port; it refuses m1,
# the user's guest)
DEST = "RAM:bbdoc/"


def hmp(cmd):
    g.hmp(cmd, wait=0.3)


def screendump():
    from PIL import Image
    tmp = tempfile.mktemp(suffix=".png")
    g.shot(None, tmp)
    im = Image.open(tmp).convert("RGB")
    im.load()
    os.unlink(tmp)
    return im


def wake():
    g.mouse(1, 0)
    g.mouse(-1, 0)
    time.sleep(1.5)


KEYS = {" ": "spc", ".": "dot", ",": "comma", "-": "minus", "/": "slash", "\n": "ret", "=": "equal",
        ":": "shift-semicolon", "_": "shift-minus", '"': "shift-apostrophe", "*": "shift-8", "'": "apostrophe"}


def sendtext(text):
    """Type into the active window (QEMU sendkey: the program's own window must be active)."""
    for c in text:
        k = KEYS.get(c) or (("shift-" + c.lower()) if c.isupper() else c)
        hmp("sendkey " + k)
        time.sleep(0.12)


def amiga(p):
    return DEST + os.path.relpath(p, ROOT)


def files_of(src, extra):
    d = os.path.dirname(src)
    out = [os.path.join(d, f) for f in sorted(os.listdir(d))
           if os.path.splitext(f)[1].lower() in (".bas", ".bbp", ".afg", ".cls", ".mod", ".ppm")]
    if src.endswith(".bbp"):
        for line in open(src, encoding="latin-1"):
            mm = re.match(r"\s*(Module|Form|Class)\s*=\s*(\S+)", line, re.I)
            if mm:
                p = os.path.normpath(os.path.join(d, mm.group(2)))
                if p not in out and os.path.exists(p):
                    out.append(p)
    for pat in extra:
        for p in sorted(glob.glob(os.path.join(d, pat))):
            if os.path.isfile(p) and p not in out:
                out.append(p)
    return out


def ours(m):
    st = str(m.tool("amiga_dos_command", command="status"))
    return re.findall(r"Process\s+(\d+): Loaded as command: (?:RAM:bbdoc/|DH1:bbdoc/)", st)


def autocrop(before, after, pad=2):
    """The box of the program's window: the biggest connected area of the screen that changed
    (in 8x8 cells), so other windows that only changed their title bars (activation) are left out."""
    from PIL import ImageChops
    diff = ImageChops.difference(before, after).convert("L").point(lambda v: 255 if v > 24 else 0)
    w, h = diff.size
    C = 8
    cw, ch = (w + C - 1) // C, (h + C - 1) // C
    small = diff.resize((cw, ch), resample=2)            # BILINEAR: the share of changed pixels
    px = small.load()
    cells = {(x, y) for y in range(ch) for x in range(cw) if px[x, y] > 40}
    best, seen, comps = [], set(), []
    for c in cells:
        if c in seen:
            continue
        comp, stack = [], [c]
        seen.add(c)
        while stack:
            x, y = stack.pop()
            comp.append((x, y))
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in cells and n not in seen:
                    seen.add(n)
                    stack.append(n)
        comps.append(comp)
    # prefer the newly opened window: it is the active one, with a blue title bar
    ap = after.load()

    def blue_title(comp):
        x0 = min(x for x, _ in comp) * C; x1 = min(w, (max(x for x, _ in comp) + 1) * C)
        y0 = min(y for _, y in comp) * C
        n = b = 0
        for y in range(y0, min(h, y0 + 24), 2):
            for x in range(x0, x1, 4):
                r, g, bl = ap[x, y]
                n += 1
                b += bl > 150 and bl > r + 40
        return b / n if n else 0
    for comp in comps:
        if len(comp) > 20 and blue_title(comp) > 0.3 and (not best or blue_title(best) <= 0.3 or len(comp) > len(best)):
            best = comp
    if not best:
        best = max(comps, key=len) if comps else []
    if not best:
        return None
    x0 = min(x for x, _ in best) * C; x1 = (max(x for x, _ in best) + 1) * C
    y0 = min(y for _, y in best) * C; y1 = (max(y for _, y in best) + 1) * C
    # tighten to the changed pixels inside that box
    box = diff.crop((x0, y0, min(w, x1), min(h, y1))).getbbox()
    if box:
        x0, y0, x1, y1 = x0 + box[0], y0 + box[1], x0 + box[2], y0 + box[3]
    return (max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(h, y1 + pad))

def exdir_of(ex):
    """An example's directory: a name under examples/, or a path (examples/book/ex04-first-form)."""
    return os.path.abspath(ex) if os.sep in ex else os.path.join(ROOT, "examples", ex)


def shoot(ex, shot, keep_full):
    exdir = exdir_of(ex)
    rel = os.path.relpath(exdir, ROOT)
    ex = os.path.basename(exdir)
    run = shot["run"]
    src = os.path.join(exdir, run.get("project", ""))
    exe = None
    if run.get("native"):
        exe = os.path.join(ROOT, "build/os4", ex + ".gallery.exe")
        subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
    m = g.MCP(g.URL)
    out_png = os.path.join(exdir, shot["file"])
    with g.testing("Boing BASIC gallery: screenshot of " + ex):
        fl = files_of(src, run.get("files", [])) if run.get("project") else []
        dirs = sorted({os.path.dirname(amiga(p)) for p in fl} | {DEST + rel})
        mk = sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})
        m.tool("amiga_dos_command", command="makedir RAM:bbdoc " + " ".join(mk))
        for f in fl:
            g.push(m, f, amiga(f))
        d = DEST + rel
        if exe:
            g.push(m, exe, d + "/" + ex)
            cmd = "%s/%s %s" % (d, ex, run.get("args", ""))
        else:
            g.push(m, os.path.join(ROOT, "build/os4/boing"), DEST + "boing")
            cmd = "%sboing run %s %s" % (DEST, amiga(src), run.get("args", ""))
        cmd = run.get("cmd", cmd).replace("{dir}", d).replace("{boing}", DEST + "boing")
        wake()
        before = screendump()
        # the bridge's protocol is one line per command: the stack/cd/command go in a script
        script = tempfile.mktemp(suffix=".script")
        with open(script, "w") as fh:
            if run.get("shell"):    # a Shell window; `run.type` is typed into it
                fh.write("stack 1048576\ncd %s\npath RAM:bbdoc ADD\n" % d)
            else:
                fh.write("stack 1048576\ncd %s\n%s >RAM:bbdoc/shot.out *>RAM:bbdoc/shot.err\n" % (d, cmd))
        gos = DEST + "go%d.script" % os.getpid()
        g.push(m, script, gos)
        os.unlink(script)
        m.tool("amiga_dos_command", command="delete RAM:bbdoc/shot.out RAM:bbdoc/shot.err QUIET")
        if run.get("shell"):
            m.tool("amiga_dos_command", command='run >NIL: NewShell "CON:%s/Boing BASIC/CLOSE" FROM %s'
                   % (run.get("window", "80/60/760/320"), gos))
            time.sleep(3)
            sendtext(run.get("type", "") + "\n")
        else:
            m.tool("amiga_dos_command", command="run >NIL: execute " + gos)
        time.sleep(run.get("secs", 6))
        for k in run.get("keys", []):
            if k.startswith("sleep:"):
                time.sleep(float(k[6:]))
            else:
                hmp("sendkey " + k)
                time.sleep(0.15)
        wake()
        after = screendump()
        # a single-buffered animation can be caught between clearing and drawing: with
        # run.dumps = N take N dumps and keep the one with the most colours where it changed
        alts = [after] + [screendump() for _ in range(run.get("dumps", 1) - 1)]
        if len(alts) > 1:
            box0 = autocrop(before, after) or (0, 0, after.width, after.height)
            after = max(alts, key=lambda im: len(im.crop(box0).getcolors(1 << 20) or ()))
        # run.wait_exit = N: let the program end by itself (up to N s) before any Ctrl-C; for
        # programs that own OS resources a Break would leave behind (declare_gfx's window)
        t_end = time.time() + run.get("wait_exit", 0)
        while time.time() < t_end and ours(m):
            time.sleep(3)
        for num in ours(m):
            m.tool("amiga_dos_command", command="break %s C" % num)
        for _ in range(5):
            time.sleep(2)
            if not ours(m):
                break
        if run.get("shell"):
            sendtext("endshell\n")
            time.sleep(2)
        left = ours(m)
        err = str(m.tool("amiga_dos_command", command="type RAM:bbdoc/shot.err")).strip()
        outp = str(m.tool("amiga_dos_command", command="type RAM:bbdoc/shot.out")).strip()
        reap = g.reapers(m)
    if outp and "no output" not in outp and "TYPE:" not in outp:
        print("stdout:", outp[-400:])
    if err and "no output" not in err:
        print("stderr:", err[:400])
    if left:
        print("WARNING: still running on the guest: processes", left)
    if reap:
        print("WARNING: Grim Reapers on the guest:", reap)
    crop = run.get("crop", "auto")
    if run.get("shell") and crop == "auto":     # the Shell window's own box
        crop = [int(v) for v in run.get("window", "80/60/760/320").split("/")]
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    if keep_full:
        after.save(out_png.replace(".png", ".full.png"))
    if crop == "auto":
        box = autocrop(before, after)
    elif crop == "full":
        box = None
    else:
        x, y, w, h = crop
        box = (x, y, x + w, y + h)
    im = after.crop(box) if box else after
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    im = im.quantize(colors=256, method=2, dither=0) if run.get("quantize", True) else im
    im.save(out_png, optimize=True)
    print("saved", os.path.relpath(out_png, ROOT), im.size, "box", box, "%d bytes" % os.path.getsize(out_png))
    return 0 if not left and not reap else 1


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    ex, want = args[0], args[1:]
    meta = tomllib.load(open(os.path.join(exdir_of(ex), "gallery.toml"), "rb"))
    rc = 0
    for shot in meta.get("shot", []):
        name = os.path.splitext(os.path.basename(shot["file"]))[0]
        if "run" in shot and (not want or any(fnmatch.fnmatch(name, w) for w in want)):
            rc |= shoot(ex, shot, "--keep-full" in sys.argv)
    return rc


if __name__ == "__main__":
    sys.exit(main())

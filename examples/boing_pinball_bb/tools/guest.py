#!/usr/bin/env python3
"""guest.py - Boing Pinball on an AmigaOS 4 guest (tools/os4guest.py: FIFO ticket, emulator lock,
"CLAUDE IS TESTING" banner; BB_GUEST=m1|local).

    tools/guest.py run MODE [game args]     the game (Pinball.bbp), e.g. run all --bench 1000
    tools/guest.py bench MODE [args]        the console bench (Bench.bbp), e.g. bench vm --frames 500
    tools/guest.py shots OUTDIR [MODE]      screenshots (QEMU HMP screendump) of each screen and table
    tools/guest.py stop                     Ctrl-C to our own processes there (after a timed-out run)
    tools/guest.py reaper [PNG]             close the Grim Reaper of a crash of ours (only when no
                                            other program runs: the Reaper could be theirs)
    tools/guest.py probe                    tools/probe natively, step by step (finding a crash)
    tools/guest.py clean                    delete our files from the guest's RAM:
  MODE: vm | jit | native | all

Files go to RAM:bbg/examples/boing_pinball_bb/ (the project, its art/ and ../common modules).
Native builds are cross-compiled here (build/boing build --target os4).
"""
import os, re, socket, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(PROJ, "../.."))
sys.path.insert(0, ROOT + "/tools")
sys.path.insert(0, ROOT + "/examples/common/tools")
import os4guest as g
import guest_game as gg

if g.GUEST == "m1":
    sys.exit("guest.py: m1 is the user's guest; use BB_GUEST=m1b, m1c or local")
SHOTS_SSH = {"m1b": "chriscollins@m1.local", "m1c": "chriscollins@m1.local"}
HMP_PORT = {"m1b": 2448, "m1c": 2548, "local": 2348}[g.GUEST]   # QEMU monitors (2348 on m1.local is the user's m1)


def push_project(m, bbp):
    fl = gg.files_of(bbp)
    fl += [os.path.join(PROJ, "art", f) for f in sorted(os.listdir(os.path.join(PROJ, "art")))
           if f.endswith(".png") or f.endswith(".mod")]
    dirs = sorted({os.path.dirname(gg.amiga(p)) for p in fl})
    m.tool("amiga_dos_command", command="makedir RAM:bbg " + " ".join(
        sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
    have = str(m.tool("amiga_dos_command", command="list RAM:bbg/examples/boing_pinball_bb/art LFORMAT \"%n %l\""))
    for f in fl:
        if "/art/" in f and ("%s %d" % (os.path.basename(f), os.path.getsize(f))) in have:
            continue                      # the pictures are big: only once a session
        g.push(m, f, gg.amiga(f))


MYDIR = "RAM:bbg/examples/boing_pinball_bb"


def ptr_reaper(m):
    """close the front Grim Reaper (Kill) with ptr from our own RAM: directory (no disk install)"""
    g.push(m, os.path.join(ROOT, "build/os4/ptr"), MYDIR + "/ptr")
    return str(m.tool("amiga_dos_command", command=MYDIR + "/ptr reaper"))


def stop_mine(m):
    """Ctrl-C to our own processes only (loaded from our directory: other agents use RAM:bbg/ too)."""
    st = str(m.tool("amiga_dos_command", command="status"))
    for num in re.findall(r"Process\s+(\d+): Loaded as command: " + re.escape(MYDIR) + "/", st):
        m.tool("amiga_dos_command", command="break %s C" % num)


gg.stop_ours = stop_mine                    # (guest_game's run() calls it on a time-out)


def build_native(bbp):
    exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(bbp))[0] + ".exe")
    subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", bbp, "--target", "os4", "-o", exe])
    return exe


def command(m, bbp, md, args, exe):
    d = os.path.dirname(gg.amiga(bbp))
    if md == "native":
        g.push(m, exe, d + "/native")
        return "%s/native %s" % (d, args)
    g.push(m, os.path.join(ROOT, "build/os4/boing"), MYDIR + "/boing")
    return "%s/boing run %s%s %s" % (MYDIR, "--jit " if md == "jit" else "", gg.amiga(bbp), args)


def hmp(cmd):
    if g.GUEST in SHOTS_SSH:
        py = ("import socket,time\ns=socket.create_connection(('127.0.0.1',%d),timeout=10)\ntime.sleep(0.5);s.recv(65536)\n"
              "s.sendall(%r.encode());time.sleep(2);s.recv(65536);s.close()" % (HMP_PORT, cmd + "\n"))
        subprocess.check_call(["ssh", SHOTS_SSH[g.GUEST], "python3", "-c", '"%s"' % py.replace('"', '\\"')])
    else:
        s = socket.create_connection(("127.0.0.1", HMP_PORT), timeout=10)
        time.sleep(0.5); s.recv(65536); s.sendall((cmd + "\n").encode()); time.sleep(2); s.recv(65536); s.close()


def screendump(out_png):
    from PIL import Image
    remote = "/tmp/bb_pinball_shot_%s.ppm" % g.GUEST
    hmp("mouse_move 1 0"); hmp("mouse_move -1 0")          # wake the screen blanker
    hmp("screendump " + remote)
    local = out_png[:-4] + ".ppm"
    if g.GUEST in SHOTS_SSH:
        subprocess.check_call(["scp", "-q", SHOTS_SSH[g.GUEST] + ":" + remote, local])
    else:
        os.replace(remote, local)
    im = Image.open(local).convert("RGB")
    os.remove(local)
    # the canvas: the 640 x 512 area whose top row is the display's dark brown (or the picture)
    box = find_canvas(im)
    if not box and im.size == (1280, 720):
        box = (320, 107, 960, 619)          # where the window opens on the m1 guests' screen
    (im.crop(box) if box else im).save(out_png)
    print("screenshot", out_png, "canvas at", box)


def screendump_full(out_png):
    from PIL import Image
    remote = "/tmp/bb_pinball_shot_%s.ppm" % g.GUEST
    hmp("screendump " + remote)
    local = out_png[:-4] + ".ppm"
    if g.GUEST in SHOTS_SSH:
        subprocess.check_call(["scp", "-q", SHOTS_SSH[g.GUEST] + ":" + remote, local])
    else:
        os.replace(remote, local)
    Image.open(local).save(out_png); os.remove(local)
    print("screenshot", out_png)


def find_canvas(im):
    """the canvas: a 640 x 512 area whose top row starts and ends in the display's dark brown
    (34, 17, 0), give or take the 16-bit screen's rounding, just inside the window's border"""
    w, h = im.size
    px = im.load()
    near = lambda p: abs(p[0] - 34) <= 8 and abs(p[1] - 17) <= 8 and p[2] <= 8
    for y in range(0, h - 511):
        for x in range(0, w - 639):
            if near(px[x, y]) and near(px[x + 639, y]) and near(px[x + 320, y]) and not near(px[x - 1, y]) \
                    and not near(px[x, y - 1]):
                return (x, y, x + 640, y + 512)
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    what = sys.argv[1]
    m = g.MCP(g.URL)
    if what == "stop":              # Ctrl-C to our own processes (left by a timed-out run), nothing else
        with g.testing("Boing Pinball: stopping a test"):
            stop_mine(m)
            time.sleep(5)
            print(m.tool("amiga_dos_command", command="status"))
        return 0
    if what == "reaper":            # a crash of ours: screenshot the Grim Reaper, close it, stop our processes
        out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/pb_reaper.png"
        with g.testing("Boing Pinball: closing a crashed test"):
            st = str(m.tool("amiga_dos_command", command="status"))
            print(st)
            others = [l for l in st.splitlines() if "Loaded as command:" in l and MYDIR not in l and not
                      re.search(r"amiga-bridge|launcher|QEMUCopyFix|status|GrimReaper", l)]
            if others:
                print("other programs are running, the Reaper may be theirs: not touching it\n" + "\n".join(others))
            elif "GrimReaper" in st and MYDIR in st:
                screendump_full(out)
                print("ptr reaper:", ptr_reaper(m))
            stop_mine(m)
            time.sleep(3)
            print(m.tool("amiga_dos_command", command="status"))
        return 0
    if what == "probe":             # tools/probe: the native build's init step by step
        bbp = os.path.join(PROJ, "tools/probe/Probe.bbp")
        exe = build_native(bbp)
        with g.testing("Boing Pinball: native probe"):
            push_project(m, os.path.join(PROJ, "Pinball.bbp"))
            if "GrimReaper" in str(m.tool("amiga_dos_command", command="status")):
                print("a Grim Reaper is up already: not starting"); return 1
            g.push(m, exe, MYDIR + "/probe")
            m.tool("amiga_dos_command", command="delete RAM:pb_probe.log QUIET")
            m.tool("amiga_dos_command", command="cd " + MYDIR)
            m.tool("amiga_dos_command", command="run >NIL: %s/probe >RAM:pb_probe.out *>RAM:pb_probe.err" % MYDIR)
            time.sleep(float(os.environ.get("PB_PROBE_WAIT", "90")))
            print(m.tool("amiga_dos_command", command="type RAM:pb_probe.log"))
            print(m.tool("amiga_dos_command", command="type RAM:pb_probe.err"))
            st = str(m.tool("amiga_dos_command", command="status"))
            print(st)
            if "GrimReaper" in st:
                screendump_full(os.environ.get("PB_SHOT", "/tmp/pb_reaper.png"))
                print("ptr reaper:", ptr_reaper(m))
            stop_mine(m)
            m.tool("amiga_dos_command", command="delete RAM:pb_probe.log RAM:pb_probe.out RAM:pb_probe.err QUIET")
        return 0
    if what == "clean":
        with g.testing("Boing Pinball: cleaning up"):
            print(m.tool("amiga_dos_command", command="delete RAM:bbg/examples/boing_pinball_bb ALL QUIET FORCE"))
        return 0
    limit = float(os.environ.get("BB_TEST_TIMEOUT", "400"))
    if what in ("run", "bench"):
        bbp = os.path.join(PROJ, "Pinball.bbp" if what == "run" else "Bench.bbp")
        mode, args = sys.argv[2], " ".join(sys.argv[3:])
        modes = ["vm", "jit", "native"] if mode == "all" else [mode]
        exe = build_native(bbp) if "native" in modes else None
        ok = True
        with g.testing("Boing BASIC: Boing Pinball " + what):
            push_project(m, bbp)
            for md in modes:
                cmd = command(m, bbp, md, args, exe)
                m.tool("amiga_dos_command", command="cd " + os.path.dirname(gg.amiga(bbp)))
                out = gg.run(m, cmd, "RAM:bbg/examples/boing_pinball_bb/pb_%s.out" % md, limit)
                print("== %s: %s\n%s" % (md, cmd, out.strip()), flush=True)
                ok &= "FAIL" not in out
            n = g.reapers(m)
            if n:
                print("Grim Reapers: %d" % n); ok = False
        return 0 if ok else 1
    if what == "shots":
        outdir = sys.argv[2]
        md = sys.argv[3] if len(sys.argv) > 3 else "vm"
        os.makedirs(outdir, exist_ok=True)
        bbp = os.path.join(PROJ, "Pinball.bbp")
        exe = build_native(bbp) if md == "native" else None
        plan = [("title", "--table 0 --screen title", 14), ("demo", "--table 0 --screen demo", 18), ("help1", "--screen help1", 12),
                ("help2", "--screen help2", 12), ("scores", "--screen scores", 12),
                ("comet", "--table 0 --screen play", 40), ("deep", "--table 1 --screen play", 40),
                ("foundry", "--table 2 --screen play", 40), ("title_deep", "--table 1 --screen title", 16),
                ("title_foundry", "--table 2 --screen title", 16)]
        only = os.environ.get("PB_SHOTS")
        with g.testing("Boing BASIC: Boing Pinball screenshots"):
            push_project(m, bbp)
            for name, args, wait in plan:
                if only and name not in only.split(","):
                    continue
                cmd = command(m, bbp, md, args + " --log", exe)
                m.tool("amiga_dos_command", command="cd " + os.path.dirname(gg.amiga(bbp)))
                m.tool("amiga_dos_command", command="run >NIL: %s >RAM:bbg/examples/boing_pinball_bb/pb_shot.out *>RAM:bbg/examples/boing_pinball_bb/pb_shot.err" % cmd)
                time.sleep(wait)
                screendump(os.path.join(outdir, "os4-%s.png" % name))
                gg.stop_ours(m)
                time.sleep(3)
                print(str(m.tool("amiga_dos_command", command="type RAM:bbg/examples/boing_pinball_bb/pb_shot.err")).strip()[-300:])
            n = g.reapers(m)
            if n:
                print("Grim Reapers: %d" % n)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())

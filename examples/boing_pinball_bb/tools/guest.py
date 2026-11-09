#!/usr/bin/env python3
"""guest.py - Boing Pinball on an AmigaOS 4 guest (tools/os4guest.py: FIFO ticket, emulator lock,
"CLAUDE IS TESTING" banner; BB_GUEST=m1|local).

    tools/guest.py run MODE [game args]     the game (Pinball.bbp), e.g. run all --bench 1000
    tools/guest.py bench MODE [args]        the console bench (Bench.bbp), e.g. bench vm --frames 500
    tools/guest.py shots OUTDIR [MODE]      screenshots (QEMU HMP screendump) of each screen and table
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

SHOTS_SSH = {"m1": "chriscollins@m1.local"}


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


def build_native(bbp):
    exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(bbp))[0] + ".exe")
    subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", bbp, "--target", "os4", "-o", exe])
    return exe


def command(m, bbp, md, args, exe):
    d = os.path.dirname(gg.amiga(bbp))
    if md == "native":
        g.push(m, exe, d + "/native")
        return "%s/native %s" % (d, args)
    g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbg/boing")
    return "RAM:bbg/boing run %s%s %s" % ("--jit " if md == "jit" else "", gg.amiga(bbp), args)


def hmp(cmd):
    if g.GUEST in SHOTS_SSH:
        py = ("import socket,time\ns=socket.create_connection(('127.0.0.1',2348),timeout=10)\ntime.sleep(0.5);s.recv(65536)\n"
              "s.sendall(%r.encode());time.sleep(2);s.recv(65536);s.close()" % (cmd + "\n"))
        subprocess.check_call(["ssh", SHOTS_SSH[g.GUEST], "python3", "-c", '"%s"' % py.replace('"', '\\"')])
    else:
        s = socket.create_connection(("127.0.0.1", 2348), timeout=10)
        time.sleep(0.5); s.recv(65536); s.sendall((cmd + "\n").encode()); time.sleep(2); s.recv(65536); s.close()


def screendump(out_png):
    from PIL import Image
    remote = "/tmp/bb_pinball_shot.ppm"
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
    (im.crop(box) if box else im).save(out_png)
    print("screenshot", out_png, "canvas at", box)


def find_canvas(im):
    """the window's inner area: look for the 640-wide run of the canvas under the title bar"""
    w, h = im.size
    px = im.load()
    for y in range(0, h - 512):
        for x in range(0, w - 640, 1):
            if px[x, y] == (34, 17, 0) and px[x + 639, y] == (34, 17, 0) and (x == 0 or px[x - 1, y] != (34, 17, 0)):
                return (x, y, x + 640, y + 512)
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    what = sys.argv[1]
    m = g.MCP(g.URL)
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
                out = gg.run(m, cmd, "RAM:bbg/pb_%s.out" % md, limit)
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
        plan = [("title", "--table 0", 14), ("demo", "--table 0 --screen demo", 18), ("help1", "--screen help1", 12),
                ("help2", "--screen help2", 12), ("scores", "--screen scores", 12),
                ("comet", "--table 0 --screen play", 40), ("deep", "--table 1 --screen play", 40),
                ("foundry", "--table 2 --screen play", 40), ("title_deep", "--table 1", 16),
                ("title_foundry", "--table 2", 16)]
        only = os.environ.get("PB_SHOTS")
        with g.testing("Boing BASIC: Boing Pinball screenshots"):
            push_project(m, bbp)
            for name, args, wait in plan:
                if only and name not in only.split(","):
                    continue
                cmd = command(m, bbp, md, args + " --log", exe)
                m.tool("amiga_dos_command", command="cd " + os.path.dirname(gg.amiga(bbp)))
                m.tool("amiga_dos_command", command="run >NIL: %s >RAM:bbg/pb_shot.out *>RAM:bbg/pb_shot.err" % cmd)
                time.sleep(wait)
                screendump(os.path.join(outdir, "os4-%s.png" % name))
                gg.stop_ours(m)
                time.sleep(3)
                print(str(m.tool("amiga_dos_command", command="type RAM:bbg/pb_shot.err")).strip()[-300:])
            n = g.reapers(m)
            if n:
                print("Grim Reapers: %d" % n)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())

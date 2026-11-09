#!/usr/bin/env python3
"""guest_shots.py - Ace Pilot 2 screenshots on an AmigaOS 4 guest (BB_GUEST=m1|local), for the
README: the game is started with each set of arguments, left to run, the screen blanker woken
(a 1-pixel mouse move through QEMU's monitor), the screen dumped, and the game stopped.

    guest_shots.py OUTDIR [vm|native] [name ...]
One lock ticket per screenshot (the 5-minute rule). Writes OUTDIR/<name>.png (the whole guest screen). Uses examples/common/tools/guest_game.py's
helpers (FIFO ticket, emulator lock, banner, RAM:bbg/).
"""
import os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "../../common/tools"))
import guest_game as gg
g = gg.g

SHOTS = [  # name, arguments, seconds
    ("dogfight", "--autoplay --mission 8", 30),
    ("strafing", "--autoplay --mission 6", 45),
    ("cockpit", "--autoplay --mission 1 --cockpit", 20),
    ("title", "", 16),
    ("brief", "--brief --mission 3", 10),
]


def hmp(cmd):
    line = "printf '%s\\n' | nc -w 2 127.0.0.1 2348 >/dev/null" % cmd
    if g.SSH:
        subprocess.run(["ssh", g.SSH, line], check=False)
    else:
        subprocess.run(line, shell=True, check=False)


def main():
    out, mode = os.path.abspath(sys.argv[1]), (sys.argv[2] if len(sys.argv) > 2 else "vm")
    want = sys.argv[3:]
    for name, args, secs in SHOTS:
        if not want or name in want:
            one(out, mode, name, args, secs)
    return 0


def one(out, mode, name, args, secs):
    os.makedirs(out, exist_ok=True)
    src = os.path.abspath(os.path.join(HERE, "../AcePilot2.bbp"))
    exe = None
    if mode == "native":
        exe = os.path.join(gg.ROOT, "build/os4/AcePilot2.exe")
        subprocess.check_call([os.path.join(gg.ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
    m = g.MCP(g.URL)
    with g.testing("Boing BASIC: Ace Pilot 2 screenshot " + name):
        fl = gg.files_of(src)
        dirs = sorted({os.path.dirname(gg.amiga(p)) for p in fl})
        m.tool("amiga_dos_command", command="makedir RAM:bbg " + " ".join(
            sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
        for f in fl:
            g.push(m, f, gg.amiga(f))
        d = os.path.dirname(gg.amiga(src))
        if exe:
            g.push(m, exe, d + "/AcePilot2")
        else:
            g.push(m, os.path.join(gg.ROOT, "build/os4/boing"), "RAM:bbg/boing")
        m.tool("amiga_dos_command", command="cd " + d)
        if True:
            cmd = ("%s/AcePilot2 %s" % (d, args)) if exe else ("RAM:bbg/boing run %s %s --data %s" % (gg.amiga(src), args, d))
            m.tool("amiga_dos_command", command="run >NIL: %s >RAM:bbg/shot.out *>RAM:bbg/shot.err" % cmd)
            time.sleep(secs)
            hmp("mouse_move 1 0")
            time.sleep(1)
            hmp("mouse_move -1 0")
            time.sleep(1)
            gg.screendump(os.path.join(out, name + ".png"))
            gg.stop_ours(m)
            time.sleep(4)
            print(name, str(m.tool("amiga_dos_command", command="type RAM:bbg/shot.err")).strip()[:300])
        n = g.reapers(m)
        print("Grim Reapers:", n)


if __name__ == "__main__":
    sys.exit(main())

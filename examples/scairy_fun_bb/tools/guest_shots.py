#!/usr/bin/env python3
"""guest_shots.py - ScAIry Fun screenshots on an AmigaOS 4 guest (BB_GUEST=m1|local), for the
README: the game is started with each set of arguments, left to run, the screen blanker woken
(a 1-pixel mouse move through QEMU's monitor), the screen dumped, and the game stopped.

    guest_shots.py OUTDIR [vm|native] [name ...]
One lock ticket per screenshot (the 5-minute rule). Writes OUTDIR/<name>.png (the whole guest screen). Uses examples/common/tools/guest_game.py's
helpers (FIFO ticket, emulator lock, banner, its own RAM:bbg-<pid>/, deleted after each shot).
"""
import os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "../../common/tools"))
import guest_game as gg
g = gg.g

SHOTS = [  # name, arguments, seconds
    ("levee", "--route 1 --nomusic", 24),
    ("mountain", "--route 3 --nomusic", 40),
    ("town", "--route 4 --nomusic --cockpit", 30),
    ("title", "--nomusic", 5),
    ("help", "--nomusic --help 3", 8),
]


def hmp(cmd):
    line = "printf '%s\\n' | nc -w 2 127.0.0.1 %d >/dev/null" % (cmd, gg.hmp_port())
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
    src = os.path.abspath(os.path.join(HERE, "../ScairyFun.bbp"))
    exe = None
    if mode == "native":
        exe = os.path.join(gg.ROOT, "build/os4/ScairyFun.exe")
        subprocess.check_call([os.path.join(gg.ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
    m = g.MCP(g.URL)
    with g.testing("Boing BASIC: ScAIry Fun screenshot " + name):
        fl = gg.files_of(src)
        dirs = sorted({os.path.dirname(gg.amiga(p)) for p in fl})
        m.tool("amiga_dos_command", command="makedir " + gg.RUN + " " + " ".join(
            sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
        for f in fl:
            g.push(m, f, gg.amiga(f))
        d = os.path.dirname(gg.amiga(src))
        if exe:
            g.push(m, exe, d + "/ScairyFun")
        else:
            g.push(m, os.path.join(gg.ROOT, "build/os4/boing"), gg.RUN + "/boing")
        m.tool("amiga_dos_command", command="cd " + d)
        if True:
            cmd = ("%s/ScairyFun %s" % (d, args)) if exe else ("%s/boing run %s %s --data %s" % (gg.RUN, gg.amiga(src), args, d))
            m.tool("amiga_dos_command", command="run >NIL: %s >%s/shot.out *>%s/shot.err" % (cmd, gg.RUN, gg.RUN))
            time.sleep(secs)
            hmp("mouse_move 1 0")
            time.sleep(1)
            hmp("mouse_move -1 0")
            time.sleep(1)
            gg.screendump(os.path.join(out, name + ".png"))
            gg.stop_ours(m)
            time.sleep(4)
            print(name, str(m.tool("amiga_dos_command", command="type " + gg.RUN + "/shot.err")).strip()[:300])
        m.tool("amiga_dos_command", command="cd RAM:")
        m.tool("amiga_dos_command", command="delete %s ALL QUIET FORCE" % gg.RUN)
        n = g.reapers(m)
        print("Grim Reapers:", n)


if __name__ == "__main__":
    sys.exit(main())

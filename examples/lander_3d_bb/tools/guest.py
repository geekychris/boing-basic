#!/usr/bin/env python3
"""guest.py - run Lander 3D (Boing BASIC) on an AmigaOS 4 guest through tools/os4guest.py
(FIFO ticket, emulator lock, "CLAUDE IS TESTING" banner; BB_GUEST=m1|local).

    guest.py PROJECT.bbp MODE [game args...]
    guest.py cleanup                        stop our processes, delete RAM:bbl
      MODE vm | jit | native                run it, wait for the --bench report
           (one mode a call: a lock ticket is capped at 5 minutes)
           shot:OUT.png:SECONDS[:vm|jit|native]   start it, wait, screenshot the guest
                                            (QEMU HMP screendump, after a 1-pixel mouse
                                            move to wake the blanker), stop it
    e.g. guest.py examples/lander_3d_bb/Lander3D.bbp vm --bench 300

Files go to RAM:bbl/<path in the repo> (the project's files, its Module=/Form= files,
the module and art/*.png), and RAM:bbl is deleted afterwards. BB_ROOT: the checkout whose
build/os4/boing (and build/boing for native builds) is used (default: this one).
"""
import os, re, subprocess, sys, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
BROOT = os.path.abspath(os.environ.get("BB_ROOT", ROOT))
sys.path.insert(0, ROOT + "/tools")
os.environ.setdefault("BB_SESSION_TIMEOUT", "290")    # the lead's 5-minute cap a lock ticket
import os4guest as g

TOP = "RAM:bbl"


def files_of(src):
    d = os.path.dirname(src)
    out = [os.path.join(d, f) for f in sorted(os.listdir(d))
           if os.path.splitext(f)[1].lower() in (".bas", ".bbp", ".afg", ".cls", ".mod")]
    art = os.path.join(d, "art")
    if os.path.isdir(art):
        out += [os.path.join(art, f) for f in sorted(os.listdir(art)) if f.endswith(".png")]
    for line in open(src, encoding="latin-1"):
        mm = re.match(r"\s*(Module|Form|Class)\s*=\s*(\S+)", line, re.I)
        if mm:
            p = os.path.normpath(os.path.join(d, mm.group(2)))
            if p not in out and os.path.exists(p):
                out.append(p)
    return out


def amiga(p):
    return TOP + "/" + os.path.relpath(p, ROOT)


def dos(m, c):
    return str(m.tool("amiga_dos_command", command=c))


def stop_ours(m):
    """Ctrl-C to our own processes (loaded from RAM:bbl/, which only this tool uses)."""
    st = dos(m, "status")
    for num in re.findall(r"Process\s+(\d+): Loaded as command: " + TOP + "/", st):
        dos(m, "break %s C" % num)


def run(m, cmd, outf, limit):
    dos(m, "delete %s %s.err QUIET" % (outf, outf))
    dos(m, "stack 1048576")
    dos(m, "run >NIL: %s >%s *>%s.err" % (cmd, outf, outf))
    t0, out = time.time(), ""
    while time.time() - t0 < limit:
        time.sleep(3)
        out, err = dos(m, "type %s" % outf), dos(m, "type %s.err" % outf)
        if "picture hash" in out or "bye" in out:
            return out + err
        if "runtime error" in err or "error:" in err:
            stop_ours(m)
            return out + "\n" + err + "\nFAIL (error)"
    stop_ours(m)
    return out + "\nFAIL (timed out after %ds)" % limit


# QEMU HMP monitor port per guest. On m1.local, 2348 is the USER's own guest (m1): never
# touched. Agent guests: m1b 2448, m1c 2548. OS4_HMP_PORT overrides.
HMP_PORT = {"local": 2348, "spark": 2348, "m1b": 2448, "m1c": 2548}


def hmp_port():
    if os.environ.get("OS4_HMP_PORT"):
        return int(os.environ["OS4_HMP_PORT"])
    guest = os.environ.get("BB_GUEST", "local")
    if guest not in HMP_PORT:
        raise SystemExit("guest.py: no screenshots or mouse on guest %r (m1 is the user's)" % guest)
    return HMP_PORT[guest]


def hmp(cmd):
    port = hmp_port()
    if g.SSH:
        subprocess.run(["ssh", g.SSH, "printf '%s\\n' | nc -w 2 127.0.0.1 %d >/dev/null" % (cmd, port)], check=True)
    else:
        subprocess.run("printf '%s\\n' | nc -w 2 127.0.0.1 %d >/dev/null" % (cmd, port), shell=True, check=True)


def screendump(out_png):
    import tempfile
    from PIL import Image
    hmp("mouse_move 1 0")                      # wake the screen blanker
    time.sleep(1)
    tmp = tempfile.mktemp(suffix=".ppm")
    if g.SSH:
        hmp("screendump /tmp/bbl_shot.ppm")
        time.sleep(1)
        subprocess.run(["scp", "-q", g.SSH + ":/tmp/bbl_shot.ppm", tmp], check=True)
    else:
        hmp("screendump " + tmp)
        time.sleep(1)
    Image.open(tmp).save(out_png)
    os.unlink(tmp)
    print("screenshot", out_png)


def cleanup():
    """stop our processes and delete RAM:bbl (after an interrupted run)"""
    m = g.MCP(g.URL)
    with g.testing("Boing BASIC: Lander 3D cleanup"):
        stop_ours(m)
        time.sleep(3)
        stop_ours(m)
        dos(m, "cd RAM:")
        dos(m, "delete %s ALL QUIET FORCE" % TOP)
        print(dos(m, "status"))
        print(dos(m, "list RAM: QUICK"))
    return 0


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "cleanup":
        return cleanup()
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, mode, args = os.path.abspath(sys.argv[1]), sys.argv[2], " ".join(sys.argv[3:])
    limit = float(os.environ.get("BB_TEST_TIMEOUT", "240"))
    shot = None
    if mode.startswith("shot:"):
        parts = mode.split(":")
        shot = (os.path.abspath(parts[1]), float(parts[2]))
        mode = parts[3] if len(parts) > 3 else "vm"
    modes = [mode]
    exe = None
    if "native" in modes:
        exe = os.path.join(BROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
        subprocess.check_call([os.path.join(BROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
    m = g.MCP(g.URL)
    ok = True
    with g.testing("Boing BASIC: Lander 3D"):
        try:
            fl = files_of(src)
            dirs = sorted({os.path.dirname(amiga(p)) for p in fl})
            dos(m, "makedir " + TOP + " " + " ".join(
                sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
            for f in fl:
                r = g.push(m, f, amiga(f))
                if os.environ.get("BB_VERBOSE"):
                    print("push", amiga(f), r)
            d = os.path.dirname(amiga(src))
            for md in modes:
                if md == "native":
                    g.push(m, exe, d + "/Lander3D")
                    cmd = "%s/Lander3D %s" % (d, args)
                else:
                    g.push(m, os.path.join(BROOT, "build/os4/boing"), TOP + "/boing")
                    cmd = "%s/boing run %s%s %s" % (TOP, "--jit " if md == "jit" else "", amiga(src), args)
                dos(m, "cd " + d)
                if shot:
                    dos(m, "stack 1048576")
                    dos(m, "run >NIL: %s >%s/shot.out *>%s/shot.err" % (cmd, TOP, TOP))
                    time.sleep(shot[1])
                    screendump(shot[0])
                    stop_ours(m)
                    time.sleep(3)
                    print(dos(m, "type %s/shot.out" % TOP), dos(m, "type %s/shot.err" % TOP))
                    continue
                out = run(m, cmd, "%s/%s.out" % (TOP, md), limit)
                print("== %s: %s\n%s" % (md, cmd, out.strip()))
                ok &= "FAIL" not in out
            n = g.reapers(m)
            if n:
                print("Grim Reapers: %d" % n)
                ok = False
        finally:
            stop_ours(m)
            time.sleep(2)
            dos(m, "cd RAM:")
            dos(m, "delete %s ALL QUIET FORCE" % TOP)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

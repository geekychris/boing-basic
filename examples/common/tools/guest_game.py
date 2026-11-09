#!/usr/bin/env python3
"""guest_game.py - run one of the amiga3d game ports on an AmigaOS 4 guest (tools/os4guest.py:
FIFO ticket, emulator lock, "CLAUDE IS TESTING" banner; BB_GUEST=m1|spark|local).

    guest_game.py PROJECT.bbp MODE [game args...]
      MODE vm      build/os4/boing run PROJECT.bbp args
           shot:OUT.png:SECONDS[:native]   start the game (VM, or the native build), wait,
                   save a screenshot of the guest's screen (QEMU HMP screendump), stop it
           jit     the same with --jit
           native  boing build --target os4, then the executable
           all     vm, jit and native one after the other
    e.g. guest_game.py examples/tank_duel/TankDuel.bbp all --bench 500

Files go to RAM:bbg/<path in the repo> (the project's own files and its Module=/Form= files),
so ../common paths work there. Waits for a line with "picture hash" (the end of a --bench
report) or a runtime error, prints the output, and checks no Grim Reaper was left.
"""
import os, re, subprocess, sys, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g


def files_of(src):
    d = os.path.dirname(src)
    out = [os.path.join(d, f) for f in sorted(os.listdir(d))
           if os.path.splitext(f)[1].lower() in (".bas", ".bbp", ".afg", ".cls", ".mod", ".ppm", ".raw")]
    for line in open(src, encoding="latin-1"):
        mm = re.match(r"\s*(Module|Form|Class)\s*=\s*(\S+)", line, re.I)
        if mm:
            p = os.path.normpath(os.path.join(d, mm.group(2)))
            if p not in out and os.path.exists(p):
                out.append(p)
    return out


def amiga(p):
    return "RAM:bbg/" + os.path.relpath(p, ROOT)


def run(m, cmd, outf, limit):
    m.tool("amiga_dos_command", command="delete %s %s.err QUIET" % (outf, outf))
    m.tool("amiga_dos_command", command="run >NIL: %s >%s *>%s.err" % (cmd, outf, outf))
    t0, out = time.time(), ""
    while time.time() - t0 < limit:
        time.sleep(3)
        out = str(m.tool("amiga_dos_command", command="type %s" % outf))
        err = str(m.tool("amiga_dos_command", command="type %s.err" % outf))
        if "picture hash" in out or "bye" in out:
            return out + err
        if "runtime error" in err or "error:" in err:
            return out + "\n" + err + "\nFAIL (error)"
    stop_ours(m)
    return out + "\nFAIL (timed out after %ds)" % limit


def stop_ours(m):
    """Ctrl-C to our own processes (loaded from RAM:bbg/, which only this tool uses)."""
    st = str(m.tool("amiga_dos_command", command="status"))
    for num in re.findall(r"Process\s+(\d+): Loaded as command: RAM:bbg/", st):
        m.tool("amiga_dos_command", command="break %s C" % num)

# QEMU HMP monitor port per guest. On m1.local, 2348 is the USER's own guest (m1); agent test
# guests are m1b (2448) and m1c (2548). OS4_HMP_PORT overrides.
HMP_PORT = {"local": 2348, "spark": 2348, "m1b": 2448, "m1c": 2548}


def hmp_port():
    if os.environ.get("OS4_HMP_PORT"):
        return int(os.environ["OS4_HMP_PORT"])
    guest = os.environ.get("BB_GUEST", "local")
    if guest not in HMP_PORT:
        raise SystemExit("guest_game: no screenshots on BB_GUEST=%s (m1 is the user's guest)" % guest)
    return HMP_PORT[guest]


def screendump(out_png):
    """The guest's screen as a PNG (QEMU's HMP monitor on the machine QEMU runs on; each guest has
    its own port, see HMP_PORT). Refuses the user's m1 guest."""
    import tempfile
    from PIL import Image
    tmp = tempfile.mktemp(suffix=".ppm")
    if g.SSH:
        subprocess.run(["ssh", g.SSH, "printf 'screendump /tmp/bbg_shot.ppm\\n' | nc -w 3 127.0.0.1 %d >/dev/null" % hmp_port()], check=True)
        time.sleep(1)
        subprocess.run(["scp", "-q", g.SSH + ":/tmp/bbg_shot.ppm", tmp], check=True)
    else:
        subprocess.run("printf 'screendump %s\\n' | nc -w 3 127.0.0.1 %d >/dev/null" % (tmp, hmp_port()), shell=True, check=True)
        time.sleep(1)
    Image.open(tmp).save(out_png)
    os.unlink(tmp)
    print("screenshot", out_png)


def screendump(out_png):
    """The guest's screen as a PNG (QEMU's HMP monitor on port 2348 of the machine QEMU runs on)."""
    import tempfile
    from PIL import Image
    tmp = tempfile.mktemp(suffix=".ppm")
    if g.SSH:
        subprocess.run(["ssh", g.SSH, "printf 'screendump /tmp/bbg_shot.ppm\\n' | nc -w 3 127.0.0.1 2348 >/dev/null"], check=True)
        time.sleep(1)
        subprocess.run(["scp", "-q", g.SSH + ":/tmp/bbg_shot.ppm", tmp], check=True)
    else:
        subprocess.run("printf 'screendump %s\\n' | nc -w 3 127.0.0.1 2348 >/dev/null" % tmp, shell=True, check=True)
        time.sleep(1)
    Image.open(tmp).save(out_png)
    os.unlink(tmp)
    print("screenshot", out_png)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, mode, args = os.path.abspath(sys.argv[1]), sys.argv[2], " ".join(sys.argv[3:])
    limit = float(os.environ.get("BB_TEST_TIMEOUT", "300"))
    shot = None
    if mode.startswith("shot:"):
        parts = mode.split(":")
        shot = (os.path.abspath(parts[1]), float(parts[2]))
        mode = parts[3] if len(parts) > 3 else "vm"
    modes = ["vm", "jit", "native"] if mode == "all" else [mode]
    exe = None
    if "native" in modes:
        exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
        subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
    m = g.MCP(g.URL)
    ok = True
    with g.testing("Boing BASIC: " + os.path.basename(src)):
        fl = files_of(src)
        dirs = sorted({os.path.dirname(amiga(p)) for p in fl})
        m.tool("amiga_dos_command", command="makedir RAM:bbg " + " ".join(
            sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
        for f in fl:
            g.push(m, f, amiga(f))
        d = os.path.dirname(amiga(src))
        for md in modes:
            if md == "native":
                g.push(m, exe, d + "/native")
                cmd = "%s/native %s" % (d, args)
            else:
                g.push(m, os.path.join(ROOT, "build/os4/boing"), "RAM:bbg/boing")
                cmd = "RAM:bbg/boing run %s%s %s" % ("--jit " if md == "jit" else "", amiga(src), args)
            m.tool("amiga_dos_command", command="cd " + d)
            if shot:
                m.tool("amiga_dos_command", command="run >NIL: %s >RAM:bbg/shot.out *>RAM:bbg/shot.err" % cmd)
                time.sleep(shot[1])
                screendump(shot[0])
                stop_ours(m)
                time.sleep(3)
                print(str(m.tool("amiga_dos_command", command="type RAM:bbg/shot.out")))
                continue
            out = run(m, cmd, "RAM:bbg/%s.out" % md, limit)
            print("== %s: %s\n%s" % (md, cmd, out.strip()))
            ok &= "FAIL" not in out
        n = g.reapers(m)
        if n:
            print("Grim Reapers: %d" % n)
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Riffwright on an AmigaOS 4 guest: smoke test, benchmarks, screenshots.

    BB_GUEST=m1 examples/riffwright/tools/guest.py push            binary, sources, demos -> DH1:riffwright/
    BB_GUEST=m1 examples/riffwright/tools/guest.py smoke [SHOTDIR]  play a demo, switch views by key,
                                                                    screenshot each, check it quits cleanly
    BB_GUEST=m1 examples/riffwright/tools/guest.py bench [N]       --bench N frames: native, VM, VM --jit
    BB_GUEST=m1 examples/riffwright/tools/guest.py shot NAME        screenshot only

Needs build/Riffwright (build/boing build examples/riffwright/Riffwright.bbp --target os4
-o build/Riffwright) and build/os4/boing for the VM runs. Takes the guest's FIFO ticket,
emulator lock and banner (tools/os4guest.py). Keys are sent only while Riffwright reports
(--log) that its window is the active one.
"""
import os, re, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(APP, "../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g  # noqa: E402

DIR = "DH1:riffwright"
SONG = DIR + "/demos/harbour_lights.mod"


def hmp_shot(path_local):
    """QEMU screendump of the whole guest screen (HMP on the QEMU machine's 127.0.0.1:2348)."""
    remote = "/tmp/riffwright_shot.ppm"
    cmd = "printf 'screendump %s\\n' | nc -w 3 127.0.0.1 2348 >/dev/null; sleep 1" % remote
    if g.SSH:
        subprocess.run(["ssh", g.SSH, cmd], check=True, timeout=30)
        subprocess.run(["scp", "-q", "%s:%s" % (g.SSH, remote), path_local + ".ppm"], check=True, timeout=60)
    else:
        subprocess.run(["sh", "-c", cmd.replace(remote, path_local + ".ppm")], check=True, timeout=30)
    subprocess.run(["magick", path_local + ".ppm", path_local + ".png"], check=True)
    os.unlink(path_local + ".ppm")
    print("screenshot", path_local + ".png")


def dos(m, c):
    return str(m.tool("amiga_dos_command", command=c))


def push_all(m):
    dos(m, "makedir %s %s/demos QUIET" % (DIR, DIR))
    files = [(ROOT + "/build/Riffwright", DIR + "/Riffwright")]
    for f in sorted(os.listdir(APP)):
        if os.path.splitext(f)[1] in (".bas", ".bbp", ".afg", ".guide", ".info"):
            files.append((os.path.join(APP, f), DIR + "/" + f))
    for f in sorted(os.listdir(APP + "/demos")):
        if f.endswith(".mod"):
            files.append((os.path.join(APP, "demos", f), DIR + "/demos/" + f))
    if os.path.exists(ROOT + "/build/os4/boing"):
        files.append((ROOT + "/build/os4/boing", DIR + "/boing"))
    for local, remote in files:
        print(g.push(m, local, remote))


def wait_for(m, outf, text, limit):
    t = time.time()
    while time.time() - t < limit:
        out = dos(m, "type %s" % outf)
        if text in out:
            return out
        time.sleep(1.5)
    return None


def key(m, outf, code):
    out = dos(m, "type %s" % outf)
    last = [l.strip() for l in out.splitlines() if l.strip() in ("active", "inactive")]
    if not last or last[-1] != "active":
        raise SystemExit("Riffwright's window is not the active one: not sending keys (%r)" % last[-1:])
    m.tool("amiga_input_key", rawkey=code, direction="down")
    time.sleep(0.12)
    m.tool("amiga_input_key", rawkey=code, direction="up")
    time.sleep(0.3)


def smoke(m, shots):
    os.makedirs(shots, exist_ok=True)
    outf = "RAM:riffwright.log"
    dos(m, "delete %s QUIET" % outf)
    dos(m, "run >NIL: %s/Riffwright %s --play --log --quit-after 40 >%s" % (DIR, SONG, outf))
    ok = wait_for(m, outf, "active", 30) is not None
    print("window active:", ok)
    if not ok:
        print(dos(m, "type %s" % outf))
        return False
    time.sleep(3)
    hmp_shot(os.path.join(shots, "pattern_playing"))
    key(m, outf, "59")             # F10: samples
    time.sleep(1.5)
    hmp_shot(os.path.join(shots, "samples"))
    key(m, outf, "59")             # F10: song
    time.sleep(1.5)
    hmp_shot(os.path.join(shots, "song"))
    key(m, outf, "59")             # back to the pattern
    key(m, outf, "45")             # Esc: stop
    key(m, outf, "40")             # Space: edit mode
    for k in ("31", "21", "32"):   # Z S X: C-2 C#2 D-2 into the pattern
        key(m, outf, k)
    time.sleep(1)
    hmp_shot(os.path.join(shots, "editing"))
    out = wait_for(m, outf, "quit", 60)
    print("log:\n" + (out or dos(m, "type %s" % outf)))
    time.sleep(2)
    st = dos(m, "status")
    left = "Riffwright" in st
    print("process gone:", not left)
    return out is not None and not left


def bench(m, n):
    res = {}
    runs = [("native", "%s/Riffwright" % DIR),
            ("vm", "%s/boing run %s/Riffwright.bbp" % (DIR, DIR)),
            ("jit", "%s/boing run --jit %s/Riffwright.bbp" % (DIR, DIR))]
    for name, cmd in runs:
        outf = "RAM:riffwright_%s.out" % name
        dos(m, "delete %s QUIET" % outf)
        dos(m, "run >NIL: %s %s --bench %d >%s *>%s.err" % (cmd, SONG, n, outf, outf))
        out = wait_for(m, outf, "worst ms", 300)
        print("==", name, "\n" + (out or dos(m, "type %s.err" % outf)))
        res[name] = out
        time.sleep(2)
    return res


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "smoke"
    m = g.MCP(g.URL)
    with g.testing("Riffwright (Boing BASIC tracker): " + what):
        if what == "push":
            push_all(m)
        elif what == "smoke":
            push_all(m)
            ok = smoke(m, sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "riffwright"))
            print("SMOKE", "PASS" if ok else "FAIL")
            sys.exit(0 if ok else 1)
        elif what == "bench":
            push_all(m)
            bench(m, int(sys.argv[2]) if len(sys.argv) > 2 else 500)
        elif what == "shot":
            hmp_shot(sys.argv[2])


main()

#!/usr/bin/env python3
"""Tincture on an AmigaOS 4 guest: deploy, smoke test, benchmarks, screenshots.

    BB_GUEST=m1 examples/tincture/tools/guest.py push             sources, help, icons, binaries -> DH1:tincture/
    BB_GUEST=m1 examples/tincture/tools/guest.py smoke [SHOTDIR]  every tool through the real handlers, undo all,
                                                                  redo all, a screenshot; checks it quits cleanly
    BB_GUEST=m1 examples/tincture/tools/guest.py demo [SHOTDIR]   paints demo/*.tsc scripts, screenshots each
    BB_GUEST=m1 examples/tincture/tools/guest.py bench [N]        --bench N strokes: native, VM, VM --jit
    BB_GUEST=m1 examples/tincture/tools/guest.py run 'ARGS'       run the VM build with ARGS, print its output

Needs build/os4/boing (tools/build-os4.sh) and, for native runs, build/Tincture
(build/boing build examples/tincture/Tincture.bbp --target os4 -o build/Tincture).
Takes the guest's FIFO ticket, emulator lock and banner (tools/os4guest.py). Sends no input:
the smoke and bench modes drive Tincture's own event handlers.
"""
import os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(APP, "../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g  # noqa: E402

DIR = "DH1:tincture"


def hmp_shot(path_local):
    """QEMU screendump of the whole guest screen (HMP on the QEMU machine's 127.0.0.1:2348)."""
    remote = "/tmp/tincture_shot.ppm"
    cmd = "printf 'screendump %s\\n' | nc -w 3 127.0.0.1 2348 >/dev/null; sleep 1" % remote
    if g.SSH:
        subprocess.run(["ssh", g.SSH, cmd], check=True, timeout=30)
        subprocess.run(["scp", "-q", "%s:%s" % (g.SSH, remote), path_local + ".ppm"], check=True, timeout=60)
    else:
        subprocess.run(["sh", "-c", cmd.replace(remote, path_local + ".ppm")], check=True, timeout=30)
    from PIL import Image
    Image.open(path_local + ".ppm").save(path_local + ".png")
    os.unlink(path_local + ".ppm")
    print("screenshot", path_local + ".png")


def dos(m, c):
    return str(m.tool("amiga_dos_command", command=c))


def push_all(m, binaries=True):
    dos(m, "makedir %s %s/Icons %s/demo QUIET" % (DIR, DIR, DIR))
    files = []
    for f in sorted(os.listdir(APP)):
        if os.path.splitext(f)[1] in (".bas", ".bbp", ".afg", ".guide"):
            files.append((os.path.join(APP, f), DIR + "/" + f))
    icons = APP + "/Icons"
    files.append((icons + "/Tincture.info", DIR + "/Tincture.info"))
    files.append((icons + "/Tincture.guide.info", DIR + "/Tincture.guide.info"))
    files.append((icons + "/picture.info", DIR + "/Icons/picture.info"))
    for f in sorted(os.listdir(APP + "/demo")):
        files.append((os.path.join(APP, "demo", f), DIR + "/demo/" + f))
    if binaries:
        if os.path.exists(ROOT + "/build/os4/boing"):
            files.append((ROOT + "/build/os4/boing", DIR + "/boing"))
        if os.path.exists(ROOT + "/build/Tincture"):
            files.append((ROOT + "/build/Tincture", DIR + "/Tincture"))
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


def gone(m):
    st = dos(m, "status")
    return "tincture" not in st.lower()


def vm_cmd():
    return "%s/boing run %s/Tincture.bbp" % (DIR, DIR)


def smoke(m, shots, native=False):
    os.makedirs(shots, exist_ok=True)
    outf = "RAM:tincture.log"
    dos(m, "delete %s RAM:tincture-smoke.ppm QUIET" % outf)
    cmd = ("%s/Tincture" % DIR) if native else vm_cmd()
    dos(m, "run >NIL: %s --smoke --hold 6 --log >%s *>%s.err" % (cmd, outf, outf))
    out = wait_for(m, outf, "SMOKE redo-all", 120)
    print(out or dos(m, "type %s.err" % outf))
    if out:
        time.sleep(1.5)
        hmp_shot(os.path.join(shots, "smoke" + ("_native" if native else "")))
    end = wait_for(m, outf, "quit", 30)
    time.sleep(2)
    ok = bool(out) and "undo-all PASS" in out and end is not None and gone(m)
    print("process gone:", gone(m))
    return ok


def demo(m, shots):
    os.makedirs(shots, exist_ok=True)
    for f in sorted(os.listdir(APP + "/demo")):
        if not f.endswith(".tsc"):
            continue
        name = os.path.splitext(f)[0]
        outf = "RAM:tincture_%s.log" % name
        dos(m, "delete %s QUIET" % outf)
        dos(m, "run >NIL: %s/Tincture --script %s/demo/%s --hold 8 --log >%s *>%s.err"
            % (DIR, DIR, f, outf, outf) if os.path.exists(ROOT + "/build/Tincture") else
            "run >NIL: %s --script %s/demo/%s --hold 8 --log >%s *>%s.err" % (vm_cmd(), DIR, f, outf, outf))
        ok = wait_for(m, outf, "active", 120)
        time.sleep(3)
        hmp_shot(os.path.join(shots, name))
        wait_for(m, outf, "quit", 40)
        time.sleep(2)
        print(name, "ok" if ok else dos(m, "type %s.err" % outf), "gone:", gone(m))


def bench(m, n):
    runs = [("native", "%s/Tincture" % DIR), ("vm", vm_cmd()),
            ("jit", "%s/boing run --jit %s/Tincture.bbp" % (DIR, DIR))]
    for name, cmd in runs:
        if name == "native" and not os.path.exists(ROOT + "/build/Tincture"):
            continue
        outf = "RAM:tincture_%s.out" % name
        dos(m, "delete %s QUIET" % outf)
        dos(m, "run >NIL: %s --bench %d >%s *>%s.err" % (cmd, n, outf, outf))
        out = wait_for(m, outf, "BENCH full view", 600)
        print("==", name, "\n" + (out or dos(m, "type %s.err" % outf)))
        wait_for(m, outf, "BENCH undo", 60)
        time.sleep(3)
        print("gone:", gone(m))


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "smoke"
    m = g.MCP(g.URL)
    with g.testing("Tincture (Boing BASIC paint): " + what):
        if what == "push":
            push_all(m)
        elif what == "smoke":
            push_all(m)
            shots = sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "tincture")
            ok = smoke(m, shots)
            if ok and os.path.exists(ROOT + "/build/Tincture"):
                ok = smoke(m, shots, native=True)
            print("SMOKE", "PASS" if ok else "FAIL")
            sys.exit(0 if ok else 1)
        elif what == "demo":
            push_all(m)
            demo(m, sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "tincture"))
        elif what == "bench":
            push_all(m)
            bench(m, int(sys.argv[2]) if len(sys.argv) > 2 else 20)
        elif what == "run":
            outf = "RAM:tincture_run.out"
            dos(m, "delete %s QUIET" % outf)
            print(dos(m, "%s %s >%s *>%s" % (vm_cmd(), sys.argv[2], outf, outf)))
            print(dos(m, "type %s" % outf))
        elif what == "shot":
            hmp_shot(sys.argv[2])


main()

#!/usr/bin/env python3
"""Tincture on an AmigaOS 4 guest: deploy, smoke test, benchmarks, screenshots.

    BB_GUEST=m1 examples/tincture/tools/guest.py push             sources, help, icons, binaries -> DH1:tincture/
    BB_GUEST=m1 examples/tincture/tools/guest.py smoke [SHOTDIR]  every tool through the real handlers, undo all,
                                                                  redo all, a screenshot; checks it quits cleanly
    BB_GUEST=m1 examples/tincture/tools/guest.py input [SHOTDIR]  real mouse input into its own active window:
                                                                  steer into the view, paint a stroke, check it
    BB_GUEST=m1 examples/tincture/tools/guest.py arexx            drive a running Tincture from demo/arexx-test.rexx
    BB_GUEST=m1 examples/tincture/tools/guest.py demo [SHOTDIR]   paints demo/*.tsc scripts, screenshots each
    BB_GUEST=m1 examples/tincture/tools/guest.py bench [N]        --bench N strokes: native, VM, VM --jit
    BB_GUEST=m1 examples/tincture/tools/guest.py run 'ARGS'       run the VM build with ARGS, print its output

Needs build/os4/boing (tools/build-os4.sh) and, for native runs, build/Tincture
(build/boing build examples/tincture/Tincture.bbp --target os4 -o build/Tincture).
Takes the guest's FIFO ticket, emulator lock and banner (tools/os4guest.py). Only `input`
sends input, and only while Tincture reports (--log) that its window is the active one and
the pointer is over its picture; the other modes drive Tincture's own event handlers.
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


def launch(m, cmdline):
    """Start a command in the background with a 1 MB stack: processes started through the
    bridge get 64 KB, and the $STACK cookie isn't honoured there (the VM overflowed it)."""
    tmp = tempfile.NamedTemporaryFile("w", suffix=".run", delete=False)
    tmp.write("stack 1048576\n%s\n" % cmdline)
    tmp.close()
    script = "RAM:tincture-%d.run" % int(time.time())     # own name: an old one may still be open
    g.push(m, tmp.name, script)
    os.unlink(tmp.name)
    dos(m, "run >NIL: execute %s" % script)


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
    outf = "RAM:tincture-%d.log" % int(time.time())      # own names: a crashed run may hold old ones open
    dos(m, "delete RAM:tincture-smoke.ppm RAM:tincture.trace QUIET")
    cmd = ("%s/Tincture" % DIR) if native else vm_cmd()
    launch(m, "%s --smoke --hold 6 --log --trace >%s *>%s.err" % (cmd, outf, outf))
    out = wait_for(m, outf, "SMOKE redo-all", 120)
    print(out or dos(m, "type %s.err" % outf))
    if out:
        time.sleep(1.5)
        hmp_shot(os.path.join(shots, "smoke" + ("_native" if native else "")))
    end = wait_for(m, outf, "quit", 30)
    time.sleep(2)
    ok = bool(out) and "undo-all PASS" in out and end is not None and gone(m)
    print("process gone:", gone(m))
    if not ok:
        print("trace (last steps):", dos(m, "type RAM:tincture.trace").strip().splitlines()[-12:])
        hmp_shot(os.path.join(shots, "smoke_fail" + ("_native" if native else "")))
    return ok


def demo(m, shots):
    os.makedirs(shots, exist_ok=True)
    for f in sorted(os.listdir(APP + "/demo")):
        if not f.endswith(".tsc"):
            continue
        name = os.path.splitext(f)[0]
        outf = "RAM:tincture_%s_%d.log" % (name, int(time.time()))
        dos(m, "delete %s QUIET" % outf)
        prog = ("%s/Tincture" % DIR) if os.path.exists(ROOT + "/build/Tincture") else vm_cmd()
        launch(m, "%s --script %s/demo/%s --hold 8 --log >%s *>%s.err" % (prog, DIR, f, outf, outf))
        ok = wait_for(m, outf, "active", 120)
        time.sleep(3)
        hmp_shot(os.path.join(shots, name))
        wait_for(m, outf, "quit", 40)
        time.sleep(2)
        print(name, "ok" if ok else dos(m, "type %s.err" % outf), "gone:", gone(m))


def last_move(m, outf):
    out = dos(m, "type %s" % outf)
    mv = [l.split() for l in out.splitlines() if l.startswith("move ")]
    return (int(mv[-1][1]), int(mv[-1][2])) if mv else None


def is_active(m, outf):
    out = dos(m, "type %s" % outf)
    st = [l.strip() for l in out.splitlines() if l.strip() in ("active", "inactive")]
    return bool(st) and st[-1] == "active"


def input_test(m, shots, native=True):
    """Real mouse input into Tincture's own (active) window: steer the pointer into the view
    using the positions Tincture reports, paint a stroke, check it in the log."""
    os.makedirs(shots, exist_ok=True)
    outf = "RAM:tincture_in_%d.log" % int(time.time())
    dos(m, "delete %s QUIET" % outf)
    prog = ("%s/Tincture" % DIR) if native and os.path.exists(ROOT + "/build/Tincture") else vm_cmd()
    launch(m, "%s --size 320x200 --hold 45 --log >%s *>%s.err" % (prog, outf, outf))
    out = wait_for(m, outf, "active", 120)
    if not out:
        print(dos(m, "type %s.err" % outf))
        return False
    geom = [l.split() for l in out.splitlines() if l.startswith("geom ")][-1]
    wl, wt, vl, vt = (int(v) for v in geom[1:5])
    mv = lambda dx, dy: m.tool("amiga_input_mouse_move", dx=dx, dy=dy)
    for _ in range(6):
        mv(-400, -400)                       # park at the top-left corner
    tx, ty = wl + vl + 120, wt + vt + 120     # a point in the view
    x = y = 0
    while x < tx or y < ty:                   # small steps: no pointer acceleration
        sx, sy = min(20, tx - x), min(20, ty - y)
        mv(sx, sy)
        x += sx
        y += sy
    time.sleep(1)
    pos = last_move(m, outf)
    print("pointer in the view at", pos)
    for _ in range(6):                        # correct towards view (120, 120)
        if not pos or (abs(pos[0] - 120) <= 2 and abs(pos[1] - 120) <= 2):
            break
        mv(max(-20, min(20, 120 - pos[0])), max(-20, min(20, 120 - pos[1])))
        time.sleep(0.6)
        pos = last_move(m, outf)
    if not pos or not is_active(m, outf):
        print("not over our active window: no clicks sent", pos)
        return False
    m.tool("amiga_input_click", button="left", direction="down")
    for _ in range(12):
        mv(10, 3)
        time.sleep(0.1)
    m.tool("amiga_input_click", button="left", direction="up")
    time.sleep(1.5)
    out = dos(m, "type %s" % outf)
    ups = [l for l in out.splitlines() if l.startswith("up ")]
    print("\n".join(l for l in out.splitlines() if l.startswith(("down ", "up "))))
    hmp_shot(os.path.join(shots, "input_stroke"))
    ok = bool(ups) and "undo=1" in ups[-1] and "pixel=#000000" in ups[-1]
    wait_for(m, outf, "quit", 90)
    time.sleep(2)
    print("process gone:", gone(m))
    return ok and gone(m)


def arexx_test(m):
    """Start Tincture, drive it from an ARexx script through its TINCTURE port, check the replies."""
    t = int(time.time())
    outf, rxout = "RAM:tincture_rx_%d.log" % t, "RAM:tincture_rx_%d.out" % t
    prog = ("%s/Tincture" % DIR) if os.path.exists(ROOT + "/build/Tincture") else vm_cmd()
    launch(m, "%s --hold 60 --log >%s *>%s.err" % (prog, outf, outf))
    if not wait_for(m, outf, "active", 120):
        print(dos(m, "type %s.err" % outf))
        return False
    time.sleep(1)
    dos(m, "rx %s/demo/arexx-test.rexx >%s" % (DIR, rxout))
    out = dos(m, "type %s" % rxout)
    print(out)
    wait_for(m, outf, "quit", 30)
    time.sleep(3)
    ok = ("pixel #FF0000" in out and "info 64 48 2 2" in out and "rc 10" in out and "done" in out and gone(m))
    print("process gone:", gone(m))
    return ok


def bench(m, n):
    runs = [("native", "%s/Tincture" % DIR), ("vm", vm_cmd()),
            ("jit", "%s/boing run --jit %s/Tincture.bbp" % (DIR, DIR))]
    for name, cmd in runs:
        if name == "native" and not os.path.exists(ROOT + "/build/Tincture"):
            continue
        outf = "RAM:tincture_%s_%d.out" % (name, int(time.time()))
        dos(m, "delete %s QUIET" % outf)
        launch(m, "%s --bench %d >%s *>%s.err" % (cmd, n, outf, outf))
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
        elif what == "input":
            push_all(m)
            ok = input_test(m, sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "tincture"))
            print("INPUT", "PASS" if ok else "FAIL")
            sys.exit(0 if ok else 1)
        elif what == "arexx":
            push_all(m)
            ok = arexx_test(m)
            print("AREXX", "PASS" if ok else "FAIL")
            sys.exit(0 if ok else 1)
        elif what == "demo":
            push_all(m)
            demo(m, sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "tincture"))
        elif what == "bench":
            push_all(m)
            bench(m, int(sys.argv[2]) if len(sys.argv) > 2 else 20)
        elif what == "run":
            outf = "RAM:tincture_run_%d.out" % int(time.time())
            dos(m, "delete %s QUIET" % outf)
            launch(m, "%s %s >%s *>%s" % (vm_cmd(), sys.argv[2], outf, outf))
            time.sleep(20)
            print(dos(m, "type %s" % outf))
        elif what == "hold":
            # keep the lock and banner (to look at / close our own crashed task by hand)
            print("holding the guest", flush=True)
            time.sleep(int(sys.argv[2]) if len(sys.argv) > 2 else 300)
        elif what == "shot":
            hmp_shot(sys.argv[2])


main()

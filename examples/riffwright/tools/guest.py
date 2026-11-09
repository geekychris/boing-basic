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
os.environ.setdefault("BB_SESSION_TIMEOUT", "290")   # the guests' rule: at most 5 minutes per lock ticket
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


def cleanup(m):
    """Ctrl-C any of our own processes still running (programs loaded from DH1:riffwright/)."""
    dos(m, "status >RAM:riffwright_status.txt")
    st = dos(m, "type RAM:riffwright_status.txt")
    left = re.findall(r"Process\s+(\d+): Loaded as command: (%s/\S+)" % re.escape(DIR), st)
    for num, cmd in left:
        print("breaking our process", num, cmd)
        dos(m, "break %s C" % num)
    dos(m, "delete RAM:riffwright_status.txt QUIET")
    return len(left)


def push_all(m):
    dos(m, "makedir %s %s/demos QUIET" % (DIR, DIR))
    files = [(ROOT + "/build/Riffwright", DIR + "/Riffwright")]
    for f in sorted(os.listdir(APP)):
        if os.path.splitext(f)[1] in (".bas", ".bbp", ".afg", ".guide", ".info"):
            files.append((os.path.join(APP, f), DIR + "/" + f))
    files.append((APP + "/icons/Riffwright.info", DIR + "/Riffwright.info"))
    files.append((APP + "/icons/def_mod.info", DIR + "/def_mod.info"))
    for f in sorted(os.listdir(APP + "/demos")):
        if f.endswith(".mod"):
            files.append((os.path.join(APP, "demos", f), DIR + "/demos/" + f))
            files.append((APP + "/icons/def_mod.info", DIR + "/demos/" + f + ".info"))
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
    dos(m, "run >NIL: %s/Riffwright %s --play --log --quit-after 75 >%s" % (DIR, SONG, outf))
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
    # the ARexx port
    def rx(cmd):
        r = dos(m, "rx \"options results; address RIFFWRIGHT '%s'; say 'RC=' || rc 'RESULT=' || result\"" % cmd)
        print("ARexx %-38s -> %s" % (cmd, r.strip().splitlines()[-1] if r.strip() else r))
        return r
    ok_rx = "Riffwright 1.0" in rx("VERSION")
    rx("PLAY 2")
    time.sleep(2)
    ok_rx &= "RESULT=" in rx("POSITION")
    rx("STOP")
    ok_rx &= "Boing Shuffle" in rx("LOAD %s/demos/boing_shuffle.mod" % DIR)
    rx("SAVE RAM:riffwright_rx.mod")
    size = dos(m, "list RAM:riffwright_rx.mod")
    print("saved by ARexx:", size.strip().splitlines()[0] if size.strip() else size)
    ok_rx &= "riffwright_rx.mod" in size
    dos(m, "delete RAM:riffwright_rx.mod RAM:riffwright_rx.mod.info QUIET")
    print("arexx ok:", ok_rx)
    out = wait_for(m, outf, "quit", 90)
    print("log:\n" + (out or dos(m, "type %s" % outf)))
    time.sleep(2)
    st = dos(m, "status")
    left = "Riffwright" in st
    print("process gone:", not left)
    return out is not None and not left and ok_rx


def bench(m, n, extra="", only=None):
    res = {}
    runs = [("native", "%s/Riffwright" % DIR),
            ("vm", "%s/boing run %s/Riffwright.bbp" % (DIR, DIR)),
            ("jit", "%s/boing run --jit %s/Riffwright.bbp" % (DIR, DIR))]
    for name, cmd in runs:
        if only and name not in only:
            continue
        outf = "RAM:riffwright_%s.out" % name
        dos(m, "delete %s QUIET" % outf)
        dos(m, "run >NIL: %s %s --bench %d %s >%s *>%s.err" % (cmd, SONG, n, extra, outf, outf))
        out = wait_for(m, outf, "worst ms", 150)
        print("==", name, "\n" + (out or dos(m, "type %s.err" % outf)))
        res[name] = out
        time.sleep(2)
    return res


def bench_main():
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    modes = sys.argv[3].split(",") if len(sys.argv) > 3 else ["native", "vm", "jit"]
    extra = " ".join(sys.argv[4:])
    m = g.MCP(g.URL)
    for mode in modes:
        with g.testing("Riffwright bench %s" % mode):
            try:
                bench(m, n, extra, [mode])
            finally:
                cleanup(m)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "smoke"
    m = g.MCP(g.URL)
    rc = 0
    with g.testing("Riffwright (Boing BASIC tracker): " + what):
      try:
          if what == "push":
              push_all(m)
          elif what == "smoke":
              push_all(m)
              ok = smoke(m, sys.argv[2] if len(sys.argv) > 2 else os.path.join(tempfile.gettempdir(), "riffwright"))
              print("SMOKE", "PASS" if ok else "FAIL")
              rc = 0 if ok else 1
          elif what == "bench":
              # one ticket for the push, then one ticket per mode (bench_main)
              push_all(m)
          elif what == "start":
              # the gentlest check: start, screenshot, let it quit by itself
              push_all(m)
              outf = "RAM:riffwright.log"
              dos(m, "delete %s QUIET" % outf)
              dos(m, "run >NIL: %s/Riffwright %s --play --log --quit-after 15 >%s *>%s.err" % (DIR, SONG, outf, outf))
              time.sleep(8)
              hmp_shot(os.path.join(tempfile.gettempdir(), "riffwright_start"))
              print("log:", wait_for(m, outf, "quit", 40))
              print("err:", dos(m, "type %s.err" % outf))
          elif what == "shot":
              hmp_shot(sys.argv[2])
      finally:
        time.sleep(1)
        if cleanup(m):
            print("(had to stop leftover processes)")
    if what == "bench" and rc == 0:
        bench_main()
    sys.exit(rc)


main()

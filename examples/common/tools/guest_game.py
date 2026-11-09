#!/usr/bin/env python3
"""guest_game.py - run one of the Boing BASIC game ports on an AmigaOS 4 guest (tools/os4guest.py:
FIFO ticket, emulator lock, "CLAUDE IS TESTING" banner; BB_GUEST=m1b|m1c|local; m1 is the user's).

    guest_game.py PROJECT.bbp MODE [game args...]
      MODE vm      build/os4/boing run PROJECT.bbp args
           jit     the same with --jit
           native  boing build --target os4, then the executable
           all     vm, jit and native, each in its own guest session
           shot:OUT.png:SECONDS[:native]   start the game (VM, or the native build), wait,
                   save a screenshot of the guest's screen (QEMU HMP screendump), stop it
           shots:LIST.txt[:native]   lines "OUT.png SECONDS game args", one session each
           frames:LIST.txt[:native]  the game's own picture (--saveshot: Canvas.SaveImage on the
                   guest, then pulled): lines "OUT.png FRAME game args", one session each;
                   independent of what screen is in front
    e.g. guest_game.py examples/tank_duel/TankDuel.bbp all --bench 300

With --bench N the run is also a smoke test: the game state hash the guest prints must equal
the one the console bench (Bench.bbp beside the project, --frames N) gives on the Mac
("SMOKE PASS" / "SMOKE FAIL"; the exit code is 1 on a failure).

Sharing the guest: every mode, shot and frame is a separate session (its own ticket and lock,
in a forked child), each limited to BB_SESSION_TIMEOUT seconds (default 300; os4guest's
watchdog also gives the guest up when the bridge goes silent). A session's files go to its own
directory RAM:bbg-<pid>/<path in the repo> (the project's files and its Module=/Form= files, so
../common paths work there); only processes loaded from that directory are stopped, and the
directory is deleted at the end. Waits for "picture hash" (the end of a --bench report),
"saved " or a runtime error (BB_TEST_TIMEOUT, default 240 s), prints the output, and reports
any Grim Reaper left.
"""
import os, re, subprocess, sys, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
os.environ.setdefault("BB_SESSION_TIMEOUT", "300")
import os4guest as g

if os.environ.get("BB_GUEST", "local") == "m1":
    raise SystemExit("guest_game: BB_GUEST=m1 is the user's guest; use m1b, m1c or local")

RUN = "RAM:bbg-%d" % os.getpid()


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
    return RUN + "/" + os.path.relpath(p, ROOT)


def run(m, cmd, outf, limit):
    m.tool("amiga_dos_command", command="delete %s %s.err QUIET" % (outf, outf))
    started = str(m.tool("amiga_dos_command", command="run >NIL: %s >%s *>%s.err" % (cmd, outf, outf)))
    t0, out = time.time(), ""
    while time.time() - t0 < limit:
        time.sleep(3)
        out = str(m.tool("amiga_dos_command", command="type %s" % outf))
        err = str(m.tool("amiga_dos_command", command="type %s.err" % outf))
        if "picture hash" in out or "bye" in out or "saved " in out:
            return out + err
        if "runtime error" in err or "error:" in err:
            stop_ours(m)
            return out + "\n" + err + "\nFAIL (error)"
    stop_ours(m)
    return out + "\n(run: %s)\nFAIL (timed out after %ds)" % (started.strip()[-300:], limit)


def stop_ours(m):
    """Ctrl-C to the processes this session started (loaded from its own RAM:bbg-<pid>/)."""
    st = str(m.tool("amiga_dos_command", command="status"))
    for num in re.findall(r"Process\s+(\d+): Loaded as command: %s/" % re.escape(RUN), st):
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


def pull_frame(m, out_png):
    import tempfile
    from PIL import Image
    tmp = tempfile.mktemp(suffix=".ppm")
    if g.SSH:
        m.tool("amiga_pull_file", amiga_path=RUN + "/shot.ppm", local_path="/tmp/bbg_frame.ppm")
        subprocess.run(["scp", "-q", g.SSH + ":/tmp/bbg_frame.ppm", tmp], check=True)
    else:
        m.tool("amiga_pull_file", amiga_path=RUN + "/shot.ppm", local_path=tmp)
    Image.open(tmp).save(out_png)
    os.unlink(tmp)
    print("frame", out_png)


def session(src, md, job, args, exe, want, limit):
    """One guest session: push, run, check, then stop our processes and delete our directory."""
    m = g.MCP(g.URL)
    ok = True
    fl = files_of(src)
    d = os.path.dirname(amiga(src))
    with g.testing("Boing BASIC: %s (%s)" % (os.path.basename(src), md)):
        try:
            t0 = time.time()
            dirs = sorted({os.path.dirname(amiga(p)) for p in fl})
            m.tool("amiga_dos_command", command="makedir " + " ".join(
                sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(1, x.count("/") + 2)})) + " QUIET")
            for f in fl:
                g.push(m, f, amiga(f))
            if md == "native":
                g.push(m, exe, d + "/native")
                base = "%s/native" % d
            else:
                g.push(m, os.path.join(ROOT, "build/os4/boing"), RUN + "/boing")
                base = "%s/boing run %s%s" % (RUN, "--jit " if md == "jit" else "", amiga(src))
            print("(pushed in %.0f s)" % (time.time() - t0))
            m.tool("amiga_dos_command", command="cd " + d)
            if job[0] == "frame":
                out_png, fr, gargs = job[1:]
                o = run(m, "%s %s --saveshot %s/shot.ppm --shotframe %s" % (base, gargs, RUN, fr),
                        RUN + "/frame.out", limit)
                if "saved " in o:
                    pull_frame(m, out_png)
                else:
                    print("FAIL no frame for %s:\n%s" % (out_png, o[-400:]))
                    print(m.tool("amiga_dos_command", command="list %s" % d))
                    print(m.tool("amiga_dos_command", command="status"))
                    ok = False
            elif job[0] == "shot":
                out_png, secs, gargs = job[1:]
                m.tool("amiga_dos_command", command="run >NIL: %s %s >%s/shot.out *>%s/shot.err" % (base, gargs, RUN, RUN))
                time.sleep(secs)
                screendump(out_png)
            else:
                cmd = "%s %s" % (base, args)
                out = run(m, cmd, "%s/%s.out" % (RUN, md), limit)
                print("== %s: %s\n%s" % (md, cmd, out.strip()))
                ok &= "FAIL" not in out
                if want:
                    good = ("hash " + want) in out
                    print("SMOKE %s (%s: state hash %s on the Mac)" % ("PASS" if good else "FAIL", md, want))
                    ok &= good
        finally:
            stop_ours(m)
            time.sleep(3)
            m.tool("amiga_dos_command", command="cd RAM:")
            m.tool("amiga_dos_command", command="delete %s ALL QUIET FORCE" % RUN)
            n = g.reapers(m)
            if n:
                print("Grim Reapers on the guest: %d" % n)
                ok = False
    return ok


def main():
    global RUN
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, mode, args = os.path.abspath(sys.argv[1]), sys.argv[2], " ".join(sys.argv[3:])
    limit = float(os.environ.get("BB_TEST_TIMEOUT", "240"))
    jobs = None
    for kind in ("frames", "shots", "shot"):
        if mode.startswith(kind + ":"):
            parts = mode.split(":")
            if kind == "shot":
                jobs = [("shot", os.path.abspath(parts[1]), float(parts[2]), args)]
                mode = parts[3] if len(parts) > 3 else "vm"
            else:
                rows = [l.strip().split(None, 2) for l in open(parts[1]) if l.strip() and not l.startswith("#")]
                jobs = [("frame" if kind == "frames" else "shot", os.path.abspath(r[0]),
                         r[1] if kind == "frames" else float(r[1]), r[2] if len(r) > 2 else "") for r in rows]
                mode = parts[2] if len(parts) > 2 else "vm"
            break
    modes = ["vm", "jit", "native"] if mode == "all" else [mode]
    exe = None
    if "native" in modes:
        exe = os.path.join(ROOT, "build/os4", os.path.splitext(os.path.basename(src))[0] + ".exe")
        subprocess.check_call([os.path.join(ROOT, "build/boing"), "build", src, "--target", "os4", "-o", exe])
    want = None
    mm = re.search(r"--bench (\d+)", args)
    bench = os.path.join(os.path.dirname(src), "Bench.bbp")
    if mm and os.path.exists(bench) and not jobs:
        extra = re.sub(r"--bench \d+", "", args)
        out = subprocess.run([os.path.join(ROOT, "build/boing"), "run", bench, "--frames", mm.group(1)] + extra.split(),
                             cwd=os.path.dirname(bench), capture_output=True, text=True).stdout
        h = re.search(r"hash ([0-9A-F]{8})", out)
        want = h.group(1) if h else None
        print("Mac console bench: state hash %s" % want)
    ok = True
    sys.stdout.flush()
    for md in modes:
        for job in (jobs or [("bench",)]):
            # a fresh process a session: os4guest's watchdog times a session from its lock
            pid = os.fork()
            if pid == 0:
                RUN = "RAM:bbg-%d" % os.getpid()
                try:
                    good = session(src, md, job, args, exe, want, limit)
                except BaseException as e:
                    print("FAIL (%s)" % e)
                    good = False
                sys.stdout.flush()
                os._exit(0 if good else 1)
            _, st = os.waitpid(pid, 0)
            if st != 0:
                if os.WIFEXITED(st) and os.WEXITSTATUS(st) == 3:
                    print("FAIL (session given up: bridge silent or longer than %ss)" % os.environ["BB_SESSION_TIMEOUT"])
                ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

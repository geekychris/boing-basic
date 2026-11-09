#!/usr/bin/env python3
"""Lander 3D's screens on an AmigaOS 4 guest, played with injected keys: title -> help (2
pages) -> fly -> the autopilot lands -> crash -> game over -> name entry -> high scores ->
title -> quit, with a screenshot of each (QEMU HMP screendump).

    BB_GUEST=m1 examples/lander_3d_bb/tools/guest_flow.py [SHOT_DIR] [vm|native]

Runs build/os4/boing (VM) or the native build from RAM:bbl (deleted afterwards). Takes
the emulator lock and banner (tools/os4guest.py). Keys are only sent while the game
reports (--log) that its window is the active one. One ship (--ships 1), each level
starting 6 m over the x1 pad (--place) and a table of zero scores, so the landing's score
makes the name entry appear. Under 5 minutes (one lock ticket). Exit 1 on a failure.
"""
import os, subprocess, sys, tempfile, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault("BB_SESSION_TIMEOUT", "290")    # the lead's 5-minute cap a lock ticket
import guest as gg
g = gg.g
SHOTS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(tempfile.gettempdir(), "lander_flow")
MODE = sys.argv[2] if len(sys.argv) > 2 else "vm"
SRC = os.path.abspath(os.path.join(HERE, "..", "Lander3D.bbp"))
KEYS = {"space": "40", "h": "25", "b": "35", "return": "44", "esc": "45", "a": "20", "c": "33", "e": "12"}


def main():
    os.makedirs(SHOTS, exist_ok=True)
    m = g.MCP(g.URL)
    dos = lambda c: gg.dos(m, c)
    d = os.path.dirname(gg.amiga(SRC))
    flow = gg.TOP + "/flow.txt"
    ok = True

    def out():
        return dos("type " + flow)

    def key(name):
        last = [l.strip() for l in out().splitlines() if l.strip() in ("active", "inactive")]
        if not last or last[-1] != "active":
            raise SystemExit("our window is not the active one: not sending keys (%r)" % last[-1:])
        m.tool("amiga_input_key", rawkey=KEYS[name], direction="down"); time.sleep(0.2)
        m.tool("amiga_input_key", rawkey=KEYS[name], direction="up"); time.sleep(0.4)

    def wait_for(text, limit):
        t = time.time()
        while time.time() - t < limit:
            o = out()
            if text in o:
                return o
            time.sleep(2)
        print("FAIL: no %r after %ds" % (text, limit))
        return None

    def shot(name):
        gg.screendump(os.path.join(SHOTS, name + ".png"))

    exe = None
    if MODE == "native":
        exe = os.path.join(gg.BROOT, "build/os4/Lander3D.exe")
        subprocess.check_call([os.path.join(gg.BROOT, "build/boing"), "build", SRC, "--target", "os4", "-o", exe])
    with g.testing("Boing BASIC: Lander 3D screens"):
        try:
            fl = gg.files_of(SRC)
            dirs = sorted({os.path.dirname(gg.amiga(p)) for p in fl})
            dos("makedir " + gg.TOP + " " + " ".join(
                sorted({"/".join(x.split("/")[:i]) for x in dirs for i in range(2, x.count("/") + 2)})) + " QUIET")
            for f in fl:
                g.push(m, f, gg.amiga(f))
            zero = tempfile.NamedTemporaryFile("w", suffix=".scores", delete=False)
            zero.write('"ZERO",0\n' * 8)
            zero.close()
            g.push(m, zero.name, d + "/lander_3d.scores")
            os.unlink(zero.name)
            if exe:
                g.push(m, exe, d + "/Lander3D")
                cmd = d + "/Lander3D"
            else:
                g.push(m, os.path.join(gg.BROOT, "build/os4/boing"), gg.TOP + "/boing")
                cmd = gg.TOP + "/boing run " + gg.amiga(SRC) + " --dir " + d + "/"
            dos("cd " + d)
            dos("stack 1048576")
            dos("run >NIL: %s --log --ships 1 --place --quiet >%s *>%s.err" % (cmd, flow, flow))
            ok &= wait_for("state title", 60) is not None
            ok &= wait_for("active", 30) is not None
            time.sleep(4)
            shot("1_title")
            key("h"); time.sleep(2); shot("2_help1")
            key("h"); time.sleep(2); shot("3_help2")
            key("h"); time.sleep(1)
            key("space")
            ok &= wait_for("state play", 60) is not None
            time.sleep(4)
            shot("4_flying")
            key("b")                                     # the autopilot lands it
            ok &= wait_for("state result", 90) is not None
            time.sleep(1)
            shot("5_landed")
            o = wait_for("ships 1\nstate play", 60) or out()
            time.sleep(1)
            key("b")                                     # autopilot off: it drops from 6 m
            ok &= wait_for("state over", 90) is not None
            time.sleep(1)
            shot("6_over")
            time.sleep(3)
            key("space")
            ok &= wait_for("state entry", 30) is not None
            time.sleep(1)
            for k in ("a", "c", "e"):
                key(k)
            shot("7_entry")
            key("return")
            ok &= wait_for("state scores", 30) is not None
            time.sleep(2)
            shot("8_scores")
            sc = dos("type %s/lander_3d.scores" % d)
            print("scores file:", sc.splitlines()[:2])
            if '"ACE"' not in sc:
                print("FAIL: ACE not in the saved table")
                ok = False
            key("space")
            ok &= wait_for("state title", 30) is not None
            key("esc")
            ok &= wait_for("bye", 30) is not None
            print(out())
            print(dos("type %s.err" % flow))
            n = g.reapers(m)
            if n:
                print("FAIL: Grim Reapers: %d" % n)
                ok = False
        finally:
            gg.stop_ours(m)
            time.sleep(2)
            dos("cd RAM:")
            dos("delete %s ALL QUIET FORCE" % gg.TOP)
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

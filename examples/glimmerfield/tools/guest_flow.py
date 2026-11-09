#!/usr/bin/env python3
"""Glimmerfield's screens on the AmigaOS 4 guest: title -> play -> game over -> name entry ->
high scores -> title -> quit, with screenshots (os4guest.shot: QEMU's screendump of the guest's own monitor) of each.

    examples/glimmerfield/tools/guest_flow.py [SHOT_PREFIX]

Needs build/os4/Glimmerfield (boing build Glimmerfield.bbp --target os4). Takes the emulator
lock and banner (tools/os4guest.py). Keys are only sent while the game reports (--log) that
its window is the active one. The game starts with one life and a table of zero scores, so
any score makes the name entry appear.
"""
import os, socket, sys, tempfile, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
sys.path.insert(0, ROOT + "/tools")
import os4guest as g
SHOTS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(tempfile.gettempdir(), "glimmerfield_flow")
if g.GUEST == "m1":
    raise SystemExit("m1 is the user's own guest: run this on BB_GUEST=m1b, m1c or local")
_m = None

def shot(name):
    """os4guest.shot: wakes the blanker, then the guest's own QEMU screendump"""
    print("screenshot", g.shot(_m, "%s_%s.png" % (SHOTS, name)))

def main():
    global _m
    m = _m = g.MCP(g.URL)
    dos = lambda c: str(m.tool("amiga_dos_command", command=c))
    def key(code):
        out = dos("type DH1:glim/flow.txt")
        last = [l for l in out.splitlines() if l.strip() in ("active", "inactive")]
        if not last or last[-1].strip() != "active":
            raise SystemExit("our window is not the active one: not sending keys (%r)" % last[-1:])
        m.tool("amiga_input_key", rawkey=code, direction="down"); time.sleep(0.15)
        m.tool("amiga_input_key", rawkey=code, direction="up"); time.sleep(0.25)
    def wait_for(text, limit):
        t = time.time()
        while time.time() - t < limit:
            out = dos("type DH1:glim/flow.txt")
            if text in out:
                return out
            time.sleep(2)
        return None
    with g.testing("Boing BASIC: Glimmerfield screens"):
        print(g.push(m, ROOT + "/build/os4/Glimmerfield", "DH1:glim/Glimmerfield"))
        dos("delete DH1:glim/flow.txt DH1:glim/glimmerfield.scores QUIET")
        zero = tempfile.NamedTemporaryFile("w", suffix=".scores", delete=False)
        zero.write('"ZERO",0\n' * 8)
        zero.close()
        print(g.push(m, zero.name, "DH1:glim/glimmerfield.scores"))
        os.unlink(zero.name)
        dos("run >NIL: DH1:glim/Glimmerfield --lives 1 --log >DH1:glim/flow.txt")
        print("title:", wait_for("mode title", 30) is not None)
        time.sleep(4)
        shot("1title")
        key("40")                                   # Space: play (our window is the active one)
        out = wait_for("mode play", 15)
        print("play:", out is not None)
        time.sleep(3)
        shot("2play")
        out = wait_for("mode entry", 240)
        print("after game over:", out)
        if not out:
            raise SystemExit("no name entry")
        shot("3entry")
        for k in ("14", "12", "21", "14"):          # T E S T
            key(k)
        time.sleep(1)
        shot("3entry_typed")
        key("44")                                   # Return
        out = wait_for("mode scores", 15)
        print("scores:", out is not None)
        time.sleep(1)
        shot("4scores")
        print("file:", dos("type DH1:glim/glimmerfield.scores"))
        time.sleep(1)
        key("40")                                   # Space: leave the scores
        time.sleep(2)
        shot("5title")
        time.sleep(2)
        key("45")                                   # Esc on the title: quit
        print("end:", wait_for("bye", 20))
        dos("delete DH1:glim/glimmerfield.scores DH1:glim/flow.txt QUIET")

if __name__ == "__main__":
    main()

#!/bin/sh
# os4-pointer-shot.sh OUT.png - a screenshot of the MousePointer crosshair over a canvas
# (tests/os4/ui_pointer_show) on BB_GUEST (m1b, m1c or local; never m1). One lock session; the
# program ends by itself after 12 s and is Ctrl-C'd (and reported if stuck) otherwise.
cd "$(dirname "$0")/.." || exit 2
out=${1:-/tmp/pointer.png}
timeout ${BB_WAIT:-3600} python3 - "$out" <<'PY'
import sys, time
sys.path.insert(0, "tools")
import os4guest
m = os4guest.MCP(os4guest.URL)
with os4guest.testing("Boing pointer screenshot"):
    m.tool("amiga_dos_command", command="makedir RAM:bbtest")
    os4guest.push(m, "build/os4/tests/ui_pointer_show", "RAM:bbtest/ui_pointer_show")
    m.tool("amiga_dos_command", command="run >NIL: RAM:bbtest/ui_pointer_show 12 >RAM:bbtest/ptr.out *>RAM:bbtest/ptr.err")
    for i in range(10):
        time.sleep(1.5)
        if "pointer over" in m.tool("amiga_dos_command", command="type RAM:bbtest/ptr.out"):
            break
    time.sleep(1.5)
    os4guest.shot(m, sys.argv[1])
    st = ""
    for i in range(15):
        time.sleep(2)
        st = m.tool("amiga_dos_command", command="status")
        if "ui_pointer_show" not in st:
            break
    print(m.tool("amiga_dos_command", command="type RAM:bbtest/ptr.out"))
    print(m.tool("amiga_dos_command", command="type RAM:bbtest/ptr.err"))
    for line in st.splitlines():
        if "ui_pointer_show" in line:
            cli = line.split()[1].rstrip(":")
            print("still running (CLI %s): Ctrl-C" % cli)
            m.tool("amiga_dos_command", command="break %s C" % cli)
            time.sleep(4)
            if "ui_pointer_show" in m.tool("amiga_dos_command", command="status"):
                print("STUCK after Ctrl-C: the guest needs a restart")
    print("reapers:", m.tool("amiga_dos_command", command="status").count("GrimReaper"))
    m.tool("amiga_dos_command", command="delete RAM:bbtest ALL QUIET")
PY

#!/usr/bin/env python3
"""os4shot.py FORM.afg OUT.png [--full] - show a form on the AmigaOS 4 QEMU guest with
build/os4/tests/form_show and save a screenshot of its window (QEMU's HMP screendump on the
selected guest (BB_GUEST, os4guest.shot); the bridge's screenshot garbles on OS4). Holds the emulator lock/banner.

    tools/os4shot.py examples/calculator/calc.afg docs/images/calculator.png
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import os4guest  # noqa: E402

def hmp(cmd):
    """the selected guest's QEMU monitor (os4guest.hmp: BB_GUEST's own port)"""
    return os4guest.hmp(cmd)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    full = "--full" in sys.argv
    if len(args) != 2:
        print(__doc__)
        return 2
    afg, out = args
    tool = os.path.join(HERE, "..", "build", "os4", "tests", "form_show")
    m = os4guest.MCP(os4guest.URL)
    with os4guest.testing("Boing BASIC screenshot"):
        m.tool("amiga_dos_command", command="makedir RAM:bbtest")
        m.tool("amiga_dos_command", command="delete RAM:bbtest/box QUIET")
        os4guest.push(m, tool, "RAM:bbtest/form_show")
        os4guest.push(m, afg, "RAM:bbtest/shot.afg")
        m.tool("amiga_dos_command", command="run >RAM:bbtest/shot.out RAM:bbtest/form_show RAM:bbtest/shot.afg 15")
        time.sleep(5)
        box = m.tool("amiga_dos_command", command="type RAM:bbtest/box")
        mm = re.search(r"box (\d+) (\d+) (\d+) (\d+)", box)
        # the selected guest's own monitor (os4guest.shot: BB_GUEST's port, wakes the blanker)
        ppm = os4guest.shot(m, tempfile.mktemp(suffix=".png"))
    from PIL import Image
    im = Image.open(ppm)
    if mm and not full:
        x, y, w, h = map(int, mm.groups())
        pad = 4
        im = im.crop((max(0, x - pad), max(0, y - pad), min(im.width, x + w + pad), min(im.height, y + h + pad)))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    im.save(out)
    os.unlink(ppm)
    print("saved", out, im.size, "box" if mm else "(no box: full screen)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

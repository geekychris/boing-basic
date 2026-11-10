#!/usr/bin/env python3
"""book-guest.py [PATTERN ...] - run the manual's window programs on an AmigaOS 4 guest.

Every project under examples/book/ whose Startup is a form (or matching PATTERN) is started
on the guest (BB_GUEST=local or m1b; never m1) with tools/gallery_shot.py's machinery: one
lock ticket each, `stack 1048576`, the program left running SECS seconds (BOOK_SECS, default
8), a screenshot of its window to build/book-shots/<path>.png, then Ctrl-C. Reports the
program's error output, processes left behind and Grim Reapers. Exit 1 if any program failed.
"""
import fnmatch
import glob
import os
import sys

os.environ.setdefault("BB_GUEST", "local")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gallery_shot as gs  # noqa: E402

ROOT = gs.ROOT


def main():
    pats = sys.argv[1:]
    secs = float(os.environ.get("BOOK_SECS", "8"))
    projs = []
    for p in sorted(glob.glob(os.path.join(ROOT, "examples", "book", "**", "*.bbp"), recursive=True)):
        rel = os.path.relpath(p, ROOT)
        txt = open(p, encoding="latin-1").read()
        if pats:
            if not any(fnmatch.fnmatch(rel, "*" + x + "*") for x in pats):
                continue
        elif "Startup=Form" not in txt.replace(" ", ""):
            continue
        projs.append(p)
    rc = 0
    for p in projs:
        d = os.path.dirname(p)
        rel = os.path.relpath(p, ROOT)
        out = os.path.join(ROOT, "build", "book-shots", rel.replace("/", "_")[:-4] + ".png")
        shot = {"file": os.path.relpath(out, d), "run": {"project": os.path.basename(p), "secs": secs,
                                                           "quantize": False}}
        print("==", rel, flush=True)
        try:
            rc |= gs.shoot(d, shot, False)
        except Exception as e:      # keep going: one broken program shouldn't stop the batch
            print("ERROR", rel, e, flush=True)
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""make_art.py - the game's pictures, from the C original's (amiga_mcp's
examples/boing_pinball, `make art` there):

  art/playfield_<table>.png   the painted playfield, 572 x 968, already squashed into the view
  art/title_<table>.png       the title's backglass with the logo, 640 x 512
  art/boing_pinball.mod       the music

(the Canvas's LoadImage reads PNG itself on every platform).

  python3 tools/make_art.py [--from AMIGA_MCP/examples/boing_pinball]
"""
import argparse, os, shutil, struct
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
ap = argparse.ArgumentParser()
ap.add_argument("--from", dest="src", default=os.path.join(root, "..", "..", "..", "amiga_mcp", "examples", "boing_pinball"))
a = ap.parse_args()
art = os.path.join(root, "art")
os.makedirs(art, exist_ok=True)

def read_img(path):
    with open(path, "rb") as f:
        d = f.read()
    assert d[:4] == b"A3IM", path
    w, h = struct.unpack(">HH", d[4:8])
    return Image.frombytes("RGB", (w, h), d[8:8 + w * h * 3])

for t in ("comet", "deep", "foundry"):
    for kind in ("playfield", "title"):
        src = os.path.join(a.src, "%s_%s.img" % (kind, t))
        png = os.path.join(art, "%s_%s.png" % (kind, t))
        if os.path.exists(src):
            read_img(src).save(png, optimize=True)
mod = os.path.join(a.src, "boing_pinball.mod")
if os.path.exists(mod):
    shutil.copy(mod, os.path.join(art, "boing_pinball.mod"))
print("art:", " ".join(sorted(os.listdir(art))))

#!/usr/bin/env python3
"""make_art.py - the game's pictures, from the C original's (amiga_mcp's
examples/boing_pinball, `make art` there):

  art/playfield_<table>.png   the painted playfield, 572 x 968, already squashed into the view
  art/title_<table>.png       the title's backglass with the logo, 640 x 512
  art/boing_pinball.mod       the music

and, with --ppm, the same pictures as binary PPM (art/*.ppm, not in git) for the
Mac, where the Canvas's LoadImage reads PPM only.

  python3 tools/make_art.py [--from AMIGA_MCP/examples/boing_pinball] [--ppm]
"""
import argparse, os, shutil, struct
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
ap = argparse.ArgumentParser()
ap.add_argument("--from", dest="src", default=os.path.join(root, "..", "..", "..", "amiga_mcp", "examples", "boing_pinball"))
ap.add_argument("--ppm", action="store_true")
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
        if a.ppm and os.path.exists(png):
            Image.open(png).convert("RGB").save(os.path.join(art, "%s_%s.ppm" % (kind, t)))
mod = os.path.join(a.src, "boing_pinball.mod")
if os.path.exists(mod):
    shutil.copy(mod, os.path.join(art, "boing_pinball.mod"))
print("art:", " ".join(sorted(os.listdir(art))))

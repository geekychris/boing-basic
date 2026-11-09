#!/usr/bin/env python3
"""make_assets.py - ScAIry Fun's data files from amiga_mcp's examples/scairy_fun:
   sc_title.ppm    the painted title (assets/title_source.png), 320 x 256
   sc_horizon.ppm  the painted dusk all the way round (assets/horizon.png): 2 pi FOV = 1131
                   pixels across, its top rows faded (the Makefile's make_image.py settings
                   at half the size)
   sc_voice_NN.raw the AI's 19 lines (scairy.voc), signed 8-bit at 11025 Hz
   scairy.mod      the music
    make_assets.py [AMIGA_MCP_EXAMPLES_SCAIRY_FUN]"""
import os, shutil, struct, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..")
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "../../../../amiga_mcp/examples/scairy_fun")

im = Image.open(os.path.join(SRC, "assets/title_source.png")).convert("RGB")
w, h = im.size
a = 320 / 256
if w / h > a:
    nw = int(h * a); im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
else:
    nh = int(w / a); im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
im.resize((320, 256), Image.LANCZOS).save(os.path.join(OUT, "sc_title.ppm"))

im = Image.open(os.path.join(SRC, "assets/horizon.png")).convert("RGB")
w, h = im.size
im = im.crop((0, 0, w, int(h * 0.78)))
W = 1131
H = int(im.size[1] * W / w * 0.5)
im = im.resize((W, H), Image.LANCZOS)
if H > 144:
    im = im.crop((0, H - 144, W, H))
H = im.size[1]
px = im.load()
top = [px[x, 0] for x in range(W)]
for y in range(24):                       # the top rows faded into the top row's colour
    f = y / 24
    for x in range(W):
        c = px[x, y]
        px[x, y] = tuple(int(top[x][i] * (1 - f) + c[i] * f) for i in range(3))
im.save(os.path.join(OUT, "sc_horizon.ppm"))

d = open(os.path.join(SRC, "scairy.voc"), "rb").read()
n = struct.unpack(">H", d[4:6])[0]
for i in range(1, n):
    o, l = struct.unpack(">II", d[8 + i * 8:16 + i * 8])
    open(os.path.join(OUT, "sc_voice_%02d.raw" % i), "wb").write(d[o:o + (l & ~1)])
shutil.copy(os.path.join(SRC, "scairy.mod"), os.path.join(OUT, "scairy.mod"))
print("ok", W, H, n - 1, "clips")

#!/usr/bin/env python3
"""montage.py OUT.png COLS IN1.png IN2.png ... [--crop X,Y,W,H] [--scale F]
Crops each screenshot (e.g. to the game's window), scales it and lays them out in a grid."""
import sys
from PIL import Image
args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
out, cols, ins = args[0], int(args[1]), args[2:]
ims = [Image.open(p).convert("RGB") for p in ins]
if "crop" in opts:
    x, y, w, h = map(int, opts["crop"].split(","))
    ims = [im.crop((x, y, x + w, y + h)) for im in ims]
if "scale" in opts:
    f = float(opts["scale"])
    ims = [im.resize((int(im.width * f), int(im.height * f)), Image.LANCZOS) for im in ims]
w, h, gap = ims[0].width, ims[0].height, 6
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w + (cols - 1) * gap, rows * h + (rows - 1) * gap), (24, 24, 24))
for i, im in enumerate(ims):
    sheet.paste(im, ((i % cols) * (w + gap), (i // cols) * (h + gap)))
sheet.save(out, optimize=True)
print(out, sheet.size)

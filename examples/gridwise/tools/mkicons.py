#!/usr/bin/env python3
"""Icons of the office apps, drawn here and written in the AmigaOS 4 icon format with
Riffwright's writer (examples/riffwright/tools/mkicons.py: a DiskObject plus a FORM ICON
with 32-bit ARGB images):

    gridwise/icons/Gridwise.info, gridwise/icons/def_gws.info  (sheets open in Gridwise)
    penwright/icons/Penwright.info, penwright/icons/def_pwd.info (documents open in Penwright)

    examples/gridwise/tools/mkicons.py        (needs Pillow)
"""
import math, os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
EX = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(EX, "riffwright", "tools"))
import mkicons as rw  # noqa: E402

S = rw.S


def brighten(im):
    px = im.load()
    for y in range(S):
        for x in range(S):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (min(255, r + 45), min(255, g + 35), min(255, b + 25), a)
    return im


def sheet(selected, doc=False):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if doc:
        d.polygon([(10, 4), (42, 4), (54, 16), (54, 60), (10, 60)], fill=(244, 246, 250, 255), outline=(52, 64, 92, 255))
        d.polygon([(42, 4), (42, 16), (54, 16)], fill=(190, 196, 210, 255), outline=(52, 64, 92, 255))
        x0, y0, x1, y1 = 14, 20, 50, 56
    else:
        d.rounded_rectangle((4, 6, 59, 57), 6, fill=(250, 251, 253, 255), outline=(28, 84, 196, 255), width=2)
        d.rectangle((6, 8, 57, 15), fill=(210, 222, 244, 255))
        d.rectangle((6, 8, 13, 55), fill=(210, 222, 244, 255))
        x0, y0, x1, y1 = 6, 8, 57, 55
    for x in range(x0 + 8, x1, 11):
        d.line([(x, y0), (x, y1)], fill=(176, 190, 214, 255))
    for y in range(y0 + 7, y1, 7):
        d.line([(x0, y), (x1, y)], fill=(176, 190, 214, 255))
    # a little bar chart in front
    cols = [(52, 101, 164, 255), (230, 120, 30, 255), (78, 154, 6, 255)]
    base = y1 - 3
    for i, h in enumerate((16, 26, 20) if not doc else (10, 18, 14)):
        bx = x0 + 14 + i * 10
        d.rectangle((bx, base - h, bx + 7, base), fill=cols[i], outline=(30, 40, 60, 255))
    return brighten(im) if selected else im


def quill(selected, doc=False):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # a page with lines of text
    d.polygon([(8, 6), (40, 6), (52, 18), (52, 60), (8, 60)], fill=(252, 250, 244, 255), outline=(70, 60, 50, 255))
    d.polygon([(40, 6), (40, 18), (52, 18)], fill=(214, 206, 190, 255), outline=(70, 60, 50, 255))
    d.rectangle((13, 13, 30, 16), fill=(28, 84, 196, 255))                 # a heading
    for i, y in enumerate(range(23, 56, 5)):
        d.rectangle((13, y, 13 + 30 - (i * 7) % 13, y + 1), fill=(60, 60, 70, 255))
    if not doc:
        # a nib, diagonally across the page
        nib = [(58, 4), (62, 8), (30, 44), (24, 48), (26, 42)]
        d.polygon(nib, fill=(178, 34, 34, 255), outline=(80, 10, 10, 255))
        d.line([(57, 7), (29, 43)], fill=(250, 210, 120, 255), width=1)
        d.polygon([(24, 48), (26, 42), (30, 44)], fill=(40, 40, 40, 255))
    return brighten(im) if selected else im


def main():
    g = os.path.join(EX, "gridwise", "icons")
    p = os.path.join(EX, "penwright", "icons")
    os.makedirs(g, exist_ok=True)
    os.makedirs(p, exist_ok=True)
    open(os.path.join(g, "Gridwise.info"), "wb").write(rw.disk_object(3, sheet(False), sheet(True), None, ("DONOTWAIT",), 262144))
    open(os.path.join(g, "def_gws.info"), "wb").write(rw.disk_object(4, sheet(False, True), sheet(True, True), "Gridwise"))
    open(os.path.join(p, "Penwright.info"), "wb").write(rw.disk_object(3, quill(False), quill(True), None, ("DONOTWAIT",), 262144))
    open(os.path.join(p, "def_pwd.info"), "wb").write(rw.disk_object(4, quill(False, True), quill(True, True), "Penwright"))
    for name, fn in (("gridwise", sheet), ("penwright", quill)):
        strip = Image.new("RGBA", (S * 4 + 24, S * 2), (180, 186, 200, 255))
        strip.paste(fn(False).resize((S * 2, S * 2), Image.NEAREST), (0, 0), fn(False).resize((S * 2, S * 2), Image.NEAREST))
        dd = fn(False, True).resize((S * 2, S * 2), Image.NEAREST)
        strip.paste(dd, (S * 2 + 24, 0), dd)
        strip.save(os.path.join(EX, name, "docs", "icons.png"))
    print("icons written")


if __name__ == "__main__":
    main()

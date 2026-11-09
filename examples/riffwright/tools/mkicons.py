#!/usr/bin/env python3
"""Riffwright's icons: Riffwright.info (the program) and def_mod.info (a project icon for
.mod files that opens them in Riffwright), drawn here and written in the AmigaOS 4 icon
format: a classic DiskObject (with a small planar image for old systems) followed by a
FORM ICON with a FACE chunk and two zlib-packed 32-bit ARGB images (normal, selected), the
layout of the SDK's own icons.

    tools/mkicons.py [OUTDIR]      (needs Pillow)
"""
import os, struct, sys, zlib
from PIL import Image, ImageDraw

S = 64


def chunk(tag, body):
    return tag + struct.pack(">I", len(body)) + body + (b"\0" if len(body) % 2 else b"")


def argb_chunk(img):
    raw = bytearray()
    for y in range(S):
        for x in range(S):
            r, g, b, a = img.getpixel((x, y))
            raw += bytes([a, r, g, b])
    z = zlib.compress(bytes(raw), 9)
    # header as in the SDK's icons: 1 (format), packed size - 1, 0
    return chunk(b"ARGB", struct.pack(">IIH", 1, len(z) - 1, 0) + z)


def planar(img, w=32, h=16):
    """a 2-plane, 32x16 classic image from the picture (dark = colour 1, light = colour 2)"""
    small = img.resize((w, h)).convert("RGBA")
    planes = [bytearray(), bytearray()]
    for y in range(h):
        for wx in range(0, w, 16):
            b0 = b1 = 0
            for x in range(wx, wx + 16):
                r, g, b, a = small.getpixel((x, y))
                c = 0 if a < 128 else (2 if (r + g + b) > 380 else 1)
                b0 = (b0 << 1) | (c & 1)
                b1 = (b1 << 1) | (c >> 1)
            planes[0] += struct.pack(">H", b0)
            planes[1] += struct.pack(">H", b1)
    return bytes(planes[0] + planes[1])


def disk_object(kind, img, sel, deftool=None, tooltypes=(), stack=0):
    w, h = 32, 16
    data = planar(img, w, h)
    gad = struct.pack(">IhhHHHHHIIIIIHI",
                      0, 0, 0, w, h + 1,
                      0x0006,          # GFLG_GADGIMAGE | GFLG_GADGHIMAGE (selected = second image)
                      0x0001,          # RELVERIFY
                      0x0001,          # BOOLGADGET
                      1, 1, 0, 0, 0, 0, 1)   # render, select render present; UserData = revision 1
    do = struct.pack(">HH", 0xE310, 1) + gad
    do += struct.pack(">BB", kind, 0)
    do += struct.pack(">IIiiIII", 1 if deftool else 0, 1 if tooltypes else 0,
                      -2147483648, -2147483648, 0, 0, stack)   # NO_ICON_POSITION
    assert len(do) == 78, len(do)
    image = struct.pack(">hhhhhIBBI", 0, 0, w, h, 2, 1, 3, 0, 0)
    out = do + image + data + image + planar(sel, w, h)
    if deftool:
        s = deftool.encode("latin-1") + b"\0"
        out += struct.pack(">I", len(s)) + s
    if tooltypes:
        out += struct.pack(">I", (len(tooltypes) + 1) * 4)
        for t in tooltypes:
            s = t.encode("latin-1") + b"\0"
            out += struct.pack(">I", len(s)) + s
    face = chunk(b"FACE", struct.pack(">BBBBH", S - 1, S - 1, 2, 0, 1))   # frameless
    form = b"ICON" + face + argb_chunk(img) + argb_chunk(sel)
    return out + b"FORM" + struct.pack(">I", len(form)) + form


def program_picture(selected):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # a dark rounded panel with pattern rows and a glowing waveform
    d.rounded_rectangle((4, 6, 59, 57), 8, fill=(18, 24, 40, 255), outline=(255, 176, 64, 255), width=2)
    for i, y in enumerate(range(14, 52, 6)):
        col = (60, 72, 104, 255) if i % 2 else (44, 54, 84, 255)
        d.rectangle((10, y, 53, y + 2), fill=col)
        d.rectangle((10, y, 10 + (i * 7) % 20 + 6, y + 2), fill=(232, 238, 248, 255))
        d.rectangle((34, y, 34 + (i * 5) % 9 + 3, y + 2), fill=(255, 190, 96, 255))
    pts = []
    import math
    for x in range(8, 57):
        pts.append((x, 32 - 14 * math.sin((x - 8) / 48 * 2 * math.pi * 2) * math.exp(-(x - 8) / 60)))
    d.line(pts, fill=(110, 214, 224, 255), width=3)
    if selected:
        px = im.load()
        for y in range(S):
            for x in range(S):
                r, g, b, a = px[x, y]
                if a:
                    px[x, y] = (min(255, r + 50), min(255, g + 40), min(255, b + 20), a)
    return im


def mod_picture(selected):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # a page with a folded corner, notes and a small waveform
    page = (226, 230, 238, 255) if not selected else (255, 236, 200, 255)
    d.polygon([(12, 4), (42, 4), (54, 16), (54, 60), (12, 60)], fill=page, outline=(60, 70, 96, 255))
    d.polygon([(42, 4), (42, 16), (54, 16)], fill=(180, 186, 200, 255), outline=(60, 70, 96, 255))
    for i, y in enumerate(range(22, 54, 6)):
        d.rectangle((17, y, 17 + 8 + (i * 5) % 12, y + 2), fill=(24, 30, 52, 255))
        d.rectangle((36, y, 36 + (i * 3) % 8 + 4, y + 2), fill=(214, 120, 30, 255))
    d.ellipse((30, 6, 38, 13), fill=(214, 120, 30, 255))
    d.line([(37, 9), (37, 0)], fill=(214, 120, 30, 255), width=2)
    return im


def main(out):
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "Riffwright.info"), "wb").write(
        disk_object(3, program_picture(False), program_picture(True), None, ("DONOTWAIT",), 524288))
    open(os.path.join(out, "def_mod.info"), "wb").write(
        disk_object(4, mod_picture(False), mod_picture(True), "Riffwright"))
    program_picture(False).resize((128, 128), Image.NEAREST).save(os.path.join(out, "..", "docs", "icon_program.png")) \
        if os.path.isdir(os.path.join(out, "..", "docs")) else None


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons"))

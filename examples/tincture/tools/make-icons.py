#!/usr/bin/env python3
"""make-icons.py [outdir] -- Tincture's Workbench icons (default: the example's Icons/ drawer).

Classic DiskObjects with a 4-colour planar fallback image and an OS4 FORM ICON (FACE + two
zlib-compressed ARGB images, normal and selected), the format AmiForge's tools/make-icons.py
writes. Drawn with Pillow at 4x and downsampled.

  Tincture.info        the program (tool icon)
  Tincture.guide.info  the help file (default tool MultiView)
  picture.info         template for saved pictures (default tool Tincture, beside it)
  drawer.info          the Tincture drawer
"""
import math
import os
import struct
import sys
import zlib

from PIL import Image, ImageDraw, ImageFilter

SIZE = 64
SS = 4


def canvas():
    return Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))


def finish(img):
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def P(*pts):
    return [(x * SS, y * SS) for x, y in pts]


def draw_palette_board(d, ox=0, oy=0, scale=1.0):
    """An artist's palette: a rounded board with a thumb hole and five paint blobs."""
    def t(x, y):
        return (ox + x * scale, oy + y * scale)
    box = [t(6, 14), t(58, 54)]
    d.ellipse(P(*box), fill=(206, 168, 112, 255), outline=(92, 62, 30, 255), width=int(1.6 * SS))
    hx, hy = t(20, 42)
    r = 4.2 * scale
    d.ellipse(P((hx - r, hy - r), (hx + r, hy + r)), fill=(0, 0, 0, 0), outline=(92, 62, 30, 255), width=int(1.2 * SS))
    blobs = [((18, 24), (230, 40, 40)), ((30, 20), (250, 196, 0)), ((43, 22), (40, 170, 70)),
             ((50, 33), (40, 110, 230)), ((44, 44), (170, 60, 200))]
    for (bx, by), col in blobs:
        cx, cy = t(bx, by)
        rr = 4.6 * scale
        d.ellipse(P((cx - rr, cy - rr), (cx + rr, cy + rr)), fill=col + (255,), outline=(40, 30, 20, 255), width=SS)
        d.ellipse(P((cx - rr * 0.45, cy - rr * 0.6), (cx - rr * 0.05, cy - rr * 0.2)), fill=(255, 255, 255, 200))


def draw_brush(d, x0, y0, x1, y1, tip=(40, 110, 230)):
    """A paint brush from (x0, y0) (handle end) to (x1, y1) (tip)."""
    ang = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(ang), math.cos(ang)
    def quad(a, b, wa, wb, col):
        ax, ay = x0 + (x1 - x0) * a, y0 + (y1 - y0) * a
        bx, by = x0 + (x1 - x0) * b, y0 + (y1 - y0) * b
        pts = [(ax + nx * wa, ay + ny * wa), (bx + nx * wb, by + ny * wb), (bx - nx * wb, by - ny * wb), (ax - nx * wa, ay - ny * wa)]
        d.polygon(P(*pts), fill=col, outline=(30, 24, 20, 255))
    quad(0.0, 0.55, 2.4, 2.0, (150, 40, 30, 255))     # handle
    quad(0.55, 0.72, 2.6, 2.6, (200, 200, 210, 255))  # ferrule
    quad(0.72, 1.0, 2.8, 0.6, tip + (255,))           # bristles


def icon_tool():
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_palette_board(d)
    draw_brush(d, 56, 4, 30, 40)
    return finish(img)


def icon_picture():
    img = canvas()
    d = ImageDraw.Draw(img)
    # a framed landscape
    d.rectangle(P((8, 10), (56, 54)), fill=(250, 246, 236, 255), outline=(60, 50, 40, 255), width=int(2 * SS))
    d.rectangle(P((12, 14), (52, 50)), fill=(120, 180, 240, 255))
    d.ellipse(P((36, 18), (46, 28)), fill=(255, 200, 40, 255))
    d.polygon(P((12, 50), (24, 30), (34, 44), (40, 36), (52, 50)), fill=(50, 140, 70, 255))
    draw_brush(d, 60, 30, 44, 54, tip=(230, 60, 40))
    return finish(img)


def icon_doc():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.polygon(P((14, 6), (42, 6), (52, 16), (52, 58), (14, 58)), fill=(250, 250, 248, 255), outline=(70, 80, 95, 255))
    d.polygon(P((42, 6), (42, 16), (52, 16)), fill=(210, 214, 222, 255), outline=(70, 80, 95, 255))
    for i in range(7):
        y = 22 + i * 5
        d.line(P((19, y), (19 + (28, 30, 22, 30, 26, 30, 18)[i], y)), fill=(110, 122, 140, 255), width=int(1.4 * SS))
    d.ellipse(P((30, 36), (50, 56)), fill=(255, 176, 0, 255), outline=(90, 60, 0, 255), width=SS)
    # a question mark: an arc, a stem and a dot
    d.arc(P((35.5, 39), (44.5, 47.5)), start=180, end=410, fill=(40, 30, 0, 255), width=int(2.2 * SS))
    d.line(P((40, 47), (40, 50)), fill=(40, 30, 0, 255), width=int(2.2 * SS))
    d.ellipse(P((38.7, 51.2), (41.3, 53.8)), fill=(40, 30, 0, 255))
    return finish(img)


def icon_drawer():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.rectangle(P((6, 20), (58, 56)), fill=(90, 96, 110, 255), outline=(30, 32, 40, 255), width=int(1.6 * SS))
    d.rectangle(P((6, 14), (28, 22)), fill=(90, 96, 110, 255), outline=(30, 32, 40, 255), width=int(1.6 * SS))
    draw_palette_board(d, 10, 14, 0.75)
    return finish(img)


def selected(img):
    """The selected image: darker, with a blue glow behind (OS4 style)."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    halo = img.split()[3].filter(ImageFilter.GaussianBlur(3)).point(lambda v: min(255, v * 2))
    glow.paste((90, 150, 255, 255), mask=halo)
    dark = img.copy()
    px = dark.load()
    for y in range(dark.size[1]):
        for x in range(dark.size[0]):
            r, g, b, a = px[x, y]
            px[x, y] = (r * 3 // 4, g * 3 // 4, b * 3 // 4 + 30 if a else 0, a)
    return Image.alpha_composite(glow, dark)


# --- icon file format ---------------------------------------------------------------------

WBDISK, WBDRAWER, WBTOOL, WBPROJECT = 1, 2, 3, 4
NO_ICON_POSITION = 0x80000000
PALETTE = [(170, 170, 170), (0, 0, 0), (255, 255, 255), (102, 136, 187)]   # Workbench pens 0-3


def planar(img):
    """A 2-bitplane image for old icon.library versions: nearest Workbench pen per pixel."""
    w, h = img.size
    row_bytes = (w + 15) // 16 * 2
    planes = [bytearray(row_bytes * h) for _ in range(2)]
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                pen = 0
            else:
                pen = min(range(1, 4), key=lambda p: sum((c - q) ** 2 for c, q in zip((r, g, b), PALETTE[p])))
            for p in range(2):
                if pen >> p & 1:
                    planes[p][y * row_bytes + x // 8] |= 0x80 >> (x % 8)
    header = struct.pack(">hhhhhIBBI", 0, 0, w, h, 2, 1, 3, 0, 0)   # struct Image
    return header + bytes(planes[0]) + bytes(planes[1])


def text_block(t):
    data = t.encode("latin-1") + b"\0"
    return struct.pack(">I", len(data)) + data


def argb_chunk(img):
    rgba = img.tobytes()
    raw = bytearray(len(rgba))
    raw[0::4], raw[1::4], raw[2::4], raw[3::4] = rgba[3::4], rgba[0::4], rgba[1::4], rgba[2::4]
    packed = zlib.compress(bytes(raw), 9)
    # header as written by OS4's icon.library: 1, compressed size - 1, 0
    body = struct.pack(">IIH", 1, len(packed) - 1, 0) + packed
    return b"ARGB" + struct.pack(">I", len(body)) + body + (b"\0" if len(body) & 1 else b"")


def iff_icon(normal, sel):
    # width-1, height-1, flags, aspect, max palette bytes: the values OS4's own true-colour
    # icons carry (icon.library rejects the icon with flags 0x01 and no palette)
    face = struct.pack(">BBBBH", SIZE - 1, SIZE - 1, 0x02, 0x00, 1)
    chunks = b"FACE" + struct.pack(">I", len(face)) + face + argb_chunk(normal) + argb_chunk(sel)
    return b"FORM" + struct.pack(">I", len(chunks) + 4) + b"ICON" + chunks


def disk_object(kind, img, default_tool=None, tool_types=(), stack=0, drawer=None):
    sel = selected(img)
    gadget = struct.pack(">IhhhhHHHIIIiIHI",
                         0, 0, 0, SIZE, SIZE,
                         0x0006,      # GFLG_GADGIMAGE | GFLG_GADGHIMAGE
                         0x0001,      # GACT_RELVERIFY
                         0x0001,      # GTYP_BOOLGADGET
                         1, 1, 0, 0, 0, 0,
                         1)           # UserData: WB_DISKREVISION 1 (OS 2.x+ icon)
    obj = struct.pack(">HH", 0xE310, 1) + gadget + struct.pack(
        ">BBIIIIIII", kind, 0,
        1 if default_tool else 0, 1 if tool_types else 0,
        NO_ICON_POSITION, NO_ICON_POSITION,
        1 if drawer else 0, 0, stack)
    out = bytearray(obj)
    if drawer:
        left, top, width, height = drawer
        # OldDrawerData: struct NewWindow, then dd_CurrentX/Y
        out += struct.pack(">hhhhBBIIIIIIIhhHHH", left, top, width, height, 255, 255,
                           0, 0, 0, 0, 0, 0, 0, 90, 40, 0xFFFF, 0xFFFF, 1)
        out += struct.pack(">ii", 0, 0)
    out += planar(img) + planar(sel)
    if default_tool:
        out += text_block(default_tool)
    if tool_types:
        out += struct.pack(">I", (len(tool_types) + 1) * 4)
        for t in tool_types:
            out += text_block(t)
    if drawer:
        out += struct.pack(">IH", 1, 1)     # dd_Flags: show icons only; dd_ViewModes: by icon
    return bytes(out) + iff_icon(img, sel)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Icons")
    os.makedirs(outdir, exist_ok=True)
    icons = {
        "Tincture.info": disk_object(WBTOOL, icon_tool(), stack=262144, tool_types=("AUTOSAVE=30",)),
        "Tincture.guide.info": disk_object(WBPROJECT, icon_doc(), default_tool="SYS:Utilities/MultiView", stack=65536),
        "picture.info": disk_object(WBPROJECT, icon_picture(), default_tool="Tincture", stack=262144),
        "drawer.info": disk_object(WBDRAWER, icon_drawer(), drawer=(80, 60, 420, 220)),
    }
    for name, data in icons.items():
        with open(os.path.join(outdir, name), "wb") as f:
            f.write(data)
        print(f"{name:22s} {len(data):6d} bytes")
    # PNG previews for the README
    for name, fn in (("tool", icon_tool), ("picture", icon_picture), ("doc", icon_doc), ("drawer", icon_drawer)):
        fn().save(os.path.join(outdir, name + "-preview.png"))


if __name__ == "__main__":
    main()

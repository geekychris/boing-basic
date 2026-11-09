#!/usr/bin/env python3
"""Lander 3D's pictures for the BASIC port: the original's A3IM files (amiga_mcp
examples/lander_3d, made by its `make art` from assets/*.png) as PNG (AmigaOS 4 loads
them through datatypes) and, with --ppm, as binary PPM (the Mac's off-screen canvas
reads only PPM; for the bench's screenshots). Same pixels as the original draws.
    tools/make_art.py [--ppm] [AMIGA_MCP]"""
import os, struct, sys, zlib

def read_a3im(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'A3IM', path
    w, h = struct.unpack('>HH', data[4:8])
    return w, h, data[8:8 + w * h * 3]

def write_png(path, w, h, rgb):
    raw = b''.join(b'\0' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
                chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    here = os.path.dirname(os.path.abspath(__file__))
    mcp = args[0] if args else os.path.join(here, '..', '..', '..', '..', 'amiga_mcp')
    src = os.path.join(mcp, 'examples', 'lander_3d')
    out = os.path.join(here, '..', 'art')
    for name in ('lander_title', 'sky_moon', 'sky_mars', 'sky_asteroid'):
        w, h, rgb = read_a3im(os.path.join(src, name + '.img'))
        write_png(os.path.join(out, name + '.png'), w, h, rgb)
        if '--ppm' in sys.argv:
            with open(os.path.join(out, name + '.ppm'), 'wb') as f:
                f.write(b'P6\n%d %d\n255\n' % (w, h) + rgb)
        print(name, w, h, 'top-left', tuple(rgb[:3]))

main()

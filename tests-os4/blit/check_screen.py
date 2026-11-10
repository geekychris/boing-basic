#!/usr/bin/env python3
"""check_screen.py SHOT.png EXPECTED.png SCALE [X Y]: does the guest screenshot show the Canvas
picture (EXPECTED, saved with Canvas.SavePNG on the host) enlarged SCALE times at X,Y (default 0,0,
the top-left corner of a full-screen window)? Colours are compared at 16 bits (R5G6B5, the depth
of the test's screen); the mouse pointer's corner (16 x 16 at the top left) is skipped.
Exit 0 and "SCREEN PASS" when every pixel matches."""
import sys
from PIL import Image
shot = Image.open(sys.argv[1]).convert("RGB")
exp = Image.open(sys.argv[2]).convert("RGB")
s = int(sys.argv[3])
ox, oy = (int(sys.argv[4]), int(sys.argv[5])) if len(sys.argv) > 5 else (0, 0)
q = lambda p: (p[0] & 0xF8, p[1] & 0xFC, p[2] & 0xF8)
bad, first = 0, None
W, H = exp.size
for y in range(H * s):
    for x in range(W * s):
        if x < 16 and y < 16:
            continue
        a, b = q(shot.getpixel((ox + x, oy + y))), q(exp.getpixel((x // s, y // s)))
        if a != b:
            bad += 1
            if first is None:
                first = (x, y, a, b)
print("SCREEN PASS" if not bad else "SCREEN FAIL: %d pixels differ, first at %s (screen %s, expected %s)"
      % (bad, first[:2], first[2], first[3]))
sys.exit(1 if bad else 0)

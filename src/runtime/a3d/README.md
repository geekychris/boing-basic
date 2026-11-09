# a3d: the amiga3d engine (vendored)

From `amiga_mcp/examples/amiga3d` (github.com/geekychris/amiga_games, commit 36a238b,
2026-11-05), MIT, Copyright (c) 2026 Chris Collins. Copies of (unchanged except that
`poly_spans` in `a3d_math.c` multiplies by 65536 instead of shifting a negative value left,
which is undefined in C; same results):

- `a3d.h`, `a3d_math.c`: 16-bit angles, 16.16 trig, square roots, the camera, clipping, spans
- `a3d_fix.h`, `a3d_fix.c`: 16.16 fixed point
- `a3d_font16.h`: the 16 x 16 font (DejaVu Sans Mono Bold, Bitstream Vera licence)

The draw list, models, terrain and drawing are re-done for Boing's 32-bit Canvas buffer in
`../engine3d.c`, after amiga3d's `a3d_draw.c` (same rules). See `docs/engine3d.md`.

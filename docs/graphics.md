# Graphics: the Canvas control

A **Canvas** is a drawing surface for games, charts and anything else drawn pixel by pixel.
It is VB's PictureBox cut down to what a game needs, plus double buffering, images
(sprites), batch drawing and keyboard state.

- In a form it is the `.afg` kind `canvas`: `canvas id=view width=400 height=300`. The
  layout reserves at least that size, and the picture is centred if the layout makes it bigger.
  `scale=2` (up to 4) shows the picture 2x bigger: the program still draws 400 x 300.
- Off-screen, on every platform (the Mac too): `Set cv = CreateObject("Boing.Canvas")`, then
  `cv.Resize 400, 300`. The tests and console benchmarks use this.

```basic
Private Sub tick_Timer()               ' a 20 ms Timer on the form
    view.Cls RGB(0, 0, 32)
    view.Circle x, 100, 12, RGB(255, 200, 0), True
    view.DrawText 4, 2, "SCORE " & score, vbWhite
    view.Refresh                       ' show the frame
    If view.KeyDown(vbKeyLeft) Then x = x - 2
End Sub
```

## How it works

Everything is drawn in portable C (`src/runtime/canvas.c`) into a 32-bit chunky buffer of
the canvas size: the **back buffer**. Nothing appears in the window until `Refresh` (alias
`Flip`, `EndDraw`), which blits the back buffer into the window in one go. On AmigaOS 4 that is
one `BltBitMapTags(BLITT_ARGB32 → window RastPort)`, which converts to the screen's pixel
format and clips to the window. So drawing never flickers, and a frame costs one blit. The
canvas re-shows its last picture by itself when the window opens or is resized.

On AmigaOS 4 the default (`BlitMode` 0) converts the picture into an off-screen bitmap of the
screen's own pixel format (a "friend" bitmap: R5G6B5, R5G6B5PC, A8R8G8B8 or B8G8R8A8, written
through `LockBitMapTags`), then copies that to the window with `BltBitMapRastPort`. On the
QEMU guest's 16-bit screen this takes 0.94 ms for 400 x 300, against 2.3 ms for the 32-bit
ARGB `BltBitMapTags` blit. Other screen formats use the ARGB blit.

Drawing is the same on every platform, pixel for pixel. `Hash` returns a checksum of the
picture, so a program can be tested off-screen on the Mac (`tests/graphics/`).

Colours are VB colours, `&HBBGGRR`: what `RGB(r, g, b)` returns, and the `vbRed`, `vbWhite`...
constants. Coordinates are pixels, (0, 0) at the top left. Everything clips at the edges.

Calls are cheap: members are looked up once per call site, and the arguments are read
straight from the call's values. Still, one call per pixel is the slow way in the
interpreter. Draw many points with `PSetMany`, and pre-draw repeated shapes into images.

## Properties

| Property | Type | Notes |
|---|---|---|
| `Width`, `Height` (`ScaleWidth`, `ScaleHeight`) | Long | the picture size; settable only off-screen (or use `Resize`) |
| `ForeColor` | Long | default colour for `PSet`, `Line`, `Rect`, `Circle`, `Print`, `DrawText` (default white) |
| `FillColor` | Long | default colour for `Box` (default white) |
| `BackColor` | Long | the colour `Cls` clears to (default black) |
| `CurrentX`, `CurrentY` | Long | where `Print` writes; `PSet`, `Line` and `DrawText` move it |
| `Target` | Long | the image being drawn into, 0 = the back buffer (same as `SetTarget`) |
| `Frames` | Long, R/O | how many times `Refresh` was called |
| `Name` | String, R/O | |
| `Scale` | Long, R/O | the `.afg`'s `scale=` |
| `BlitMode` | Long | how `Refresh` gets the picture into the window (all canvases): 0 = the best the platform has (default), 1 = a 32-bit ARGB blit, 2 = converted to 16-bit first, 3 = through an off-screen bitmap in the screen's own format |
| `BlitInfo` | String, R/O | the method `Refresh` used last, e.g. `friend bitmap R5G6B5PC` |

## Methods

Optional arguments are in brackets; a missing colour means `ForeColor` (`FillColor` for `Box`).

| Method | |
|---|---|
| `Cls [colour]` | clear the target (the back buffer to `BackColor`, an image to transparent) |
| `PSet x, y [, colour]` | one pixel |
| `Line x1, y1, x2, y2 [, colour [, "B" \| "BF"]]` | a line; `"B"` a rectangle outline with those corners, `"BF"` filled (VB's `Line ... , B/BF`) |
| `Box x, y, w, h [, colour]` (`FillRect`) | a filled rectangle |
| `Rect x, y, w, h [, colour]` | a rectangle outline |
| `Circle x, y, r [, colour [, filled]]` | a circle outline, or filled when `filled` is True |
| `Polygon xs(), ys(), n [, colour [, filled]]` | a closed polygon of the first n points (up to 64) of two numeric arrays |
| `PSetMany xs(), ys(), colours, n [, size]` | n points from Long arrays; `colours` is an array or one colour; `size` > 1 draws size x size squares. Use it for particles and starfields |
| `Point(x, y)` | the colour of a pixel, -1 outside |
| `DrawText x, y, text [, colour]` | text in the built-in 6 x 9 font (Latin-1 32..126; others show as `?`) |
| `Print text` | text at CurrentX/CurrentY, then on to the next line (VB's `Picture.Print`) |
| `TextWidth(text)`, `TextHeight([text])` | the size of a text in pixels |
| `Refresh` (`Flip`, `EndDraw`) | show the back buffer in the window |
| `BeginDraw` | draw into the back buffer again (`SetTarget 0`) |
| `KeyDown(keycode)` | True while the key is held down in the canvas's form (`vbKeyLeft`, `vbKeySpace`, `vbKeyA`...) |
| `InjectKey keycode [, down]` | set a key's state, for tests and demos |
| `Hash` | a checksum of the target's pixels |
| `Resize w, h` | change the picture size (clears it to `BackColor`) |

### Images (sprites)

Images are pictures held by the canvas, numbered from 1. A new image is transparent, and
drawing into one makes those pixels opaque. `DrawImage` copies only the opaque pixels, so an
image works as a sprite.

| Method | |
|---|---|
| `CreateImage(w, h)` | a new transparent image; returns its number |
| `LoadImage(path)` | a picture file: IFF, PNG, JPEG, ... (datatypes) on AmigaOS 4, binary PPM (`P6`) everywhere; returns its number. Error 53 if the file is missing, 481 if it isn't a picture |
| `SetTarget id` | draw into image id from now on (0 = the back buffer) |
| `DrawImage id, x, y [, opaque]` | copy the image to (x, y) of the target, skipping transparent pixels unless `opaque` |
| `DrawImagePart id, sx, sy, w, h, x, y [, opaque]` | copy a part (sprite sheets, tiles) |
| `ImageWidth(id)`, `ImageHeight(id)` | |
| `FreeImage id` | |
| `SaveImage path [, id]` | write the back buffer (or an image) as a binary PPM (screenshots, tests) |

## Example: a sprite

```basic
Dim ship As Long
ship = view.CreateImage(16, 16)
view.SetTarget ship
view.Polygon xs, ys, 3, vbWhite, True       ' draw once into the image
view.SetTarget 0
...
view.DrawImage ship, px - 8, py - 8          ' each frame
```

## Performance

The Glimmerfield game (`examples/glimmerfield`) draws about 60 polygons, 300 particles, text
and circles per frame through a Canvas. Its timings are in
[performance.md](performance.md#game-benchmark).

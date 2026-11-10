# Graphics: the Canvas

This chapter is about the Canvas, Boing BASIC's drawing surface for games, charts, paint
programs and anything else you draw pixel by pixel. It covers a canvas in a form and a canvas
off-screen, every drawing method, colours and see-through drawing, text, images and sprites,
the paint helpers, keyboard and mouse input, and how to build a game loop with a Timer that
runs smoothly on AmigaOS 4.

## Two kinds of canvas

A canvas is always a picture in memory that you draw into. There are two ways to get one.

**In a form.** A `canvas` line in the form's `.afg` layout puts a canvas control in the
window. Its `id` becomes a variable in the form's code:

```text
canvas id=view width=320 height=200
```

**Off-screen.** `CreateObject("Boing.Canvas")` makes a canvas with no window. It is 320 x 200
until you call `Resize`. Off-screen canvases work everywhere, also on the host computer you
cross-develop on, so you can draw pictures in a console program, save them as PNG or IFF
files, and test drawing code without opening a window.

Declare the variable `As Canvas` (or `As Boing.Canvas`), or `As Object`:

*Listing 14.1* (`examples/book/ch14-graphics/listing-14-01.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim cv As Canvas
    Set cv = CreateObject("Boing.Canvas")
    Print "new canvas:"; cv.Width; "x"; cv.Height
    cv.Resize 160, 100
    cv.Cls RGB(0, 0, 64)
    cv.Box 10, 10, 40, 30, vbRed
    cv.Circle 100, 50, 20, vbYellow, True
    cv.Line 0, 99, 159, 0, vbWhite
    cv.DrawText 4, 88, "HELLO", vbGreen
    Print "pixel in the box: &H"; Hex$(cv.Point(20, 20))
    Print "pixel in the disc: &H"; Hex$(cv.Point(100, 50))
    Print "outside:"; cv.Point(200, 0)
    Print "hash:"; cv.Hash
End Sub
```

```output
new canvas: 320 x 200 
pixel in the box: &HFF
pixel in the disc: &HFFFF
outside:-1 
hash: 1752801191 
```

`Dim cv As New Canvas` is not allowed: always use `CreateObject`. `TypeName(cv)` is
`"Canvas"`.

Note: with `As Engine3D` and `As Audio`, `boing check` reports a misspelt member name when it
compiles. A Canvas cannot do that, because names it does not know are passed on to the form
control it sits in (see "Control properties" below). A misspelt Canvas member shows up as
run-time error 438 ("Object doesn't support this property or method").

## How drawing works

Everything you draw goes into the canvas's **back buffer**, a 32-bit picture the size of
the canvas. Nothing appears in the window until you call `Refresh`, which copies the whole
back buffer into the window in one go. So you draw a complete frame, call `Refresh`, and the
viewer never sees a half-drawn picture: drawing never flickers, and you don't need to manage
double buffering yourself. On an off-screen canvas `Refresh` only counts the frame (see
`Frames`).

When the window opens, or is uncovered or resized, the canvas shows its last picture again
by itself.

- **Coordinates** are pixels, with (0, 0) at the top left. Everything is clipped at the
  edges, so drawing partly or wholly outside the canvas is safe.
- **Colours** are Long values made with `RGB(red, green, blue)` (each 0..255), or the
  constants `vbBlack`, `vbWhite`, `vbRed`, `vbGreen`, `vbBlue`, `vbYellow`, `vbCyan` and
  `vbMagenta`. In hex a colour is `&HBBGGRR` (blue in the high byte). `Point` returns colours
  in the same form.
- **Default colours**: a drawing method called without a colour uses `ForeColor` (white at
  first); `Box` uses `FillColor` (white). `Cls` with no colour clears to `BackColor` (black).

The picture is drawn the same, pixel for pixel, on every platform. `Hash` returns a checksum
of the picture, which makes drawing code easy to test: run it off-screen and compare the
hash with a known value.

## Drawing methods

Optional arguments are in brackets. `colour` defaults to `ForeColor` (`FillColor` for
`Box`).

| Method | What it does |
|---|---|
| `Cls [colour]` | clear the picture (to `BackColor`, or to `colour`); also sets `CurrentX` and `CurrentY` to 0 |
| `PSet x, y [, colour]` | one pixel |
| `Line x1, y1, x2, y2 [, colour [, "B" \| "BF"]]` | a line; with `"B"` a rectangle outline with those two corners, with `"BF"` a filled rectangle |
| `Box x, y, w, h [, colour]` | a filled rectangle w x h with its top left at (x, y). `FillRect` is the same |
| `Rect x, y, w, h [, colour]` | a rectangle outline |
| `Circle x, y, r [, colour [, filled]]` | a circle of radius r round (x, y); filled when `filled` is True |
| `Ellipse cx, cy, rx, ry [, colour [, filled]]` | an ellipse with radii rx and ry |
| `Polygon xs(), ys(), n [, colour [, filled]]` | a closed polygon through the first n points (2..64) of two numeric arrays |
| `PSetMany xs(), ys(), colours, n [, size]` | n points at once; `colours` is an array or one colour; `size` > 1 draws size x size squares |
| `Point(x, y)` | the colour of a pixel, -1 outside the picture |
| `Gradient x, y, w, h, topLeft, topRight [, bottomLeft, bottomRight]` | a rectangle shaded between corner colours |
| `LinearGradient x, y, w, h, x1, y1, x2, y2, colour1, colour2 [, dither]` | a rectangle shaded along the line (x1, y1)-(x2, y2); dithered unless `dither` is False |
| `Checker x, y, w, h, size, colour1, colour2` | a checkerboard of size x size squares |
| `DashRect x, y, w, h, colour1, colour2 [, phase]` | a dashed outline ("marching ants" round a selection: change `phase` each frame) |

`PSet` and `Line` set `CurrentX` and `CurrentY` to the point they ended on. Lines with ends
far outside the canvas cost no more than lines across it, so you can draw them without
clipping them yourself.

`PSetMany` is the fast way to draw many points (stars, particles, sparks): one call instead
of one call per point. The arrays must hold at least n elements (error 9 otherwise), and
Long arrays are quickest:

*Listing 14.2* (`examples/book/ch14-graphics/listing-14-02.bas`)

<!-- run -->
```basic
Option Explicit

Const N As Long = 200

Sub Main()
    Dim cv As Canvas, i As Long, f As Long
    Dim sx(0 To N - 1) As Long, sy(0 To N - 1) As Long, col(0 To N - 1) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 200
    Rnd -1: Randomize 7                      ' the same stars every run
    For i = 0 To N - 1
        sx(i) = Int(Rnd * 320): sy(i) = Int(Rnd * 200)
        col(i) = RGB(100 + i Mod 156, 100 + i Mod 156, 255)
    Next i
    For f = 1 To 50                          ' 50 frames of a scrolling starfield
        For i = 0 To N - 1
            sx(i) = (sx(i) + 1 + i Mod 3) Mod 320
        Next i
        cv.Cls
        cv.PSetMany sx, sy, col, N           ' all the stars in one call
        cv.Refresh
    Next f
    Print "frames"; cv.Frames; " hash"; cv.Hash
End Sub
```

```output
frames 50  hash 510469737 
```

### See-through drawing: Alpha

`Alpha` (0..255, default 255) sets how opaque drawing is. Below 255, `PSet`, `Line`, `Box`,
`Rect`, `Circle`, `Polygon`, text and the paint helpers blend their colour with what is
already there: shadows, glows, see-through panels. `Cls` and the image copies are not
affected. Black at 128 (a shadow) is especially fast. Set `Alpha` back to 255 for solid
drawing.

*Listing 14.3* (`examples/book/ch14-graphics/listing-14-03.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim cv As Canvas, c As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 32, 32
    cv.Cls vbWhite
    cv.Alpha = 128                     ' half see-through
    cv.Box 0, 0, 16, 16, vbBlack       ' a shadow
    cv.Alpha = 255                     ' back to solid drawing
    c = cv.Point(4, 4)
    Print "red"; c And &HFF; " green"; (c \ &H100) And &HFF; " blue"; (c \ &H10000) And &HFF
    Print "outside the shadow: &H"; Hex$(cv.Point(20, 20))
End Sub
```

```output
red 127  green 127  blue 127 
outside the shadow: &HFFFFFF
```

## Text

The canvas has one built-in font: a fixed 6 x 9 pixel font for the printable characters 32
to 126. Other characters are drawn as `?`. There is no choice of typeface or size for this
font; for bigger text use `DrawTextScaled`, which draws the same font scaled up. (The
[Engine3D](15-engine3d.md) object has a second, larger font of its own.)

| Member | What it does |
|---|---|
| `DrawText x, y, text [, colour]` | text with its top left at (x, y); afterwards `CurrentX` is just past its end and `CurrentY` is y |
| `Print text` | text at `CurrentX`, `CurrentY`, then `CurrentX` = 0 and `CurrentY` moves down one line (10 pixels) |
| `DrawTextScaled x, y, text, colour, scale` | the font `scale` times bigger |
| `TextWidth(text)` | the width of a text in pixels (6 per character) |
| `TextHeight([text])` | the height of a line: 10 (9 pixels and one pixel of spacing) |
| `CurrentX`, `CurrentY` | where `Print` writes next |

*Listing 14.4* (`examples/book/ch14-graphics/listing-14-04.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim cv As Canvas
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 120, 40
    Print "TextWidth(""SCORE 100"") ="; cv.TextWidth("SCORE 100")
    Print "TextHeight ="; cv.TextHeight()
    cv.CurrentX = 2: cv.CurrentY = 2
    cv.Print "line one"
    cv.Print "line two"
    Print "after two Prints: CurrentX"; cv.CurrentX; " CurrentY"; cv.CurrentY
    cv.DrawText 2, 25, "abc"
    Print "after DrawText: CurrentX"; cv.CurrentX
    cv.DrawTextScaled 60, 2, "BIG", vbYellow, 3
    Print "hash"; cv.Hash
End Sub
```

```output
TextWidth("SCORE 100") = 54 
TextHeight = 10 
after two Prints: CurrentX 0  CurrentY 22 
after DrawText: CurrentX 20 
hash 1008490052 
```

To centre a text, use `(cv.Width - cv.TextWidth(s)) \ 2` as its x.

## Images and sprites

A canvas also holds any number of **images**: extra pictures numbered from 1. A new image is
fully transparent. Whatever you draw into it becomes opaque, and `DrawImage` copies only the
opaque pixels, so an image works as a sprite: draw a ship once into an image, then copy it
to a new place every frame. That is also much faster than drawing the shape again each time.

`SetTarget id` sends all drawing to image `id` instead of the back buffer; `SetTarget 0` (or
`BeginDraw`) goes back to the back buffer. `Target` tells you which one is current.

*Listing 14.5* (`examples/book/ch14-graphics/listing-14-05.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim cv As Canvas, ship As Long, big As Long, back As Long
    Dim xs(0 To 2) As Long, ys(0 To 2) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 64

    ' draw a ship once, into an image
    ship = cv.CreateImage(16, 16)
    cv.SetTarget ship
    xs(0) = 8: ys(0) = 0
    xs(1) = 15: ys(1) = 15
    xs(2) = 0: ys(2) = 15
    cv.Polygon xs, ys, 3, vbWhite, True
    cv.SetTarget 0
    Print "ship is image"; ship; "size"; cv.ImageWidth(ship); "x"; cv.ImageHeight(ship)
    Print "corner of the image:"; cv.ImagePoint(ship, 0, 0); "(transparent)"

    ' use it as a sprite
    cv.Cls vbBlue
    cv.DrawImage ship, 24, 24
    Print "sprite pixel &H"; Hex$(cv.Point(32, 36)); ", around it &H"; Hex$(cv.Point(24, 24))

    ' a scaled copy, and the whole picture saved and loaded again
    big = cv.ScaleImage(ship, 32, 32)
    Print "scaled:"; cv.ImageWidth(big); "x"; cv.ImageHeight(big)
    cv.SavePNG "frame.png"
    back = cv.LoadImage("frame.png")
    Print "loaded"; cv.ImageWidth(back); "x"; cv.ImageHeight(back); " same pixel: "; cv.ImagePoint(back, 32, 36) = cv.Point(32, 36)
    Kill "frame.png"
End Sub
```

```output
ship is image 1 size 16 x 16 
corner of the image:-1 (transparent)
sprite pixel &HFFFFFF, around it &HFF0000
scaled: 32 x 32 
loaded 64 x 64  same pixel: True
```

Inside an image, `Cls` with no colour makes the whole image transparent again.

| Member | What it does |
|---|---|
| `CreateImage(w, h)` | a new transparent image (up to 4096 x 4096); returns its number |
| `LoadImage(path)` | load a picture file as a new image; returns its number. Error 53 if the file is missing, 481 if it is not a picture |
| `FreeImage id` | free an image (its number is not reused) |
| `SetTarget id` | draw into image id from now on; 0 = the back buffer |
| `Target` | the current target (read/write) |
| `BeginDraw` | the same as `SetTarget 0` |
| `DrawImage id, x, y [, opaque]` | copy an image to (x, y), skipping its transparent pixels unless `opaque` is True |
| `DrawImagePart id, sx, sy, w, h, x, y [, opaque]` | copy the w x h part at (sx, sy) of an image: tiles and frames from a sprite sheet |
| `DrawImageScaled id, sx, sy, sw, sh, dx, dy, dw, dh [, opaque]` | copy part of an image stretched to dw x dh (nearest pixel: zoomed views). id 0 = the back buffer |
| `DrawImageBlend id, x, y, alpha [, sx, sy, w, h]` | copy an image blended by its own transparency and `alpha` (0..255): layers, fades |
| `ImageWidth(id)`, `ImageHeight(id)` | its size |
| `ImagePoint(id, x, y)` | one pixel of an image; -1 if transparent or outside |
| `ImageBounds(id)` | x, y, w, h of the opaque part, as a Long array; Empty if there is none |
| `ImageHash(id)` | a checksum of an image, transparency included |
| `CopyImage(id [, x, y, w, h])` | a new image copied from (part of) an image; id 0 = the back buffer |
| `FlipImage id [, vertical]` | mirror an image left-right (or upside down) in place |
| `RotateImage(id [, quarters])` | a new image turned by quarters of a turn clockwise (default 1) |
| `ScaleImage(id, w, h [, smooth])` | a new image scaled to w x h; smooth = averaged instead of nearest pixel |
| `SaveImage path [, id]` | save the back buffer (or an image) as a binary PPM file |
| `SavePNG path [, id [, pal(), n]]` | save as PNG: RGB, RGBA if any pixel is see-through, or with a palette of n colours |
| `SaveILBM path [, id [, pal(), n]]` | save as IFF ILBM: 24-bit, or 1 to 8 bitplanes with a palette |

Calling an image number that does not exist (or was freed) is error 5.

**Picture files.** `LoadImage` reads PNG (8 and 16 bits, grey, palette, alpha; not
interlaced), IFF ILBM (1 to 8 bitplanes, EHB, HAM6 and HAM8, 24 and 32-bit, masks) and binary
PPM on every platform. On AmigaOS 4 it also reads anything a datatype is installed for, such
as JPEG and GIF. A file next to the program is `PROGDIR:name.png` on the Amiga.

## Paint helpers

These members are for paint programs, but they are handy elsewhere too. They work on the
current target (back buffer or image). In these members a colour of **-1 means
transparent**, so on an image they erase.

| Member | What it does |
|---|---|
| `FloodFill(x, y [, colour [, tolerance]])` | fill the area of the colour at (x, y) (4-connected); `tolerance` = how far each of red, green and blue may differ; returns the number of pixels filled |
| `FillBounds()` | x, y, w, h (a Long array) of what the last `FloodFill` changed |
| `BrushLine x1, y1, x2, y2, size [, colour [, shape]]` | a line drawn with a brush `size` pixels across, round (0) or square (1) |
| `StampLine id, x1, y1, x2, y2 [, tint [, spacing]]` | image id used as a brush, stamped along a line every `spacing` pixels; tint -2 = its own colours (default), -1 = erase, else one colour |
| `Spray x, y, radius, count [, colour [, seed]]` | an airbrush: count random dots in a circle; `seed` makes it repeatable |
| `ReplaceColor(from, to [, x, y, w, h])` | change every pixel of one colour to another; returns the count |
| `ClearRect x, y, w, h` | make a rectangle transparent |
| `GetPalette(id, max)` | the distinct colours of an image (id 0 = the back buffer) as a Long array; Empty if there are more than max (1..256) |
| `Quantize(id, n)` | a palette of up to n colours that suits the picture best (median cut), as a Long array |
| `RemapImage id, pal(), n [, dither]` | change every pixel to the nearest of n palette colours (dither: Floyd-Steinberg) |
| `LastPalette()` | the palette of the last paletted PNG or ILBM loaded, Empty if none |

*Listing 14.6* (`examples/book/ch14-graphics/listing-14-06.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim cv As Canvas, n As Long, b As Variant, pal As Variant, img As Long, rot As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 48
    cv.Cls vbWhite
    cv.Rect 10, 10, 20, 20, vbBlack          ' an outline...
    n = cv.FloodFill(15, 15, vbRed)          ' ...filled inside
    b = cv.FillBounds()
    Print "filled"; n; "pixels at"; b(0); b(1); "size"; b(2); "x"; b(3)
    n = cv.ReplaceColor(vbRed, vbGreen)
    Print "recoloured"; n
    pal = cv.GetPalette(0, 16)
    Print "colours in the picture:"; UBound(pal) + 1

    img = cv.CopyImage(0, 10, 10, 20, 10)    ' a 20 x 10 piece of the picture
    rot = cv.RotateImage(img, 1)             ' turned a quarter
    Print "copy"; cv.ImageWidth(img); "x"; cv.ImageHeight(img); _
          ", rotated"; cv.ImageWidth(rot); "x"; cv.ImageHeight(rot)

    cv.SetTarget img
    cv.ClearRect 0, 0, 20, 5                 ' the top half transparent
    cv.SetTarget 0
    b = cv.ImageBounds(img)
    Print "opaque part of the copy:"; b(0); b(1); b(2); b(3)

    cv.Gradient 0, 40, 64, 8, vbBlack, vbBlue
    Print "gradient ends: &H"; Hex$(cv.Point(0, 40)); " &H"; Hex$(cv.Point(63, 40))
End Sub
```

```output
filled 324 pixels at 11  11 size 18 x 18 
recoloured 324 
colours in the picture: 3 
copy 20 x 10 , rotated 10 x 20 
opaque part of the copy: 0  5  20  5 
gradient ends: &H0 &HFF0000
```

## Properties

| Property | Type | Notes |
|---|---|---|
| `Width`, `Height` | Long | the picture size (also `ScaleWidth`, `ScaleHeight`). Settable only off-screen |
| `Resize w, h` | method | change the size (1..4096 each) and clear to `BackColor`; error 380 for a bad size |
| `ForeColor` | Long | the default drawing colour (white) |
| `FillColor` | Long | the default colour of `Box` (white) |
| `BackColor` | Long | the colour `Cls` and `Resize` clear to (black) |
| `CurrentX`, `CurrentY` | Long | the text position |
| `Alpha` | Long | 0..255, how opaque drawing is (255) |
| `Target` | Long | the image being drawn into, 0 = the back buffer |
| `Frames` | Long, read-only | how many times `Refresh` has been called |
| `Scale` | Long, read-only | the `.afg`'s `scale=` (1 off-screen) |
| `Left`, `Top` | Long, read-only | where the control is in its window (0 off-screen) |
| `Name` | String, read-only | `"Canvas"` |
| `BlitMode` | Long | how `Refresh` copies to the window (below) |
| `BlitInfo` | String, read-only | the copy method `Refresh` used last, for example `friend bitmap R5G6B5PC` |
| `Hash` | method | a checksum of the current target's pixels |

## A canvas in a form

In a form's `.afg` file a canvas is one line. These keys are read for it:

| Key | Meaning |
|---|---|
| `id` | the name of the canvas variable in the form's code |
| `width`, `height` | the picture size (default 320 x 200); the layout gives the control at least that much room and centres the picture if it gets more |
| `scale` | 1 to 4: show every pixel scale x scale times bigger. Your program still draws `width` x `height`; mouse positions are still in canvas pixels |
| `fill` | `fill=1`: the picture follows the control's size when the window is resized (`width` and `height` are the minimum). The old picture stays at the top left, the new part is cleared to `BackColor`, and the canvas's `Resize` event follows |
| `mousemove` | `mousemove=1`: `MouseMove` events for every move over the canvas, not only while a button is held |
| `rmb` | `rmb=1`: the right mouse button goes to the canvas (painting) instead of opening the menus, with or without Shift and Ctrl |
| `mousepointer` | the pointer shape over the canvas (see `MousePointer`) |
| `contextmenu` | a pop-up menu for the canvas, opened with Shift or Ctrl + right button (see [Menus and dialogs](13-menus-dialogs.md#context-menus)) |

For example, a 320 x 256 picture shown twice as big, with a Timer for the game loop:

```text
# AmiForge GUI
window name=court title="Bat and ball" width=640 height=512
vlayout id=root
  canvas id=view width=320 height=256 scale=2
  timer id=tick interval=20 enabled=1
```

A game can also take the whole display: `screen=own` on the `window` line opens a screen for
the program (`screenwidth=`, `screenheight=`, `screendepth=`, or a mode the user chose with
`App.OpenScreen`), and `fullscreen=1` makes the window cover it without a border. The canvas is
centred in the window: here the 640 x 400 picture sits in the middle of an 800 x 600 screen.
Make the screen a little larger than the picture: the layout keeps a small margin around its
controls, and a window whose layout needs more room than the screen has can't open (error 7):

```text
window name=court title="Bat and ball" screen=own screenwidth=800 screenheight=600 fullscreen=1
vlayout id=root
  canvas id=view width=320 height=200 scale=2
  timer id=tick interval=20 enabled=1
```

The window has no close gadget, so let Esc end the game. A complete example, which also lets
the player choose the screen mode, is in
[The AmigaOS 4 desktop](18-desktop.md#a-full-screen-game-on-its-own-screen).

### Control properties

A canvas in a form also has these properties of the control:

| Property | Type | Notes |
|---|---|---|
| `MouseX`, `MouseY` | Long, read-only | the last mouse position over the canvas, in its pixels |
| `MouseButtons` | Long, read-only | the buttons held now: 1 left, 2 right, 4 middle (added together) |
| `RightButton` | Boolean | the right button goes to the canvas (the `rmb` key). Error 5 if the form was loaded without mouse events: set `rmb=1` in the `.afg` instead |
| `Fill` | Boolean | the `fill` key |
| `MousePointer` | Integer | `vbDefault` (0), `vbCrosshair` (2), `vbIbeam` (3), `vbHourglass` (11), `vbSizeAll` (15), or 100 + an AmigaOS 4 pointer type (for example 135 pen, 137 rubber, 133 zoom in, 111 hand, 138 select, 139 smudge) |
| `ContextMenu` | String | the pop-up menu's id, `""` for none |

The usual control properties such as `Visible` and `ToolTipText` work as for other controls
([Forms](12-forms.md)). Off-screen, these properties do not exist (error 438).

Other things in the forms chapters work with canvases too: `Clipboard.SetPicture canvas [,
imageId]`, `Clipboard.GetPicture(canvas)` and `Clipboard.GetImage(canvas)` copy pictures to
and from the clipboard, and `Printer.PaintPicture canvas` prints one
([Menus and dialogs](13-menus-dialogs.md)).

### Mouse events

| Event | Signature | When |
|---|---|---|
| `MouseDown` | `<id>_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)` | a button went down over the canvas (Button: 1 left, 2 right, 4 middle) |
| `MouseUp` | `<id>_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)` | it was released, also outside the canvas after a press on it |
| `MouseMove` | `<id>_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)` | the pointer moved while a button was held (Button = the buttons held); with `mousemove=1` every move over the canvas |
| `DblClick` | `<id>_DblClick()` | a double click (after the second `MouseDown`) |
| `MouseWheel` | `<id>_MouseWheel(Delta As Integer)` | the wheel turned over the canvas (positive = away from you) |
| `Resize` | `<id>_Resize()` | a `fill=1` canvas got a new size |

X and Y are in canvas pixels, with the scale and centring already taken off. While you drag,
they can be outside the picture (negative, or past the width), so check them before you use
them as array indexes. `Shift` is 1 for Shift, 2 for Ctrl, 4 for Alt and 8 for Amiga, added
together.

On the Amiga the right mouse button opens a window's menus. So `Button = 2` reaches the
canvas only in a form without menus, or over a canvas with `rmb=1`. A plain right click shows
the menu bar, and Shift or Ctrl with the right button opens the canvas's `contextmenu`; with
`rmb=1` the canvas gets every right-button press instead (its `Shift` argument tells you whether
Shift or Ctrl was held), and neither menu opens over it.

Here is the start of a small drawing program's code (the `.afg` has
`canvas id=view width=320 height=200 mousemove=0`):

<!-- fragment -->
```basic
Private lastX As Long, lastY As Long

Private Sub view_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    lastX = X: lastY = Y
    view.PSet X, Y, vbWhite
    view.Refresh
End Sub

Private Sub view_MouseMove(Button As Integer, Shift As Integer, X As Long, Y As Long)
    If Button And vbLeftButton Then
        view.BrushLine lastX, lastY, X, Y, 3, vbWhite
        lastX = X: lastY = Y
        view.Refresh
    End If
End Sub
```

## The keyboard

There are two ways to read the keyboard in a game:

- **Events.** The form gets `Form_KeyDown(KeyCode As Integer, Shift As Integer)` when a key
  goes down (repeated while it is held), `Form_KeyUp` when it is released, and
  `Form_KeyPress(KeyAscii As Integer)` for typed characters. These are best for menus, typing
  a name into a high-score table, and one-off keys like P for pause.
- **Polling.** `view.KeyDown(keycode)` is True while a key is held down. Ask it every frame for
  the keys that steer: it does not depend on key repeat, and several keys can be held at once.

Key codes are the `vbKey` constants: `vbKeyLeft`, `vbKeyRight`, `vbKeyUp`, `vbKeyDown`,
`vbKeySpace`, `vbKeyReturn`, `vbKeyEscape`, `vbKeyA` to `vbKeyZ`, `vbKey0` to `vbKey9`,
`vbKeyF1` to `vbKeyF10`, and so on (the full list is in [Forms](12-forms.md)). `KeyDown` also
knows the qualifier keys on their own: `vbKeyShift` (either Shift), `vbKeyLShift`,
`vbKeyRShift`, `vbKeyControl`, `vbKeyMenu` (either Alt), `vbKeyLMenu`, `vbKeyRMenu`,
`vbKeyLWin` and `vbKeyRWin` (left and right Amiga). The key state is shared by all canvases.

`InjectKey keycode [, down]` sets a key's state as if it had been pressed (`down` True, the
default) or released (False). Use it for tests, demo modes and a computer player, as in the
next example.

## The game loop

A game redraws its picture many times a second. In Boing BASIC the loop is a **Timer**
control in the form: its `Timer` event runs every `Interval` milliseconds, and each event
draws one frame.

| Timer | |
|---|---|
| `.afg` line | `timer id=tick interval=20 enabled=1` (a timer takes no room in the window) |
| `Interval` | Long: milliseconds between events; 0 = never. Setting it starts the timeline again |
| `Enabled` | Boolean: False stops it, True starts it again (the next event one `Interval` later) |
| `<id>_Timer()` | the event |

Timers keep a fixed timeline: each event is due one `Interval` after the previous one was
due, not after your code finished, so a 20 ms timer gives 50 frames a second as long as a
frame takes less than 20 ms. Events never overlap. If a frame takes longer, the next event
comes at once, and if the program falls more than a whole interval behind, the timeline
starts again from now: you never get a burst of catch-up events. So a slow frame makes the
game slower for a moment, never jerky with frames bunched together.

A good way to write a game is to keep the game itself in a module of its own that takes the
canvas as a parameter, and only call it from the form. Then the same code runs in the window
on the Amiga and on an off-screen canvas, where you can test it and measure it. This complete
program is such a game: bat and ball, played by the program itself, which "presses" the
cursor keys with `InjectKey`:

*Listing 14.7* (`examples/book/ch14-graphics/listing-14-07.bas`)

<!-- run -->
```basic
' Bat and ball, played by the program itself on an off-screen canvas
Option Explicit

Private ballX As Long, ballY As Long, dx As Long, dy As Long
Private batX As Long, score As Long, misses As Long

Sub GameStart(cv As Canvas)
    ballX = cv.Width \ 2: ballY = 20
    dx = 3: dy = 2
    batX = cv.Width \ 2 - 20
End Sub

' one frame: read the keys, move, draw, show
Sub GameFrame(cv As Canvas)
    Dim w As Long, h As Long
    w = cv.Width: h = cv.Height
    If cv.KeyDown(vbKeyLeft) And batX > 0 Then batX = batX - 4
    If cv.KeyDown(vbKeyRight) And batX < w - 40 Then batX = batX + 4
    ballX = ballX + dx: ballY = ballY + dy
    If ballX < 4 Or ballX > w - 5 Then dx = -dx
    If ballY < 4 Then dy = -dy
    If ballY >= h - 12 And ballY < h - 8 And ballX >= batX And ballX < batX + 40 Then
        dy = -dy
        score = score + 1
    ElseIf ballY > h Then
        misses = misses + 1
        ballX = w \ 2: ballY = 20
    End If
    cv.Cls RGB(0, 0, 48)
    cv.Box batX, h - 10, 40, 4, vbWhite
    cv.Circle ballX, ballY, 4, RGB(255, 200, 0), True
    cv.DrawText 4, 2, "SCORE " & score & "  MISSED " & misses, vbWhite
    cv.Refresh
End Sub

Sub Main()
    Dim cv As Canvas, f As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 200, 150
    GameStart cv
    For f = 1 To 500
        ' a "player" that presses the keys: keep the bat under the ball
        cv.InjectKey vbKeyLeft, ballX < batX + 10
        cv.InjectKey vbKeyRight, ballX > batX + 30
        GameFrame cv
    Next f
    Print "frames"; cv.Frames; " score"; score; " missed"; misses
    Print "picture hash"; cv.Hash
End Sub
```

```output
frames 500  score 4  missed 0 
picture hash 679037440 
```

To play it in a window, make a project of three files. `Game.bas` is the program above
without `Sub Main`. `court.afg` is the layout shown earlier under "A canvas in a form". The
project file `BatBall.bbp` names them:

```ini
# Boing BASIC project: bat and ball
Name=BatBall
Startup=Form court
Module=Game.bas
Form=court.afg
```

and the form's code, `court.bas`, starts the game and draws a frame on every tick:

<!-- fragment -->
```basic
' court.bas - the form's code
Option Explicit

Private Sub Form_Load()
    GameStart view
End Sub

Private Sub tick_Timer()
    GameFrame view
    If view.KeyDown(vbKeyEscape) Then Unload Me
End Sub
```

`examples/engine3d_demo` in the Boing BASIC directory is built the same way: `Scene.bas` holds
the drawing, `demo.bas` is the form, and `BenchMain.bas` runs the same scene off-screen and
prints the frame rate.

### Frame pacing on AmigaOS 4

- **Use a Timer.** Do not write a loop that draws as fast as it can with `DoEvents`, and do
  not try to wait for the vertical blank: on AmigaOS 4 (and especially under emulation) a
  loop like that uses all the processor time and other programs crawl. A Timer sleeps on
  timer.device between frames.
- **Pick the rate.** `interval=20` (50 frames a second) suits most games. `interval=40` (25)
  halves the work. Make movement depend on frames, as the bat-and-ball game does, and the
  game runs at the same speed on every machine that keeps up.
- **Keep a frame short.** Do the work in as few calls as possible: one `PSetMany` for a cloud
  of points, pre-drawn images instead of shapes drawn again each frame, and
  [Engine3D](15-engine3d.md) for 3D, which does the per-vertex work in C.
- **Mind the scale.** `scale=2` doubles the picture on screen, but copying four times as many
  pixels to the window costs about six times as much (5.6 ms instead of 0.9 ms for a 400 x
  300 canvas on the emulated sam460ex). Draw at the size you need.
- **Compile it.** A program built with `boing build` draws the same picture as one run in the
  interpreter, but the BASIC code between the canvas calls runs many times faster.

### How Refresh reaches the window: BlitMode

`Refresh` converts the 32-bit picture to the screen's pixel format. `BlitMode` (shared by all
canvases) chooses how:

| BlitMode | Method |
|---|---|
| 0 | the best for the screen (the default) |
| 1 | a 32-bit ARGB blit |
| 2 | converted to 16-bit first |
| 3 | through an off-screen bitmap in the screen's own format |

On a 16-bit screen mode 0 uses the off-screen bitmap: 0.94 ms per frame for 400 x 300 on
the emulated sam460ex, against 2.3 ms for the 32-bit blit. Leave it at 0 unless you are
measuring; `BlitInfo` says which method was used.

### Measuring speed

`TimerMs()` returns a time in milliseconds with fractions, good for timing. (`Timer` gives
seconds since midnight as a Single, too coarse for single frames.) Time many frames and divide.
This program measures a simple frame drawn off-screen, so the figure is the drawing alone,
without the copy to the window:

*Listing 14.8* (`examples/book/ch14-graphics/listing-14-08.bas`)

```basic
Option Explicit

Sub GameFrame(cv As Canvas)
    cv.Cls RGB(0, 0, 48)
    cv.Box 80, 140, 40, 4, vbWhite
    cv.Circle 100, 75, 4, RGB(255, 200, 0), True
    cv.DrawText 4, 2, "SCORE 0", vbWhite
    cv.Refresh
End Sub

Sub Main()
    Dim cv As Canvas, f As Long, t0 As Double, ms As Double
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 200, 150
    t0 = TimerMs()
    For f = 1 To 1000
        GameFrame cv
    Next f
    ms = TimerMs() - t0
    Print "1000 frames in"; Format$(ms, "0"); " ms:"; Format$(ms / 1000, "0.000"); " ms a frame"
    If ms > 0 Then Print Format$(1000000 / ms, "0"); " frames a second"
End Sub
```

In a form, time the inside of `tick_Timer` the same way and show the figure on the canvas
every second or so. Compare the interpreter (`boing run`) with a native build (`boing
build`) to see where the time goes.

## Summary

- A canvas is a picture you draw into; `Refresh` shows it in the window. Off-screen canvases
  (`CreateObject("Boing.Canvas")`) work everywhere and are ideal for testing.
- Draw with `Cls`, `PSet`, `Line`, `Box`, `Rect`, `Circle`, `Ellipse`, `Polygon`,
  `PSetMany`, gradients, and text with `DrawText` and `Print`.
- Images are sprites: draw once with `SetTarget`, copy with `DrawImage`. Load and save PNG and
  IFF pictures.
- Read the keys with `KeyDown` each frame, the mouse with the canvas's mouse events.
- Run the game from a Timer, keep the game code in its own module, and test it off-screen.
- For full screen, give the window `screen=own` and `fullscreen=1`; `rmb=1` gives a canvas the
  right mouse button.

See also: [Forms](12-forms.md), [Menus and dialogs](13-menus-dialogs.md),
[Engine3D](15-engine3d.md), [Audio](16-audio.md).

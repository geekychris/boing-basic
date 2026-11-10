# 3D graphics: Engine3D

This chapter is about Engine3D, the 3D engine built into Boing BASIC. It does the heavy work
of a 3D game in fast C code: the camera, turning world points into screen points, clipping,
sorting polygons by depth, models, terrain, lines and point clouds, shading and fog, and a
text font. You give it a [Canvas](14-graphics.md) to draw into, and a frame takes a few dozen
calls instead of thousands of lines of BASIC arithmetic. The chapter builds a first scene step
by step, then describes every member.

## What Engine3D is

Engine3D is a runtime object, made with `CreateObject("Boing.Engine3D")`. It draws into a
canvas, either a form's canvas or an off-screen one, so a 3D program works in the
interpreter, in a native build, and off-screen on the host computer, where it draws exactly
the same picture.

Declare the variable `As Engine3D` (or `As Boing.Engine3D`). Then `boing check` reports a
misspelt member name when it compiles, and a native build calls the members directly. `As
Object` works too.

The engine follows the rules of the amiga3d C engine it comes from: whole numbers
throughout, 16-bit angles, 16.16 fixed point for fine positions, and a painter's algorithm
(polygons drawn from far to near). Because everything is integer arithmetic, a scene gives
the same picture on every machine.

## A first scene, step by step

This program draws 50 frames of a crate turning on a green floor under a sky, on an
off-screen canvas, and prints a checksum of the last picture. Each step is explained below.

*Listing 15.1* (`examples/book/ch15-engine3d/listing-15-01.bas`)

<!-- run -->
```basic
' A first 3D scene: a ground grid, a spinning crate, a sky, on an off-screen canvas
Option Explicit

Sub Main()
    Dim cv As Canvas, e As Engine3D, crate As Long, ground As Long, f As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 256

    ' 1. the engine, the canvas it draws into, and the 3D area
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    e.View 320, 256, 160, 128, 256        ' area 320 x 256, centre (160, 128), scale 256

    ' 2. the palette: pens 0..4
    e.Palette Array(vbBlack, vbWhite, RGB(200, 120, 40), RGB(120, 70, 20), RGB(60, 140, 60))
    e.SkyGradient 5, RGB(20, 40, 100), RGB(160, 190, 230), 128    ' pen 5 is a sky

    ' 3. a model: a crate 60 units wide and high, faces in pens 2 (lit) and 3 (shaded)
    crate = e.ModelNew()
    e.MdlBox crate, 2, 3, -30, 30, 0, 60, -30, 30

    ' 4. flat ground: a 9 x 9 grid of heights, 100 units apart, round the origin
    ground = e.GridNew(9, 9, 100, -400, -400)
    e.GridColours ground, -100, 4, 4, 4, 1000, 1

    For f = 0 To 49
        ' 5. the camera: 120 units up, 250 back, looking a little down
        e.CamPos 0, 120, -250
        e.CamAngles 0, 2500
        ' 6. a frame: clear, fill the draw list, draw it, add text on top
        e.Clear 5
        e.Begin 3000
        e.DrawGrid ground
        e.DrawModel crate, 0, 0, 100, f * 600          ' turning by 600/65536 of a turn a frame
        e.Flush
        e.TextShadow 4, 4, "FRAME " & f, 1
        cv.Refresh
    Next f
    Print "polygons in the last frame:"; e.NPolys
    Print "picture hash:"; cv.Hash
End Sub
```

```output
polygons in the last frame: 39 
picture hash: 798437217 
```

1. **Engine and view.** `Attach` names the canvas the engine draws into. `View` sets the 3D
   area: its width and height in pixels, the screen point straight ahead of the camera (here
   the centre), and the projection scale, which works like a lens: bigger numbers zoom in.
2. **Pens.** The engine draws in **pens**, numbered 0 to 255, like the colour registers of an
   Amiga screen. `Palette` sets pens from `RGB` colours, starting at pen 0. A pen can also be
   a vertical gradient (`SkyGradient`), which is how the sky is drawn.
3. **A model.** A model is a set of vertices and faces kept inside the engine; you refer to it
   by number. `MdlBox` adds a box. Its faces are drawn in the "lit" pen when they face the
   engine's fixed sun and in the "shade" pen when they face away, which gives a cheap
   impression of light.
4. **Terrain.** A grid is a square of heights; here they are all 0, a flat floor.
   `GridColours` chooses its pens by height.
5. **Camera.** `CamPos` puts the camera at a world position; `CamAngles` turns it (yaw, then
   pitch). Positive pitch looks down.
6. **A frame.** `Clear` fills the 3D area with a pen. `Begin` empties the draw list,
   `DrawGrid` and `DrawModel` add polygons to it, and `Flush` draws the whole list into the
   canvas, far polygons first. Text goes on top after `Flush`. `cv.Refresh` shows the frame in a
   window (here it only counts it).

To show the scene in a window, put a canvas and a timer in a form and do steps 1 to 4 in
`Form_Load` and step 6 in the timer's event, as [Graphics](14-graphics.md) describes. The
example program `examples/engine3d_demo` in the Boing BASIC directory is the reference: a
terrain flyover with fog, shaded models and a point cloud, about 800 polygons a frame. Its
form code is just this:

*Listing 15.2* (`examples/book/ch15-engine3d/engine3d_demo/Engine3DDemo.bbp`)

<!-- project: examples/book/ch15-engine3d/engine3d_demo/Engine3DDemo.bbp -->
```basic
Private Sub Form_Load()
    SceneInit view
    ' "--frames N": end after N frames (demos, screenshots)
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
End Sub

Private Sub tick_Timer()
    SceneFrame view, t
    view.Refresh
    t = t + 1
    If view.KeyDown(vbKeyEscape) Or (maxFrames > 0 And t >= maxFrames) Then Unload Me
End Sub
```

`SceneInit` and `SceneFrame` live in the module `Scene.bas`, and `Bench.bbp` runs the same
scene off-screen and prints the frame rate.

## Conventions

- **World coordinates**: x to the right, y up, z ahead, in whole units. You choose what a
  unit means (a centimetre, a metre).
- **16.16 fixed point**: where a member says "16.16", the value is units x 65536, so 1.5
  units is 98304. This gives positions finer than a unit without floating point.
- **Angles**: a full turn is 65536 (a quarter turn is 16384). Any Long is accepted and wraps
  round. Yaw 0 looks along +z and grows towards +x; pitch above 0 looks down; roll turns the
  picture clockwise.
- **Screen coordinates** are pixels of the 3D area, (0, 0) at its top left.
- **Pens**: 0 to 255. Anywhere a pen is expected you may also give `Not RGB(r, g, b)` (that is,
  -1 - colour) to draw in that colour directly. Model faces may use the special pens 200 and
  201, the "body" colours given when the model is drawn (a tank in each team's colours), and
  210 to 219, drawn in the `flash` pen (a hit flash).
- **Arrays** may be Long, Integer, Single, Double or Variant; Long is quickest. Arrays that the
  engine fills must be Long and big enough.
- **Errors**: 5 a bad argument, 9 an array too small or an index out of range, 13 not an array
  (or `Attach` given something that is not a canvas), 91 drawing with no canvas attached, 380
  a model or grid number that does not exist.

## Setting up

| Member | What it does |
|---|---|
| `Attach canvas` | draw into this canvas, into its current target (the back buffer, or an image chosen with `SetTarget`) |
| `View w, h, cx, cy, scale` | the 3D area w x h pixels, the screen point (cx, cy) straight ahead, and the projection scale |
| `ViewOrigin x, y` | where the 3D area's top left is on the canvas (default 0, 0): a 3D window inside a larger picture with a score panel |
| `Sub` | 1 (default) to 4: draw at Sub times the resolution. With `Sub = 2` a game keeps 320 x 256 coordinates but draws into a 640 x 512 canvas, with finer polygon edges and text |
| `Palette colours() [, first]` | set pens from `RGB` colours, starting at pen `first` (default 0) |
| `Palette12 colours() [, first]` | the same from 12-bit Amiga colours `&HRGB` (`&HF80` is orange) |
| `Pen(i)` | read or set one pen as an `RGB` colour |
| `PenColor(i)` (`PenColour`) | the `RGB` colour of pen i, for example for `cv.Cls` |
| `SkyGradient pen, topColour, bottomColour, rows` | make a pen a vertical gradient over `rows` rows of the 3D area |
| `Clear pen` | fill the 3D area with a pen (gradients too) |

## The camera

There is one camera, kept inside the engine.

| Member | What it does |
|---|---|
| `CamPos x, y, z` | put the camera at a world position, in whole units |
| `CamPlace x, y, z` | put it at a 16.16 position (finer movement) |
| `CamAngles yaw, pitch [, roll]` | turn it |
| `CamSet x, y, z, yaw, pitch [, qx, qy, qz [, roll]]` | position and angles in one call; qx, qy, qz add sixteenths of a unit |
| `CamLookAt x, y, z` | turn the camera to look at a world point |
| `CamX`, `CamY`, `CamZ`, `CamYaw`, `CamPitch`, `CamRoll` | the camera's position and angles, read or set one at a time |
| `CamBank cos, sin` | an extra turn of the picture from a 16.16 cosine and sine (aircraft banking); call it after `CamAngles` or `CamSet`, which reset it |
| `CamSave n`, `CamLoad n` | keep and restore up to 8 cameras (n = 0 to 7): a mirror, a radar view, a second player |
| `Horizon` | read-only: the screen row of the horizon |
| `CamU`, `CamNear` | read-only: the camera-space unit (1, or 16 after `CamPlace`) and the near-plane distance |
| `Xform wx, wy, wz, cx, cy, cz` | turn a world point into camera space (x right, y up, z ahead of the camera), into the Long variables cx, cy, cz |
| `XformMany n, wx(), wy(), wz(), cx(), cy(), cz()` | n points at once |
| `Project(wx, wy, wz, sx, sy)` | the screen position of a world point, into the Long variables sx, sy; False if the point is behind the camera |
| `ProjectCam(x, y, z, sx, sy)` | the same for a camera-space point |
| `Visible(wx, wy, wz, radius)` | False if a sphere is certainly off the screen: skip work for things you can't see |

A camera placed with `CamPlace` works in sixteenths of a unit (`CamU` = 16); compare
camera-space distances with `CamNear` rather than a fixed number.

*Listing 15.3* (`examples/book/ch15-engine3d/listing-15-03.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim e As Engine3D, sx As Long, sy As Long, cx As Long, cy As Long, cz As Long
    Set e = CreateObject("Boing.Engine3D")
    e.View 320, 256, 160, 128, 256
    e.CamPos 0, 100, 0
    e.CamAngles 0, 0                       ' looking along +z, level
    Print "horizon row:"; e.Horizon
    e.Xform 50, 100, 400, cx, cy, cz
    Print "camera space:"; cx; cy; cz
    If e.Project(50, 100, 400, sx, sy) Then Print "on screen at"; sx; sy
    If Not e.Project(0, 100, -50, sx, sy) Then Print "a point behind the camera is not drawn"
    Print "visible ahead:"; e.Visible(0, 100, 400, 10); "  behind:"; e.Visible(0, 100, -400, 10)
    e.CamLookAt 400, 100, 400              ' turn to look at a point
    Print "yaw after CamLookAt:"; e.CamYaw; " pitch:"; e.CamPitch
    e.CamSave 0
    e.CamPos 1000, 0, 0
    e.CamLoad 0
    Print "camera restored to x ="; e.CamX
End Sub
```

```output
horizon row: 128 
camera space: 50  0  400 
on screen at 192  128 
a point behind the camera is not drawn
visible ahead:True  behind:False
yaw after CamLookAt: 8192  pitch: 0 
camera restored to x = 0 
```

The point 400 units ahead and 50 to the right lands at x = 160 + 50 x 256 / 400 = 192: the
scale given to `View` divided by the distance.

## The draw list

Between `Begin` and `Flush` you add polygons to the draw list. They are sorted into 512
depth buckets and drawn from far to near, so near things cover far ones. Within a bucket they
are drawn in the order you added them. A frame can hold 8000 entries; more are counted in
`Dropped` and not drawn.

| Member | What it does |
|---|---|
| `Begin far` | empty the list; depths 0 to `far` are sorted (anything further goes in the last bucket) |
| `Far` | read-only: the `far` given to `Begin` |
| `Flush` | draw the list into the canvas |
| `NPolys`, `Dropped` | read-only: polygons added and dropped since `Begin` |
| `PolyW depth, pen, xs(), ys(), zs(), n` | a convex polygon of n (3 to 10) world points |
| `QuadW depth, pen, x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3` | a four-cornered polygon of world points |
| `QuadsW n, depth, pens, coords() [, first]` | n quads from one array of 12 values a quad, starting at quad `first`; `pens` is an array or one pen. Static scenery in one call |
| `Poly depth, pen, xs(), ys(), zs(), n` | a polygon of camera-space points (after `Xform`) |
| `Quad depth, pen, ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz` | a quad of camera-space points |
| `Spot x, y, z, r, pen [, bias]` | a square of half-size r that always faces the camera: shells, particles |
| `Star x, y, z, r, pen, points, turn [, bias]` | a ragged star facing the camera (explosions); `points` = 2 to 5 tips, `turn` its angle |
| `Line3D x1, y1, z1, x2, y2, z2, pen [, bias]` | a world line, sorted with the polygons |
| `Lines3D n, coords(), pens` | n lines of 6 values each |
| `Points n, xs(), ys(), zs(), pens [, size [, bias]]` | a cloud of points (stars, rain, sparks) as size x size squares; a negative size shrinks with distance |
| `DrawLine3D x1, y1, z1, x2, y2, z2, pen` | a world line drawn straight away, not sorted |

Polygons are drawn whichever way they face: these calls do not hide back faces. Models do
(below).

**Depth.** The `depth` argument says where a polygon goes in the order. For the
camera-space calls (`Poly`, `Quad`) it is a camera-space distance. For the world calls
(`PolyW`, `QuadW`, `QuadsW`), a negative `depth` chooses a rule:

| depth | Rule |
|---|---|
| 0 or more | used as it is |
| -1 | half-way between the first and third corners, plus `QuadBias` |
| -2 | the average of the corners |
| -3 | the nearest corner |
| -4 | the farthest corner |
| -5 | the average plus `QuadBias` |

`QuadBias` (default 0) is a property. The `bias` arguments of the other calls move an item
nearer (positive) or further (negative) in the order, to settle which of two touching things
is drawn on top.

## Models

Models are numbered from 1. A model has up to 256 vertices and 192 faces, each face a
triangle or a quad. You build a model once and draw it as often as you like each frame.

| Member | What it does |
|---|---|
| `ModelNew()` | a new empty model; returns its number |
| `MdlVtx(m, x, y, z)` | add a vertex; returns its index (from 0) |
| `MdlFace m, lit, shade, n, a, b, c, d, ix, iy, iz` | add a face of n (3 or 4) vertices a, b, c, d; it is turned to face away from the inside point (ix, iy, iz), and drawn in `lit` or `shade` |
| `MdlBox m, lit, shade, x0, x1, y0, y1, z0, z1` | add a box |
| `MdlPyramid m, lit, shade, x0, x1, y0, z0, z1, apex` | add a pyramid on the rectangle x0..x1, z0..z1 at height y0, with its tip at height `apex` |
| `MdlPrism m, lit, shade, sides, r, y0, y1 [, noTop]` | add an upright prism of `sides` sides and radius r from y0 to y1 (a post, a tower); noTop True leaves the top off |
| `MdlShadow m, pen, x0, x1, z0, z1` | add a flat shadow just above the ground, drawn before the rest of the model |
| `ModelFromArrays(vx(), vy(), vz(), nv, fn(), fi(), fcol(), nf)` | a new model from arrays: nv vertices; nf faces with `fn(k)` = 3 or 4 corners, `fi` four vertex indices a face, `fcol` a pen a face. Wind the faces clockwise as seen from outside |
| `ModelLoad(path)` | a new model from a text file (below). Error 53 if the file is missing, 5 for a line it does not understand |
| `ModelClear m` | remove all of a model's vertices and faces |
| `ModelFree m` | free a model |
| `ModelVerts(m)`, `ModelFaces(m)` | the counts |
| `ModelRadius(m)` | the distance of its furthest vertex from its origin, for `Visible` |
| `ModelMargin` | property: a model whose centre is more than this many units (default 800) outside the view or behind the camera is skipped |

### Drawing models

| Member | What it does |
|---|---|
| `DrawModel m, x, y, z [, yaw [, pitch [, roll [, bodyLit [, bodyShade [, flash [, bias]]]]]]]` | draw a model at a world position, turned by the angles |
| `DrawModelF m, x16, y16, z16 [, ...]` | the same at a 16.16 position, for smooth slow movement |
| `DrawModelM m, x, y, z, rot() [, bodyLit, bodyShade, flash, bias]` | turned by your own 3 x 3 matrix of nine 16.16 values (row by row). Scale the matrix to scale the model |
| `DrawModelMF m, x16, y16, z16, rot() [, ...]` | the same at a 16.16 position |
| `DrawModels n, ids, xs(), ys(), zs(), yaws [, f16 [, bodyLit [, bodyShade [, bias]]]]` | n models in one call. `ids`, `yaws`, `bodyLit`, `bodyShade` and `bias` are each an array (one value a model) or one value for all; f16 True means the positions are 16.16 |

Only the faces that face the camera are drawn, sorted far to near, and the whole model goes
into the draw list at the depth of its centre (minus `bias`). `bodyLit` and `bodyShade` are the
pens used for faces in pens 200 and 201 (pen 3 if you leave them out); `bodyShade` defaults
to `bodyLit`. `flash` (default pen 1) replaces pens 210 to 219.

### Model files

A model file is plain text, one command a line, with `#` starting a comment:

```text
# a crate
v -34 0 -34          # a vertex (numbered 0, 1, 2 ... in order)
v  34 0 -34
f 13 0 3 2 1         # a face: its pen, then 3 or 4 vertex numbers, clockwise from outside
f body 4 5 6 7       # pen names: body or lit (200), shade (201), flash (210)
box 13 14 -34 34 0 56 -34 34       # the builders: box, pyramid, prism, shadow, face
```

`box`, `pyramid`, `prism`, `shadow` and `face` take the same numbers as `MdlBox`,
`MdlPyramid`, `MdlPrism`, `MdlShadow` and `MdlFace` without the model number.

*Listing 15.4* (`examples/book/ch15-engine3d/listing-15-04.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim e As Engine3D, m As Long, t As Long, f As Integer
    Set e = CreateObject("Boing.Engine3D")
    ' write a small model file: a square pyramid by hand, and a box from a builder
    f = FreeFile
    Open "tent.3d" For Output As #f
    Print #f, "# a tent: four sides and a floor"
    Print #f, "v -40 0 -40"
    Print #f, "v  40 0 -40"
    Print #f, "v  40 0  40"
    Print #f, "v -40 0  40"
    Print #f, "v   0 60  0     # the top (index 4)"
    Print #f, "f 2 0 4 1"
    Print #f, "f 3 1 4 2"
    Print #f, "f 2 2 4 3"
    Print #f, "f 3 3 4 0"
    Print #f, "f body 0 1 2 3"
    Print #f, "box 5 6 -10 10 0 20 -50 -40"
    Close #f
    m = e.ModelLoad("tent.3d")
    Print "model"; m; ":"; e.ModelVerts(m); "vertices,"; e.ModelFaces(m); "faces, radius"; e.ModelRadius(m)
    t = e.ModelNew()
    Print "next model is"; t
    e.ModelFree m
    Kill "tent.3d"
End Sub
```

```output
model 1 : 13 vertices, 11 faces, radius 61 
next model is 2 
```

## Terrain

A grid is w x h heights spaced `cell` units apart, with its corner at world (x0, z0). It is
drawn as a surface of quads (split into two triangles where the four corners are not flat),
each shaded by its slope. Only the cells within range of the camera are drawn, so a large map
costs only what is near.

| Member | What it does |
|---|---|
| `GridNew(w, h, cell [, x0, z0])` | a new grid (w and h 2 to 1025), all heights 0; returns its number |
| `GridSet g, heights() [, pens()]` | all the heights at once (w x h values, row by row along x), and optionally a pen for each cell ((w - 1) x (h - 1)) |
| `GridHeightSet g, i, j, y` | the height of one point |
| `GridPenSet g, i, j, pen` | the pen of one cell |
| `GridGenerate g, seed, rough, height` | fill with random hills (fractal); the same `seed` gives the same land |
| `GridColours g, waterLevel, waterPen, lowPen, highPen, snowLevel, snowPen` (`GridColors`) | pens by the height of each cell: `waterPen` below `waterLevel`, `snowPen` above `snowLevel`, and between them `lowPen` in the lower half and `highPen` in the upper half |
| `GridHeight(g, x16, z16)` | the ground height under a point, in whole units; x and z are 16.16 |
| `GridHeightF(g, x16, z16)` | the same as a 16.16 value |
| `DrawGrid g [, range [, bias]]` | add the cells ahead of the camera within `range` units (default: all) to the draw list |
| `GridShade g, on` | shade the cells by slope (default True); False draws plain pens, one quad a cell (faster) |
| `GridFree g` | free a grid |

`GridHeight` is how you keep a vehicle on the ground and the camera above the hills, as the
next example does.

## Shading and fog

| Member | What it does |
|---|---|
| `Shading` | False (default): faces are drawn in their pens as given. True: each face's pen is shaded by how much it faces the light |
| `Light x, y, z [, ambient]` | the direction the light comes from (any length), and the light everything gets (0 to 256, default 64) |
| `Fog colour, near, far` | blend into an `RGB` colour from distance `near` to `far` (camera units); `Fog -1` turns fog off |

Grids are shaded by the light whatever `Shading` is (see `GridShade`). This scene uses most
of what has been described so far: generated hills with fog and light, a row of shaded posts
standing on the ground, a wall, a line, a point cloud and a spot, drawn into a 3D window that
starts 20 rows down the canvas:

*Listing 15.5* (`examples/book/ch15-engine3d/listing-15-05.bas`)

<!-- run -->
```basic
' Hills, fog, shading, a row of pylons, sparks and a wall, drawn into a 3D window in a HUD
Option Explicit

Sub Main()
    Dim cv As Canvas, e As Engine3D, hills As Long, pylon As Long, i As Long
    Dim px(0 To 4) As Long, py(0 To 4) As Long, pz(0 To 4) As Long
    Dim sx(0 To 99) As Long, sy(0 To 99) As Long, sz(0 To 99) As Long, st As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 240
    Set e = CreateObject("Boing.Engine3D")
    e.Attach cv
    e.ViewOrigin 0, 20                         ' the 3D area starts 20 rows down
    e.View 320, 200, 160, 100, 220
    ' pens: 0 black, 1 white, 2 grey, 3 red, 4 water, 5 grass, 6 rock, 7 snow, 8 sky, 9 yellow
    e.Palette12 Array(&H000, &HFFF, &H888, &HC22, &H36A, &H5A4, &H886, &HEEF, &H9BE, &HFE4)
    e.Fog RGB(150, 180, 220), 600, 2000        ' fade into the haze from 600 to 2000 units
    e.Light 1, 2, -1, 80                       ' light from up and to the right

    hills = e.GridNew(33, 33, 64, -1024, 0)
    e.GridGenerate hills, 7, 120, 200          ' fractal hills
    e.GridColours hills, -20, 4, 5, 6, 140, 7  ' water, grass, rock, snow on top

    pylon = e.ModelNew()
    e.MdlPrism pylon, 2, 2, 6, 6, 0, 80        ' a six-sided post
    e.MdlPyramid pylon, 3, 3, -12, 12, 80, -12, 12, 100
    For i = 0 To 4
        px(i) = -200 + i * 100: pz(i) = 400 + i * 50
        py(i) = e.GridHeight(hills, px(i) * 65536, pz(i) * 65536)   ' stand on the ground
    Next i

    st = 5
    For i = 0 To 99
        sx(i) = (e.Rand(st) Mod 400) - 200
        sy(i) = 150 + e.Rand(st) Mod 100
        sz(i) = 300 + e.Rand(st) Mod 600
    Next i

    cv.Cls vbBlack
    e.CamPos 0, e.GridHeight(hills, 0, 200 * 65536) + 120, 200
    e.CamAngles 0, 1500
    e.Clear 8
    e.Begin 4000
    e.DrawGrid hills, 1800
    e.Shading = True                            ' flat shading for the models
    e.DrawModels 5, pylon, px, py, pz, 0        ' five pylons in one call
    e.Shading = False
    e.QuadW -2, 3, -60, 0, 700, 60, 0, 700, 60, 60, 700, -60, 60, 700
    e.Line3D -200, 200, 500, 200, 200, 500, 9
    e.Points 100, sx, sy, sz, 1, 2
    e.Spot 0, 180, 500, 8, 9
    e.Flush
    e.TextCentre 4, "HILLS", 1, 2
    cv.DrawText 4, 6, "polygons " & e.NPolys & ", dropped " & e.Dropped, vbWhite
    Print "polygons"; e.NPolys; " dropped"; e.Dropped
    Print "hash"; cv.Hash
End Sub
```

```output
polygons 970  dropped 0 
hash 2111274750 
```

## Text and flat drawing

The engine has its own font, larger and clearer than the canvas's: 16 x 16 cells
(characters 32 to 126). These members draw straight onto the canvas, not into the draw list,
in 3D-area coordinates; call them after `Flush` to draw on top of the scene.

| Member | What it does |
|---|---|
| `Text x, y, s, pen [, scale]` | text with the top of its cells at y; scale 1 draws 8 x 8 cells (16 x 16 with `Sub = 2`), 2 twice that, and so on |
| `TextShadow x, y, s, pen [, scale]` | the same with a shadow in pen 0 one pixel down and right |
| `TextCentre y, s, pen [, scale]` (`TextCenter`) | centred across the 3D area, with a shadow |
| `TextWidth(s [, scale])` | the width of a text in 3D-area pixels |
| `FillRect x0, y0, x1, y1, pen` | a filled rectangle between two corners |
| `PolyFill xs(), ys(), n, pen` | a filled polygon of screen points |
| `Span y, xl, xr, pen` | one row from xl to xr, in the drawing's own pixels (multiplied by `Sub`) |
| `FillGradient y0, y1, topColour, bottomColour` | rows y0 to y1 across the 3D area shaded between two `RGB` colours |
| `Blend y, xl, xr, pen, alpha` | a see-through row (alpha 0 to 256), in the drawing's own pixels |

You can also draw with the canvas's own methods between frames (as the example above does
for the polygon count).

## Maths helpers

These integer maths functions give exactly the values the engine uses, so game rules
written with them come out the same on every machine. Angles are 16-bit (65536 a turn) and
results marked 16.16 are x 65536.

| Member | What it does |
|---|---|
| `Sin(a)`, `Cos(a)` | the sine and cosine of an angle, 16.16 |
| `Atan2(x, y)` | the angle of the direction (x, y), measured from +y towards +x |
| `ISqrt(v)` | the integer square root |
| `Hypot(x, y)` | the length of (x, y) |
| `FMul(a, b)`, `FDiv(a, b)`, `FSqrt(a)` | multiply, divide and square root of 16.16 values |
| `Hash(x)` | a well-mixed number made from x (repeatable randomness for level generation) |
| `Rand(state)` | the next pseudo-random number (0 to 32767); `state` is a Long variable the call updates |
| `RotYPR rot(), yaw, pitch, roll` | fill a Long array of 9 with a 16.16 rotation matrix (for `DrawModelM`) |
| `RotYaw rot(), yaw` | the same for a turn about the vertical only |
| `MatMul out(), a(), b()` | multiply two 3 x 3 matrices |
| `MatApply rot(), x, y, z, ox, oy, oz` | turn a point by a matrix into the variables ox, oy, oz |
| `SinTable(out())`, `CosTable(out())` | fill a 256-element Long array with a table, so you can look values up in BASIC without a call |

*Listing 15.6* (`examples/book/ch15-engine3d/listing-15-06.bas`)

<!-- run -->
```basic
Option Explicit

Sub Main()
    Dim e As Engine3D, st As Long
    Set e = CreateObject("Boing.Engine3D")
    Print "Sin(16384) ="; e.Sin(16384); " (a quarter turn: 1.0 is 65536)"
    Print "Cos(0) ="; e.Cos(0); "  Sin(8192) ="; e.Sin(8192)
    Print "Atan2(1, 1) ="; e.Atan2(1, 1); " (an eighth of a turn)"
    Print "ISqrt(1000000) ="; e.ISqrt(1000000); "  Hypot(3, 4) ="; e.Hypot(3, 4)
    Print "FMul(1.5, 2.5) ="; e.FMul(98304, 163840) / 65536
    Print "FDiv(1, 4) ="; e.FDiv(65536, 262144) / 65536
    Print "FSqrt(2) ="; e.FSqrt(131072) / 65536
    st = 1
    Print "Rand:"; e.Rand(st); e.Rand(st); e.Rand(st)
    Print "Hash(42) ="; e.Hash(42)
End Sub
```

```output
Sin(16384) = 65536  (a quarter turn: 1.0 is 65536)
Cos(0) = 65536   Sin(8192) = 46341 
Atan2(1, 1) = 8192  (an eighth of a turn)
ISqrt(1000000) = 1000   Hypot(3, 4) = 5 
FMul(1.5, 2.5) = 3.75 
FDiv(1, 4) = .25 
FSqrt(2) = 1.4141845703125 
Rand: 16838  5758  10113 
Hash(42) = 388445122 
```

## Speed

Keep the per-vertex work inside the engine. A frame should be tens of calls: one for the
ground, one for a batch of quads (`QuadsW`), one per model (or one `DrawModels` for many), one
for a point cloud. Each call costs about as much as a canvas call, whatever it draws, so a
loop that calls `QuadW` for every tile of a map in BASIC is the slow way; build the tiles into
an array once and draw them with one `QuadsW`. Use `Visible` to skip objects that are off the
screen before you do any work for them, and measure with `TimerMs()` as described in
[Graphics](14-graphics.md).

## Summary

- `CreateObject("Boing.Engine3D")`, `Attach` a canvas, set the `View` and the pens.
- Each frame: place the camera, `Clear`, `Begin`, add grids, models and polygons, `Flush`,
  then draw text on top and `Refresh` the canvas.
- Positions are whole units or 16.16; angles are 65536 to a turn; colours are pens.
- Build models with the `Mdl` members or load them from text files; draw them with
  `DrawModel` or many at once with `DrawModels`.

See also: [Graphics](14-graphics.md), [Audio](16-audio.md), [Forms](12-forms.md).

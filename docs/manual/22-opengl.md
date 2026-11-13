# 3D graphics: OpenGL

This chapter is about OpenGL, the 3D graphics interface that a great many books, tutorials and
games are written for. Boing BASIC has the classic OpenGL (version 1.x, "fixed function"): you
describe a camera, lights and materials, send it points, lines and polygons, and it draws them
with a depth buffer, lighting, textures and fog. The chapter builds pictures step by step,
first off-screen and then in a window, and ends with what makes OpenGL programs fast.

## OpenGL or Engine3D?

Boing BASIC has two ways to draw 3D. [Engine3D](15-engine3d.md) is a game engine: whole-number
maths, models and terrain grids, a painter's algorithm, a frame in a few dozen calls. OpenGL is
a drawing interface: you say what to draw, triangle by triangle or from arrays, and it works out
the rest per pixel, with a depth buffer (no sorting), smooth lighting and textures. Choose
OpenGL when you want those, or when you follow OpenGL material written for other systems.
Choose Engine3D for a scene that should cost as little as possible.

OpenGL here is Mesa's software renderer: it needs no 3D graphics card, and every AmigaOS 4
machine (and the QEMU emulator) draws the same picture. It draws into a
[Canvas](14-graphics.md), a form's or an off-screen one.

## Asking for OpenGL: Extension=opengl

OpenGL is a **standard extension**, like SQLite: a program that uses it has this line in its
project file,

```ini
Extension=opengl
```

and the OpenGL functions and constants are then there. A program that uses OpenGL is therefore
always a project (a `.bbp` file, see [Projects](02-shell.md#projects)). The interpreter in the
Boing BASIC kit has OpenGL built in, so `boing run` and AmiForge's Run just work; a native build
(`boing build`, AmiForge's Build) links OpenGL into the program, which makes it about 3 MB
larger. [Standard extensions](21-extending.md#standard-extensions) in chapter 21 says more.

The functions have their OpenGL names (`glBegin`, `glVertex3f`, `gluPerspective`), and the
constants their `GL_` names (`GL_TRIANGLES`, `GL_DEPTH_TEST`). A misspelt one is an error when
the program is compiled, as for any other name. The arguments are numbers: OpenGL's floating
point arguments take any number, its enumerations and counts a whole number.

One thing to watch for: a call without arguments followed by a colon **at the start of a line**
(`glLoadIdentity: glTranslatef 0, 0, -5`) is a line label (see [GoTo](06-control-flow.md)),
so the call is never made. `boing check` warns about it. Put such a call on its own line.

## A first picture, step by step

This program draws one triangle with a different colour at each corner, on an off-screen
canvas, and then reads some pixels back. Every example in this chapter is a small project in
`examples/book/ch22-opengl/`; this is `first`:

```ini
# First: a first OpenGL picture on an off-screen canvas (manual chapter 22)
Name=First
Startup=Sub Main
Module=first.bas
Extension=opengl
```

*Listing 22.1* (`examples/book/ch22-opengl/first/first.bbp`)

<!-- project: examples/book/ch22-opengl/first/first.bbp -->
```basic
' first.bas - a triangle drawn by OpenGL into an off-screen canvas, then read back
Option Explicit

Sub Main()
    Dim cv As Canvas
    ' 1. a canvas to draw into, and OpenGL attached to it
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 160, 128
    GLAttach cv
    ' 2. the camera: x from -1 (left) to 1 (right), y from -1 (bottom) to 1 (top)
    glMatrixMode GL_PROJECTION
    glLoadIdentity
    glOrtho -1, 1, -1, 1, -1, 1
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    ' 3. clear to dark blue, then a triangle with a colour at each corner
    glClearColor 0, 0, 0.5, 1
    glClear GL_COLOR_BUFFER_BIT
    glBegin GL_TRIANGLES
    glColor3f 1, 0, 0: glVertex2f -0.8, -0.8
    glColor3f 0, 1, 0: glVertex2f 0.8, -0.8
    glColor3f 0, 0, 1: glVertex2f 0, 0.8
    glEnd
    ' 4. wait for GL to finish; the canvas now holds the picture
    GLPresent
    Describe "the top left corner", cv.Point(2, 2)
    Describe "near the red corner", cv.Point(20, 112)
    Describe "near the green corner", cv.Point(140, 112)
    Describe "near the blue corner", cv.Point(80, 20)
    Print "OpenGL "; Left$(glGetString(GL_VERSION), 3); " by "; glGetString(GL_VENDOR)
End Sub

' the strongest of a colour's red, green and blue parts (Point gives RGB() colours, &HBBGGRR)
Sub Describe(ByVal where As String, ByVal c As Long)
    Dim r As Long, g As Long, b As Long, name As String
    r = c And &HFF: g = (c \ &H100) And &HFF: b = (c \ &H10000) And &HFF
    If r > g And r > b Then
        name = "red"
    ElseIf g > b Then
        name = "green"
    Else
        name = "blue"
    End If
    Print where; " is mostly "; name
End Sub
```

```output
the top left corner is mostly blue
near the red corner is mostly red
near the green corner is mostly green
near the blue corner is mostly blue
OpenGL 2.1 by Brian Paul
```

1. **`GLAttach cv`** gives OpenGL a canvas to draw into. From then on, every OpenGL call draws
   into that canvas's pixels.
2. **The projection** says which part of the 3D world the canvas shows. `glMatrixMode
   GL_PROJECTION` picks the projection matrix, `glLoadIdentity` resets it and `glOrtho` sets
   a box: x from -1 to 1 across the canvas, y from -1 at the bottom to 1 at the top, and z from
   -1 to 1. Then `glMatrixMode GL_MODELVIEW` and `glLoadIdentity` reset the matrix that places
   things in the world. Note that y goes **up** in OpenGL, unlike Canvas coordinates.
3. **`glClearColor` and `glClear`** fill the canvas with a colour (red, green, blue and alpha
   from 0 to 1). `glBegin GL_TRIANGLES` starts a list of triangles, three `glVertex2f` points
   make one, and `glEnd` ends the list. Each `glColor3f` sets the colour for the points after
   it, and OpenGL blends the colours across the triangle.
4. **`GLPresent`** waits until OpenGL has finished. The picture is now in the canvas: `Point`
   reads it, `SaveImage` would save it, and a form's canvas would show it on `Refresh`.

## A program in a window

A program with a window does the same in two places: it sets OpenGL up once in `Form_Load`,
and draws a frame in each tick of a [Timer](14-graphics.md#the-game-loop). This is `spinner`, a lit
ring that turns; its form is a 320 x 256 canvas shown at twice that size and a timer:

```ini
# Spinner: a lit torus turning in a window, with a HUD (manual chapter 22)
Name=Spinner
Startup=Form spinner
Form=spinner.afg
Extension=opengl
```

*Listing 22.2* (`examples/book/ch22-opengl/spinner/Spinner.bbp`)

<!-- project: examples/book/ch22-opengl/spinner/Spinner.bbp -->
```basic
' spinner.bas - the frame of an OpenGL program in a window: set up once in Form_Load, draw a
' frame in each Timer tick. Esc closes it.
Option Explicit

Private angle As Double, frames As Long, torus As Long

Private Sub Form_Load()
    GLAttach view                                 ' OpenGL draws into the form's canvas
    glEnable GL_DEPTH_TEST
    glEnable GL_CULL_FACE                         ' skip the faces turned away from us
    glEnable GL_LIGHTING
    glEnable GL_LIGHT0
    glLight4f GL_LIGHT0, GL_POSITION, 1, 1, 1, 0  ' a light from the upper right, far away
    glEnable GL_COLOR_MATERIAL                    ' glColor sets the material's colour
    glMatrixMode GL_PROJECTION
    gluPerspective 45, 320 / 256, 1, 50           ' 45 degrees high, the canvas's shape
    glMatrixMode GL_MODELVIEW
    ' the torus never changes shape: record it once in a display list
    torus = glGenLists(1)
    glNewList torus, GL_COMPILE
    glutSolidTorus 0.35, 1, 12, 24
    glEndList
End Sub

Private Sub tick_Timer()
    glClearColor 0.05, 0.05, 0.15, 1
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    glTranslatef 0, 0, -5                         ' move the world 5 units away from the eye
    glRotatef angle, 1, 0.5, 0                    ' and turn it
    glColor3f 1, 0.6, 0.1
    glCallList torus
    GLPresent                                     ' the picture is in the canvas
    view.DrawText 4, 4, "frame " & frames, vbWhite   ' the HUD, drawn with the Canvas
    view.Refresh                                  ' show it
    angle = angle + 4
    frames = frames + 1
    If view.KeyDown(vbKeyEscape) Then Unload Me
End Sub
```

Each frame:

- `glClear` with `GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT` clears the picture and the
  **depth buffer**, OpenGL's record of how far away each pixel's surface is. With `glEnable
  GL_DEPTH_TEST`, a pixel is only drawn if it is nearer than what is already there, so surfaces
  hide each other correctly in any order.
- `glLoadIdentity`, `glTranslatef` and `glRotatef` place the ring: the matrix moves the world
  5 units away from the eye, then turns it. `glRotatef` takes degrees and an axis.
- `glCallList torus` draws the ring that `Form_Load` recorded in a **display list** (see
  [Speed](#speed)).
- `GLPresent`, then anything drawn with the Canvas lands on top of the 3D picture: here the
  frame count with `DrawText`. `Refresh` shows it.

`gluPerspective 45, 320 / 256, 1, 50` is the usual camera: 45 degrees from the bottom of the
picture to the top, the canvas's width/height ratio, and nothing nearer than 1 or further than
50 units. Far things look smaller, as through a real camera.

## The camera and the matrices

OpenGL places every point with two matrices. The **projection** (`GL_PROJECTION`) is the camera's
lens: `gluPerspective`, `glFrustum` or `glOrtho`. The **model-view** (`GL_MODELVIEW`) moves the
world in front of the camera: `glTranslatef`, `glRotatef`, `glScalef`, or `gluLookAt` for a
camera at one point looking at another. Each call changes the current matrix, so the order
counts: translate then rotate turns an object where it is; rotate then translate moves it along
a turned direction.

`glPushMatrix` saves the current matrix and `glPopMatrix` puts it back. That is how a program
draws several objects, each moved from the same camera: push, move, draw, pop. The `labels`
program below does exactly that.

## Light and materials

Without lighting, every point has the colour given by `glColor`. With `glEnable GL_LIGHTING`,
the colour comes from **lights** (up to eight, `GL_LIGHT0` to `GL_LIGHT7`, each switched on with
`glEnable`) and the **material** of the surface, and the shapes' **normals** (the direction each
surface faces; the `glut` shapes have them; for your own polygons `glNormal3f`) decide how much
light a surface catches.

*Listing 22.3* (`examples/book/ch22-opengl/lighting/lighting.bbp`)

<!-- project: examples/book/ch22-opengl/lighting/lighting.bbp -->
```basic
' lighting.bas - a white sphere lit from the left: the left side is bright, the right side is
' only lit by the ambient light. A material and a light colour change what we see.
Option Explicit

Private cv As Canvas

Sub Main()
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 160, 120
    GLAttach cv
    glEnable GL_DEPTH_TEST
    glMatrixMode GL_PROJECTION
    gluPerspective 40, 160 / 120, 1, 20
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    glTranslatef 0, 0, -6

    glEnable GL_LIGHTING
    glEnable GL_LIGHT0
    ' w = 0: a directional light, shining from the left (-x) towards the sphere
    glLight4f GL_LIGHT0, GL_POSITION, -1, 0, 0.3, 0
    glLight4f GL_LIGHT0, GL_DIFFUSE, 1, 1, 1, 1
    glLightModel4f GL_LIGHT_MODEL_AMBIENT, 0.15, 0.15, 0.15, 1
    glMaterial4f GL_FRONT, GL_DIFFUSE, 1, 1, 1, 1
    glMaterial4f GL_FRONT, GL_AMBIENT, 1, 1, 1, 1
    Frame "white light"

    ' the same light in orange: only the lit side changes colour
    glLight4f GL_LIGHT0, GL_DIFFUSE, 1, 0.5, 0, 1
    Frame "orange light"

    ' flat shading: one colour per face instead of a smooth blend
    glShadeModel GL_FLAT
    Frame "flat"
    Print "error"; glGetError()
End Sub

Sub Frame(ByVal title As String)
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glutSolidSphere 1.5, 24, 16
    GLPresent
    Print title; ": left"; Level(cv.Point(55, 60)); " right"; Level(cv.Point(105, 60)); _
          " red>blue on the left: "; (cv.Point(55, 60) And &HFF) > ((cv.Point(55, 60) \ &H10000) And &HFF)
End Sub

' brightness 0..9 from the red part of a colour (&HBBGGRR)
Function Level(ByVal c As Long) As Long
    Level = (c And &HFF) * 10 \ 256
End Function
```

```output
white light: left 8  right 1  red>blue on the left: False
orange light: left 8  right 1  red>blue on the left: True
flat: left 8  right 1  red>blue on the left: True
error 0
```

- `glLight4f GL_LIGHT0, GL_POSITION, x, y, z, w`: with w = 0 the light is infinitely far away in
  the direction (x, y, z), like the sun; with w = 1 it is a lamp at that point.
- `GL_DIFFUSE` is the light's colour, `GL_LIGHT_MODEL_AMBIENT` the light that reaches every
  surface from everywhere (so the dark side isn't black).
- `glMaterial4f GL_FRONT, GL_DIFFUSE, ...` is how much of each colour the surface reflects.
  `glEnable GL_COLOR_MATERIAL` (as in `spinner`) makes `glColor` set the material instead,
  which is often simpler.
- `glShadeModel GL_FLAT` gives each polygon one colour; the default `GL_SMOOTH` blends the
  colours of its corners.

The shapes from GLUT are there with their normals: `glutSolidCube`, `glutSolidSphere`,
`glutSolidTorus`, `glutSolidCone`, `glutSolidCylinder`, their `Wire` versions, and
`glutSolidCheckerSphere`, a ball checkered in two colours.

## Textures

A **texture** is a picture laid over polygons. Make one with `glGenTexture()`, select it with
`glBindTexture GL_TEXTURE_2D, t`, fill it, and draw with `glEnable GL_TEXTURE_2D`, giving each
point a texture coordinate with `glTexCoord2f`: (0, 0) is the picture's bottom left corner and
(1, 1) its top right. There are two ways to fill a texture: from an array of colours, or from a
picture drawn with the Canvas, text included.

*Listing 22.4* (`examples/book/ch22-opengl/texture/texture.bbp`)

<!-- project: examples/book/ch22-opengl/texture/texture.bbp -->
```basic
' texture.bas - two textures on a square that fills the canvas: one from an array of colours,
' one drawn with the Canvas methods (a picture with text) into an image
Option Explicit

Sub Main()
    Dim cv As Canvas, px(63) As Long, x As Long, y As Long, checker As Long, label As Long, img As Long

    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 128, 128
    GLAttach cv
    glMatrixMode GL_PROJECTION
    glLoadIdentity
    gluOrtho2D 0, 1, 0, 1
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    glEnable GL_TEXTURE_2D

    ' 1. an 8 x 8 checkerboard: colours &HAARRGGBB, row by row from the top
    For y = 0 To 7
        For x = 0 To 7
            If (x + y) Mod 2 = 0 Then px(y * 8 + x) = &HFFFFFFFF Else px(y * 8 + x) = &HFFC00000
        Next
    Next
    checker = glGenTexture()
    glBindTexture GL_TEXTURE_2D, checker
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST   ' sharp squares
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST
    GLTexImage 8, 8, px
    Square
    Print "checker: top left "; Hex$(cv.Point(4, 4)); ", next square "; Hex$(cv.Point(20, 4))

    ' 2. a texture drawn with the Canvas: an image of 64 x 64, then text on it
    img = cv.CreateImage(64, 64)
    cv.SetTarget img
    cv.Box 0, 0, 64, 64, RGB(0, 90, 160)
    cv.DrawText 8, 28, "BOING", vbYellow
    cv.SetTarget 0
    label = glGenTexture()
    glBindTexture GL_TEXTURE_2D, label
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST
    GLTexImageCanvas cv, img
    Square
    Print "label: background "; Hex$(cv.Point(4, 4)); ", yellow text pixels"; CountColour(cv, vbYellow)
    Print "error"; glGetError()
End Sub

' a square over the whole canvas: texture coordinates (0, 0) at the bottom left, (1, 1) at
' the top right, so the picture shows the right way up
Sub Square()
    glClear GL_COLOR_BUFFER_BIT
    glBegin GL_QUADS
    glTexCoord2f 0, 0: glVertex2f 0, 0
    glTexCoord2f 1, 0: glVertex2f 1, 0
    glTexCoord2f 1, 1: glVertex2f 1, 1
    glTexCoord2f 0, 1: glVertex2f 0, 1
    glEnd
    GLPresent
End Sub

Function CountColour(ByVal cv As Canvas, ByVal c As Long) As Long
    Dim x As Long, y As Long
    For y = 0 To cv.Height - 1
        For x = 0 To cv.Width - 1
            If cv.Point(x, y) = c Then CountColour = CountColour + 1
        Next
    Next
End Function
```

```output
checker: top left FFFFFF, next square C0
label: background A05A00, yellow text pixels 304 
error 0
```

- `GLTexImage w, h, px` takes `w * h` colours written `&HAARRGGBB` (alpha, red, green, blue),
  row by row from the top.
- `GLTexImageCanvas cv, img` takes a canvas image (0 = the back buffer).
- `GL_TEXTURE_MIN_FILTER` and `GL_TEXTURE_MAG_FILTER` say how a texture is shrunk and enlarged:
  `GL_NEAREST` keeps sharp pixels, `GL_LINEAR` blends them.
- Textures can be up to 1024 x 1024 pixels.

## Points on the canvas: GLProject

OpenGL draws no text, but the Canvas does, so a label is drawn with the Canvas at the place
where a 3D point appears. `GLProject(x, y, z, p)` works that out with the current matrices: it
fills `p(0)` and `p(1)` with canvas coordinates (from the top left, as `DrawText` wants), `p(2)`
with the depth (0 near, 1 far), and returns False when the point is behind the camera.

*Listing 22.5* (`examples/book/ch22-opengl/labels/labels.bbp`)

<!-- project: examples/book/ch22-opengl/labels/labels.bbp -->
```basic
' labels.bas - GLProject tells where a point of the 3D world appears on the canvas, so a label
' drawn with the Canvas can follow it
Option Explicit

Sub Main()
    Dim cv As Canvas, p(2) As Double, names As Variant, xs As Variant, i As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 200, 150
    GLAttach cv
    glEnable GL_DEPTH_TEST
    glMatrixMode GL_PROJECTION
    gluPerspective 60, 200 / 150, 1, 100
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    gluLookAt 0, 2, 8, 0, 0, 0, 0, 1, 0

    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    names = Array("left", "centre", "right")
    xs = Array(-3, 0, 3)
    For i = 0 To 2
        glPushMatrix                               ' save the camera's matrix
        glTranslatef xs(i), 0, 0
        glColor3f 0.3 + i * 0.3, 0.5, 1 - i * 0.3
        glutSolidCube 1
        glPopMatrix                                ' and put it back
    Next
    GLPresent
    For i = 0 To 2
        ' the top of each cube: where is it on the canvas?
        If GLProject(xs(i), 0.5, 0, p) Then
            cv.DrawText CLng(p(0)) - cv.TextWidth(names(i)) \ 2, CLng(p(1)) - 12, names(i), vbWhite
            Print names(i); " cube's top at"; CLng(p(0)); ","; CLng(p(1)); " depth "; Format$(p(2), "0.00")
        End If
    Next
    Print "behind the camera:"; GLProject(0, 0, 20, p)
End Sub
```

```output
left cube's top at 52 , 67  depth 0.89
centre cube's top at 100 , 67  depth 0.89
right cube's top at 148 , 67  depth 0.89
behind the camera:False
```

## Speed

OpenGL here draws in software, so each frame costs time for every point and every pixel. On
the QEMU emulator, where even the PowerPC's floating point is emulated, that matters a lot.
What helps most:

- **Display lists.** `glNewList list, GL_COMPILE` ... `glEndList` records OpenGL calls, and
  `glCallList list` replays them. A shape made of 500 `glVertex3f` calls costs 500 calls from
  BASIC each frame; in a list it costs one. Record everything that doesn't change shape.
- **Vertex arrays.** `glVertexPointer`, `glColorPointer`, `glNormalPointer` and
  `glTexCoordPointer` hand OpenGL whole arrays of numbers, and `glDrawArrays` or
  `glDrawElements` draws from them in one call. Recorded in a display list, a whole landscape
  is one call:

*Listing 22.6* (`examples/book/ch22-opengl/terrain/terrain.bbp`)

<!-- project: examples/book/ch22-opengl/terrain/terrain.bbp -->
```basic
' terrain.bas - a 17 x 17 grid of heights drawn with vertex arrays and glDrawElements, recorded
' once into a display list and then drawn from two places with one call each
Option Explicit

Const N = 17                     ' points along each side
Const SPACING = 1

Sub Main()
    Dim cv As Canvas, land As Long
    Dim verts(N * N * 3 - 1) As Single, cols(N * N * 3 - 1) As Single
    Dim idx((N - 1) * (N - 1) * 6 - 1) As Long
    Dim x As Long, z As Long, i As Long, k As Long, h As Single

    ' 1. the points: x and z on a grid round the origin, y a gentle hill; green low, brown high
    For z = 0 To N - 1
        For x = 0 To N - 1
            h = 2 * Cos((x - 8) / 4) * Cos((z - 8) / 5)
            i = (z * N + x) * 3
            verts(i) = (x - 8) * SPACING: verts(i + 1) = h: verts(i + 2) = (z - 8) * SPACING
            cols(i) = 0.2 + h * 0.15: cols(i + 1) = 0.6 - h * 0.1: cols(i + 2) = 0.2
        Next
    Next
    ' 2. two triangles for each square of the grid, as indices into the points
    For z = 0 To N - 2
        For x = 0 To N - 2
            i = z * N + x
            idx(k) = i: idx(k + 1) = i + N: idx(k + 2) = i + 1
            idx(k + 3) = i + 1: idx(k + 4) = i + N: idx(k + 5) = i + N + 1
            k = k + 6
        Next
    Next

    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 160, 120
    GLAttach cv
    glEnable GL_DEPTH_TEST
    glMatrixMode GL_PROJECTION
    gluPerspective 50, 160 / 120, 0.5, 60
    glMatrixMode GL_MODELVIEW

    ' 3. record the arrays into a display list: from now on the whole landscape is one call
    glVertexPointer 3, verts
    glColorPointer 3, cols
    glEnableClientState GL_VERTEX_ARRAY
    glEnableClientState GL_COLOR_ARRAY
    land = glGenLists(1)
    glNewList land, GL_COMPILE
    glDrawElements GL_TRIANGLES, k, idx
    glEndList
    glDisableClientState GL_VERTEX_ARRAY
    glDisableClientState GL_COLOR_ARRAY
    Print N * N; "points,"; k \ 3; "triangles in display list"; land

    ' 4. two views of the same list
    View cv, land, 0, 6, 14, "from the south"
    View cv, land, 14, 3, 0, "from the east"
    Print "error"; glGetError()
End Sub

Sub View(ByVal cv As Canvas, ByVal land As Long, ByVal ex As Double, ByVal ey As Double, ByVal ez As Double, ByVal title As String)
    glClearColor 0.5, 0.7, 1, 1                   ' sky
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    gluLookAt ex, ey, ez, 0, 0, 0, 0, 1, 0        ' eye, the point looked at, which way is up
    glCallList land
    GLPresent
    Print title; ": sky at the top "; IsBlue(cv.Point(80, 2)); ", land in the middle "; Not IsBlue(cv.Point(80, 80))
End Sub

' more blue than green (Point gives RGB() colours, &HBBGGRR)
Function IsBlue(ByVal c As Long) As Boolean
    IsBlue = (c \ &H10000) > ((c \ &H100) And &HFF)
End Function
```

```output
 289 points, 512 triangles in display list 1 
from the south: sky at the top True, land in the middle True
from the east: sky at the top True, land in the middle True
error 0
```

- **Keep the fast path.** OpenGL draws plain polygons fastest with the default depth test
  (`GL_LESS`) and without blending, alpha test or textures; textures and blending cost more per
  pixel. `glShadeModel GL_FLAT` where smooth shading doesn't show, and `glEnable GL_CULL_FACE`
  for closed shapes (the faces turned away aren't drawn).
- **No fog or blending in hot paths.** They take Mesa's slow general path (fog cost one example
  15 times its speed on the emulator); fade distant things by colouring them yourself.
- **Small pictures.** A 320 x 256 canvas shown at `scale=2` in the form looks big and costs a
  quarter of 640 x 512.

The examples `gl_cube`, `gl_shapes`, `gl_texture`, `gl_terrain`, `gl_boing` and `gl_starfield`
show each part of OpenGL in a window, and `gl_boing_rally` is a whole game. The full list of
functions is in the Boing BASIC source's `docs/opengl.md`.

# OpenGL: 3D with the OpenGL API

`Extension=opengl` gives a program OpenGL 1.x, the fixed-function API of countless tutorials,
books and games: matrices, lighting, materials, textures, fog, display lists, vertex arrays,
blending. It is Mesa 7.8.2's software renderer (OSMesa), so it needs no 3D hardware and runs
the same on every AmigaOS 4 machine, in QEMU, and on the host (macOS, Linux), where the tests
run. It draws straight into a [Canvas](graphics.md): a form's canvas or an off-screen one.

Use [Engine3D](engine3d.md) for an amiga3d-style game (integer maths, painter's algorithm,
a scene in a few dozen calls); use OpenGL when you want a depth buffer, real lighting,
textures, or to follow OpenGL material written for other systems.

```basic
' in the project (.bbp): Extension=opengl
Private angle As Double

Private Sub Form_Load()
    GLAttach view                          ' draw into the form's canvas
    glEnable GL_DEPTH_TEST
    glMatrixMode GL_PROJECTION
    gluPerspective 45, 320 / 256, 1, 100
    glMatrixMode GL_MODELVIEW
End Sub

Private Sub tick_Timer()
    glClearColor 0.1, 0.1, 0.2, 1
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    glTranslatef 0, 0, -5
    glRotatef angle, 1, 1, 0
    glBegin GL_TRIANGLES
    glColor3f 1, 0, 0: glVertex3f 0, 1, 0
    glColor3f 0, 1, 0: glVertex3f -1, -1, 0
    glColor3f 0, 0, 1: glVertex3f 1, -1, 0
    glEnd
    GLPresent                              ' GL is done: the canvas has the picture
    view.DrawText 4, 4, "angle " & CLng(angle)   ' Canvas drawing on top (a HUD), if you like
    view.Refresh                           ' show it, as for any canvas
    angle = angle + 3
End Sub
```

**Status: implemented (2026-11-13).** Tested natively, in the VM, with the JIT and in an
interpreter built with `STD_EXTS=opengl` (`tests/opengl`), on the host and on the QEMU OS4
guest. Examples: `examples/gl_*` (below).

## Using it

- **The project**: `Extension=opengl`. A single `.bas` file can't name an extension, so an
  OpenGL program is always a project.
- **`boing run` / AmiForge's Run**: the kit's interpreter has OpenGL built in (it is built
  with `STD_EXTS="sqlite opengl"`). A `boing` you built yourself without it stops with "this
  program needs the extension 'opengl'": build one with `make STD_EXTS=opengl` (host) or
  `tools/build-os4.sh STD_EXTS=opengl` (AmigaOS 4), or make one for the project with
  `boing vm --project P.bbp -o myboing`.
- **Native builds**: `boing build P.bbp` (host), `boing build P.bbp --target os4` (Docker
  cross build) or `boing build P.bbp` on the Amiga (SDK GCC) compile `ext/opengl/opengl.c` and
  link Mesa (`libOSMesa.a`, about 3 MB of code, beside `libboing.a`: `build/libOSMesa.a`,
  `build/os4/libOSMesa.a`, the kit's `lib/`). A native OpenGL program is 3 MB larger than
  another.
- **Building Mesa**: `make opengl` (host; downloads the Mesa 7.8.2 source once, checks its
  SHA-256, builds in about 3 s) and `third_party/mesa/build.sh os4` (Docker; `tools/build-os4.sh`
  runs it when needed). See `third_party/mesa/build.sh`.
- **Stack**: Mesa's span functions keep big stack frames. The descriptor says `stack 1048576`,
  so a native program that uses OpenGL gets at least 1 MB of stack (`Stack=` can give it more).
  The kit's `boing` has a 1 MB stack too.

## The context: GLAttach, GLPresent

| | |
|---|---|
| `GLAttach canvas` | draw into this Canvas: its current target (the back buffer, or an image made the target with `SetTarget`). Sets the viewport to the canvas size the first time and whenever the size changes. One context per program; attaching another canvas moves it. |
| `GLPresent` | waits until GL has finished drawing. Then draw a HUD with the Canvas methods if you like, and `Refresh` the canvas to show it. |
| `GLDetach` | stop drawing into the canvas (it is released) |
| `GLWidth()`, `GLHeight()` | the size of the attached canvas |
| `GLVersion()` | Mesa's version string ("2.1 Mesa 7.8.2") |

GL draws into the canvas's pixels directly; there is no copy. `glClear` and `GLPresent` notice
when the canvas's target or size has changed (`Resize`, `SetTarget`) and follow it.

The largest picture is **1024 x 1024** (the canvas, and each texture). `GLAttach` raises
error 5 for a bigger canvas. Software rendering costs time per pixel: games on the QEMU guest
use 320 x 256 shown at `scale=2`, as the examples do.

## Functions

Every name below is called like a built-in Sub or Function (`glEnable GL_LIGHTING`,
`n = glGenLists(1)`), with the arguments of the C function. Numbers are converted (a Double
for each GLfloat/GLdouble, a Long for each GLenum/GLint/GLuint, a Boolean for GLboolean). The
constants are the `GL_` names of `gl.h` (more than 800, OpenGL 1.0-1.3 plus the extensions
Mesa implements), and `boing check` knows every one: a misspelt function or constant is a
compile error.

**State**: `glEnable`, `glDisable`, `glIsEnabled`, `glClear`, `glClearColor`, `glClearDepth`,
`glClearStencil`, `glDepthFunc`, `glDepthMask`, `glDepthRange`, `glShadeModel`, `glCullFace`,
`glFrontFace`, `glPolygonMode`, `glPolygonOffset`, `glBlendFunc`, `glAlphaFunc`, `glLogicOp`,
`glColorMask`, `glLineWidth`, `glLineStipple`, `glPointSize`, `glHint`, `glScissor`,
`glStencilFunc`, `glStencilOp`, `glStencilMask`, `glPushAttrib`, `glPopAttrib`, `glFlush`,
`glFinish`, `glGetError`, `glGetString`, `glGetInteger(pname)`, `glGetFloat(pname, index)`.

**Matrices**: `glMatrixMode`, `glLoadIdentity`, `glPushMatrix`, `glPopMatrix`, `glTranslatef`,
`glRotatef` (degrees), `glScalef`, `glFrustum`, `glOrtho`, `glViewport`, `glLoadMatrixf m`,
`glMultMatrixf m` (16 numbers, column by column), `GLGetMatrix pname, m` (fills a Single or
Double array of 16, e.g. `GL_MODELVIEW_MATRIX`).

**Drawing**: `glBegin`, `glEnd`, `glVertex2f`, `glVertex3f`, `glVertex4f`, `glColor3f`,
`glColor4f`, `glColor3ub`, `glColor4ub`, `glColorRGB vbColour` (an `RGB()` colour or a `vb`
colour constant), `glNormal3f`, `glTexCoord2f`, `glRectf`, `glEdgeFlag`.

**Lighting and fog**: `glLightf`, `glLight4f light, pname, a, b, c, d` (`GL_POSITION`,
`GL_DIFFUSE`... four values), `glLightfv light, pname, arr`, `glLightModelf`, `glLightModeli`,
`glLightModel4f`, `glMaterialf`, `glMaterial4f`, `glMaterialfv`, `glColorMaterial`, `glFogf`,
`glFogi`, `glFog4f` (`GL_FOG_COLOR`).

**Textures**: `glGenTexture()` (one name), `glDeleteTexture t`, `glBindTexture`,
`glTexParameteri`, `glTexParameterf`, `glTexEnvi`, `glTexEnvf`, `glTexEnv4f`, `glTexGeni`,
`glTexGen4f`, `glIsTexture`, and two ways to fill the bound `GL_TEXTURE_2D`:

| | |
|---|---|
| `GLTexImage w, h, pixels` | from an array of `w * h` colours `&HAARRGGBB` (Long), row by row from the top. A 2-D array `px(x, y)` is stored x fastest, so it works as it is. |
| `GLTexImageCanvas canvas, image` | from a canvas image (`image` = an id from `CreateImage`/`LoadImage`, 0 = the back buffer): draw a texture with the Canvas methods, text included |

The picture's top row is texture coordinate t = 1 and its bottom row t = 0, so with the usual
coordinates ((0, 0) at a face's bottom left, (1, 1) at its top right, as on `glutSolidCube`'s
faces) it shows the right way up. Sizes up to 1024 x 1024; any size works (power-of-two sizes are fastest).
`glTexParameteri GL_TEXTURE_2D, GL_GENERATE_MIPMAP, GL_TRUE` before the upload makes mipmaps.

**Display lists**: `glGenLists`, `glNewList`, `glEndList`, `glCallList`, `glDeleteLists`,
`glIsList`. Record static geometry once (`GL_COMPILE`) and draw it with one call a frame: from
BASIC that turns thousands of calls into one, and is the most important speed-up.

**Vertex arrays**: `glVertexPointer size, arr`, `glColorPointer size, arr`,
`glNormalPointer arr`, `glTexCoordPointer size, arr`, `glEnableClientState`,
`glDisableClientState`, `glDrawArrays mode, first, count`, `glDrawElements mode, count,
indices`, `glArrayElement`. The arrays are BASIC arrays of numbers (Single is fastest; any
numeric type works); each pointer function copies its array, so change the array and call it
again to change the data. Indices past the end of the vertex array raise error 9 instead of
reading memory that isn't there.

**GLU**: `gluPerspective fovy, aspect, zNear, zFar`, `gluLookAt eye, centre, up` (9 numbers),
`gluOrtho2D`, and `GLProject(x, y, z, r)`: where a world point lands on the canvas, in canvas
pixels from the top left, for labels drawn with the Canvas: `r(0)` = x, `r(1)` = y, `r(2)` =
depth 0..1 (a Single, Double or Long array of 3 or more); False when the point is behind the
camera.

**Shapes** (GLUT's, with normals; the sphere and cube also with texture coordinates; z is the
axis of the sphere, torus, cone and cylinder): `glutSolidCube size`, `glutWireCube`,
`glutSolidSphere radius, slices, stacks`, `glutWireSphere`, `glutSolidTorus inner, outer,
sides, rings`, `glutWireTorus`, `glutSolidCone base, height, slices, stacks`, `glutWireCone`,
`glutSolidCylinder radius, height, slices, stacks`, and `glutSolidCheckerSphere radius,
slices, stacks, colour1, colour2` (a checkerboard ball in two `RGB()` colours: the Boing ball).

Not there: GLSL shaders (Mesa's GLSL compiler isn't built; ARB vertex/fragment programs
work), `glReadPixels` (read the canvas: `Point`, `Hash`, `SaveImage`), feedback/selection
buffers, evaluators, and fonts (draw text with the Canvas after `GLPresent`).

## Speed

The renderer is software, and on the QEMU guest the PowerPC FPU is emulated too, so a frame
costs per vertex and per pixel:

- **Display lists** for everything that doesn't change shape. A BASIC loop of `glVertex3f`
  calls costs one call each frame per vertex; a display list costs one call.
- **`glDepthFunc GL_LESS`** (the default), 16-bit depth, no blending, no alpha test, no
  texture: OSMesa then uses its fast triangle functions (about 20 times faster for big flat
  polygons). `glShadeModel GL_FLAT` where it looks right.
- **Cull back faces** (`glEnable GL_CULL_FACE`) of closed shapes.
- Few vertices: a sphere of 16 x 12 is plenty at 320 x 256.
- Small canvases shown scaled (`scale=2` in the form) rather than big ones.

Numbers: `examples/gl_boing_rally` and the `gl_*` READMEs list fps on the guest.

## Examples

| | |
|---|---|
| `examples/gl_cube` | the smallest: a spinning colour cube |
| `examples/gl_shapes` | lighting and materials on the GLUT shapes; flat/smooth, lighting and wireframe toggles |
| `examples/gl_texture` | textures from a BASIC array and from Canvas drawing |
| `examples/gl_terrain` | a landscape in vertex arrays and a display list, with fog |
| `examples/gl_boing` | the bouncing checkered ball |
| `examples/gl_starfield` | points, lines and blending |
| `examples/gl_boing_rally` | a game: steer the Boing ball along a sky road |

## How it is built

- `ext/opengl/opengl.c` is the extension: the context (OSMesa bound to the canvas's pixels:
  `OSMESA_ARGB` on big-endian PowerPC, `OSMESA_BGRA` on little-endian hosts, so the bytes match
  the canvas's 0xAARRGGBB words, with `OSMESA_Y_UP` 0 so row 0 is the top), the functions that
  take arrays, GLU and the shapes.
- `tools/gen-opengl.py` writes `opengl_gen.h` (the plain wrappers and their registration) and
  `opengl.bbx` (every function, the `GL_` constants of `GL/gl.h`, `link OSMesa`, `stack
  1048576`). `make test` checks they are up to date. To add a plain function, add a line to
  its table and run it.
- `third_party/mesa`: `build.sh`, the Makefile (Mesa's own source lists; no GLSL compiler:
  `shims/slang_stub.c`), and `patches/max-1024.patch`, which caps the viewport and textures at
  1024 so the span functions' stack frames are a quarter of Mesa's default size
  (`_swrast_texture_span` 390 KB -> 99 KB). Mesa is MIT licensed.
- The compiler's support for it is general: `.bbx` `const` and `stack` lines, extension Subs
  called as statements, and array variables passed to an extension's Variant parameters by
  reference ([extensions](extensions.md)).

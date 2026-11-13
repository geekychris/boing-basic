' OpenGL Terrain: a landscape flown over in a circle. The ground is a grid of heights made
' once from a few sine waves; its corners, colours and normals go into arrays, which
' glDrawElements draws as triangles into display lists. Each frame then costs one
' glCallList: the BASIC program only moves the camera.
'
' Software OpenGL on the Amiga does the lighting and the fog for every vertex and pixel of
' every frame, so they are what costs. The sun never moves here, so by default its light is
' worked out once in BASIC and baked into the vertex colours. L switches to OpenGL's own
' lighting (a second list with the plain colours and the normals); F turns on OpenGL's fog,
' which looks good but is its slowest path: on the QEMU guest ~0.5 s a frame instead of ~30 ms.
' Esc ends; "--frames N" ends after N frames and prints a checksum of the last picture
' ("--light" and "--fog" start with those on).
Option Explicit

Const N = 32                                 ' cells along each side (N + 1 corners)
Const CELL = 4                               ' world units per cell

Private t As Long, maxFrames As Long, t0 As Double, busy As Double
Private baked As Long, litLand As Long       ' the two display lists
Private fog As Boolean, lit As Boolean, fWas As Boolean, lWas As Boolean

' the height of the ground at grid corner (i, j); 0 is sea level
Private Function Height(ByVal i As Long, ByVal j As Long) As Double
    Dim h As Double
    h = 8 * Sin(i * 0.25) * Cos(j * 0.22) + 3.5 * Sin((i + j) * 0.45) + 1.5 * Cos(i * 0.8 - j * 0.5) + 3
    If h < 0 Then h = 0                      ' the sea is flat
    Height = h
End Function

Private Sub BuildLand()
    Dim nv As Long, i As Long, j As Long, k As Long, q As Long
    Dim h As Double, hx As Double, hz As Double, l As Double, sun As Double
    Dim r As Double, g As Double, b As Double, nx As Double, ny As Double, nz As Double
    Dim v() As Single, c() As Single, cb() As Single, nrm() As Single, idx() As Long
    nv = (N + 1) * (N + 1)
    ReDim v(nv * 3 - 1), c(nv * 3 - 1), cb(nv * 3 - 1), nrm(nv * 3 - 1), idx(N * N * 6 - 1)
    For j = 0 To N
        For i = 0 To N
            k = j * (N + 1) + i
            h = Height(i, j)
            v(k * 3) = (i - N / 2) * CELL
            v(k * 3 + 1) = h
            v(k * 3 + 2) = (j - N / 2) * CELL
            ' the normal from the slopes to the neighbours
            hx = Height(i + 1, j) - Height(i - 1, j)
            hz = Height(i, j + 1) - Height(i, j - 1)
            l = Sqr(hx * hx + 4 * CELL * CELL + hz * hz)
            nx = -hx / l: ny = 2 * CELL / l: nz = -hz / l
            ' the colour by height: sea, sand, grass, rock, snow
            If h <= 0 Then
                r = 0.15: g = 0.3: b = 0.7
                nx = 0: ny = 1: nz = 0
            ElseIf h < 1 Then
                r = 0.85: g = 0.8: b = 0.5
            ElseIf h < 7.5 Then
                r = 0.25: g = 0.65 - h * 0.03: b = 0.2
            ElseIf h < 11 Then
                r = 0.5: g = 0.45: b = 0.4
            Else
                r = 0.95: g = 0.95: b = 1
            End If
            nrm(k * 3) = nx: nrm(k * 3 + 1) = ny: nrm(k * 3 + 2) = nz
            c(k * 3) = r: c(k * 3 + 1) = g: c(k * 3 + 2) = b
            ' the sun (direction -0.4, 1, 0.3) baked in: ambient 0.35 + diffuse
            sun = (-0.4 * nx + ny + 0.3 * nz) / 1.1
            If sun < 0 Then sun = 0
            sun = 0.35 + 0.65 * sun
            cb(k * 3) = r * sun: cb(k * 3 + 1) = g * sun: cb(k * 3 + 2) = b * sun
        Next
    Next
    ' two triangles per cell, counter-clockwise seen from above
    For j = 0 To N - 1
        For i = 0 To N - 1
            k = j * (N + 1) + i
            idx(q) = k: idx(q + 1) = k + N + 1: idx(q + 2) = k + 1
            idx(q + 3) = k + 1: idx(q + 4) = k + N + 1: idx(q + 5) = k + N + 2
            q = q + 6
        Next
    Next
    glEnableClientState GL_VERTEX_ARRAY
    glEnableClientState GL_COLOR_ARRAY
    glVertexPointer 3, v

    baked = glGenLists(2)                    ' a list keeps its own copy of the triangles
    glColorPointer 3, cb
    glNewList baked, GL_COMPILE
    glDrawElements GL_TRIANGLES, N * N * 6, idx
    glEndList

    litLand = baked + 1                      ' plain colours and normals, for OpenGL's lighting
    glColorPointer 3, c
    glNormalPointer nrm
    glEnableClientState GL_NORMAL_ARRAY
    glNewList litLand, GL_COMPILE
    glDrawElements GL_TRIANGLES, N * N * 6, idx
    glEndList
    glDisableClientState GL_VERTEX_ARRAY
    glDisableClientState GL_COLOR_ARRAY
    glDisableClientState GL_NORMAL_ARRAY
End Sub

Private Sub Form_Load()
    GLAttach view
    glEnable GL_DEPTH_TEST
    glEnable GL_CULL_FACE
    glShadeModel GL_FLAT                     ' one colour per triangle: crisp facets, and faster
    glMatrixMode GL_PROJECTION
    gluPerspective 55, 320 / 256, 1, 90
    glMatrixMode GL_MODELVIEW
    glClearColor 0.55, 0.7, 0.9, 1           ' the sky, and the fog the same colour
    glFogi GL_FOG_MODE, GL_LINEAR
    glFogf GL_FOG_START, 30
    glFogf GL_FOG_END, 85
    glFog4f GL_FOG_COLOR, 0.55, 0.7, 0.9, 1
    glEnable GL_LIGHT0
    glEnable GL_COLOR_MATERIAL               ' the vertex colours are the material
    glColorMaterial GL_FRONT, GL_AMBIENT_AND_DIFFUSE
    glLightModel4f GL_LIGHT_MODEL_AMBIENT, 0.35, 0.35, 0.35, 1
    BuildLand
    fog = InStr(Command$(), "--fog") > 0
    lit = InStr(Command$(), "--light") > 0
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
    t0 = Timer
End Sub

Private Sub tick_Timer()
    Dim ts As Double, a As Double, ex As Double, ez As Double
    ts = Timer
    If view.KeyDown(vbKeyF) And Not fWas Then fog = Not fog
    fWas = view.KeyDown(vbKeyF)
    If view.KeyDown(vbKeyL) And Not lWas Then lit = Not lit
    lWas = view.KeyDown(vbKeyL)
    If fog Then glEnable GL_FOG Else glDisable GL_FOG

    a = t * 0.012                            ' the camera goes round a circle, looking ahead
    ex = 34 * Cos(a): ez = 34 * Sin(a)
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    gluLookAt ex, 28, ez, 34 * Cos(a + 0.9), 0, 34 * Sin(a + 0.9), 0, 1, 0
    If lit Then
        glLight4f GL_LIGHT0, GL_POSITION, -0.4, 1, 0.3, 0     ' sunlight, fixed in the world
        glEnable GL_LIGHTING
        glCallList litLand
        glDisable GL_LIGHTING
    Else
        glCallList baked
    End If
    GLPresent
    view.DrawText 4, 4, "OpenGL Terrain", RGB(20, 30, 60)
    view.DrawText 4, 243, "L light " & IIf(lit, "OpenGL", "baked") & "  F fog " & IIf(fog, "on (slow)", "off"), RGB(20, 30, 60)
    view.Refresh
    t = t + 1
    busy = busy + Timer - ts
    If maxFrames > 0 And t >= maxFrames Then
        Print "frames"; t; "hash "; Hex$(view.Hash)
        Print "fps "; Format$(t / (Timer - t0 + 0.001), "0.0"); ", "; Format$(busy * 1000 / t, "0.0"); " ms a frame drawing"
        Unload Me
    ElseIf view.KeyDown(vbKeyEscape) Then
        Unload Me
    End If
End Sub

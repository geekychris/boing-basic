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

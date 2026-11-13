' tests/opengl/basics: what the OpenGL extension draws, read back through the canvas
Option Explicit

Private Function Hex6(ByVal c As Long) As String
    Hex6 = Right$("000000" & Hex$(c And &HFFFFFF), 6)
End Function

Sub Main()
    Dim cv As Object, i As Long, lst As Long, r(2) As Double
    Dim v(8) As Single, cols(11) As Single, idx(2) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 64, 48
    GLAttach cv
    Print "size"; GLWidth(); GLHeight()
    Print "version "; Left$(glGetString(GL_VERSION), 3)
    Print "renderer "; glGetString(GL_RENDERER)

    ' clear: the canvas sees the colour (0xRRGGBB in Point)
    glClearColor 0, 0, 1, 1
    glClear GL_COLOR_BUFFER_BIT
    GLPresent
    Print "clear "; Hex6(cv.Point(10, 10))

    ' a red quad over the left half, orthographic, pixel units, y down like the canvas
    glMatrixMode GL_PROJECTION
    glLoadIdentity
    glOrtho 0, 64, 48, 0, -1, 1
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    glColor3f 1, 0, 0
    glBegin GL_QUADS
    glVertex2f 0, 0: glVertex2f 32, 0: glVertex2f 32, 48: glVertex2f 0, 48
    glEnd
    GLPresent
    Print "quad "; Hex6(cv.Point(5, 5)); " "; Hex6(cv.Point(40, 5))

    ' depth: a far green quad drawn after a near yellow one stays behind
    glEnable GL_DEPTH_TEST
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glColorRGB RGB(255, 255, 0)
    glBegin GL_TRIANGLES
    glVertex3f 0, 0, 0.5: glVertex3f 64, 0, 0.5: glVertex3f 0, 48, 0.5
    glEnd
    glColor3ub 0, 255, 0
    glBegin GL_QUADS
    glVertex3f 0, 0, -0.5: glVertex3f 64, 0, -0.5: glVertex3f 64, 48, -0.5: glVertex3f 0, 48, -0.5
    glEnd
    GLPresent
    Print "depth "; Hex6(cv.Point(2, 2)); " "; Hex6(cv.Point(62, 46))
    glDisable GL_DEPTH_TEST

    ' vertex arrays + colour array + glDrawElements
    v(0) = 0: v(1) = 0: v(2) = 0
    v(3) = 64: v(4) = 0: v(5) = 0
    v(6) = 0: v(7) = 48: v(8) = 0
    For i = 0 To 2: cols(i * 4) = 1: cols(i * 4 + 1) = 0.5: cols(i * 4 + 2) = 0: cols(i * 4 + 3) = 1: Next
    idx(0) = 0: idx(1) = 1: idx(2) = 2
    glClear GL_COLOR_BUFFER_BIT
    glVertexPointer 3, v
    glColorPointer 4, cols
    glEnableClientState GL_VERTEX_ARRAY
    glEnableClientState GL_COLOR_ARRAY
    glDrawElements GL_TRIANGLES, 3, idx
    glDisableClientState GL_COLOR_ARRAY
    GLPresent
    Print "arrays "; Hex6(cv.Point(4, 4)); " "; Hex6(cv.Point(60, 44))

    ' display list
    lst = glGenLists(1)
    glNewList lst, GL_COMPILE
    glColor3f 1, 1, 1
    glRectf 10, 10, 20, 20
    glEndList
    glClear GL_COLOR_BUFFER_BIT
    glCallList lst
    GLPresent
    Print "list "; glIsList(lst); " "; Hex6(cv.Point(15, 15)); " "; Hex6(cv.Point(25, 15))

    ' perspective + GLProject: the origin 5 units ahead lands at the centre
    glMatrixMode GL_PROJECTION
    glLoadIdentity
    gluPerspective 60, 64 / 48, 1, 100
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    gluLookAt 0, 0, 5, 0, 0, 0, 0, 1, 0
    Print "project "; GLProject(0, 0, 0, r); CLng(r(0)); CLng(r(1)); r(2) > 0 And r(2) < 1
    Print "behind "; GLProject(0, 0, 10, r)

    ' a lit sphere: the side towards the light is brighter than the far side
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glEnable GL_DEPTH_TEST
    glEnable GL_LIGHTING
    glEnable GL_LIGHT0
    glLight4f GL_LIGHT0, GL_POSITION, -1, 0, 1, 0
    glMaterial4f GL_FRONT, GL_DIFFUSE, 1, 1, 1, 1
    glutSolidSphere 1.5, 24, 16
    GLPresent
    Print "lit "; (cv.Point(24, 24) And &HFF) > (cv.Point(40, 24) And &HFF)
    Print "error"; glGetError()
    GLDetach
End Sub

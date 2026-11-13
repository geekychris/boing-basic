' OpenGL Boing: a red and white checkered ball spins and bounces in front of a grid wall,
' throwing a shadow on it. The ball (glutSolidCheckerSphere), the grid and the shadow disc are
' display lists made once; each frame only places them. Esc ends; "--frames N" ends after N
' frames and prints a checksum of the last picture.
Option Explicit

Const WALLZ = -4                             ' the wall's depth; the floor is at y = -3

Private t As Long, maxFrames As Long, t0 As Double, busy As Double
Private ball As Long, grid As Long, shadow As Long
Private bx As Double, vx As Double

Private Sub MakeLists()
    Dim i As Long, a As Double
    ball = glGenLists(3)
    grid = ball + 1
    shadow = ball + 2

    glNewList ball, GL_COMPILE               ' poles on z: turned upright and tilted when drawn
    glutSolidCheckerSphere 1.2, 16, 8, RGB(220, 20, 20), RGB(245, 245, 245)
    glEndList

    glNewList grid, GL_COMPILE               ' purple lines: the wall, then the floor
    glColor3f 0.6, 0.2, 0.6
    glBegin GL_LINES
    For i = -6 To 6
        glVertex3f i, -3, WALLZ: glVertex3f i, 4, WALLZ
    Next
    For i = -3 To 4
        glVertex3f -6, i, WALLZ: glVertex3f 6, i, WALLZ
    Next
    For i = -6 To 6
        glVertex3f i, -3, WALLZ: glVertex3f i * 1.6, -3, 4
    Next
    For i = 0 To 4
        glVertex3f -6 - i * 0.6, -3, WALLZ + i * 2: glVertex3f 6 + i * 0.6, -3, WALLZ + i * 2
    Next
    glEnd
    glEndList

    glNewList shadow, GL_COMPILE             ' a dark disc of radius 1 in the x-y plane
    glColor3f 0.4, 0.4, 0.45
    glBegin GL_TRIANGLE_FAN
    glVertex3f 0, 0, 0
    For i = 0 To 20
        a = i * 6.2831853 / 20
        glVertex3f Cos(a), Sin(a), 0
    Next
    glEnd
    glEndList
End Sub

Private Sub Form_Load()
    GLAttach view
    glEnable GL_DEPTH_TEST
    glMatrixMode GL_PROJECTION
    gluPerspective 50, 320 / 256, 1, 40
    glMatrixMode GL_MODELVIEW
    glClearColor 0.72, 0.72, 0.75, 1
    glShadeModel GL_FLAT
    glLight4f GL_LIGHT0, GL_POSITION, -0.4, 0.6, 1, 0
    glLightModel4f GL_LIGHT_MODEL_AMBIENT, 0.45, 0.45, 0.45, 1
    glEnable GL_LIGHT0
    glColorMaterial GL_FRONT, GL_AMBIENT_AND_DIFFUSE   ' the checker colours are the material
    glEnable GL_COLOR_MATERIAL
    MakeLists
    bx = -3: vx = 0.06
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
    t0 = Timer
End Sub

Private Sub tick_Timer()
    Dim ts As Double, by As Double, ph As Double
    ts = Timer
    ' left and right at a steady speed; up and down on a bounce (a parabola per hop)
    bx = bx + vx
    If bx > 3.6 Or bx < -3.6 Then vx = -vx
    ph = (t Mod 50) / 50
    by = -1.8 + 4 * 4 * ph * (1 - ph)

    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    glTranslatef 0, -0.3, -9
    glDisable GL_LIGHTING
    glCallList grid
    glPushMatrix                             ' the shadow: on the wall, down and to the right
    glTranslatef bx + 0.7, by - 0.4, WALLZ + 0.01
    glScalef 1.2, 1.2, 1
    glCallList shadow
    glPopMatrix
    glEnable GL_LIGHTING
    glPushMatrix
    glTranslatef bx, by, 0
    glRotatef 18, 0, 0, 1                    ' the tilt
    glRotatef -90, 1, 0, 0                   ' poles up
    glRotatef IIf(vx > 0, -1, 1) * t * 4, 0, 0, 1   ' spin the way it travels
    glCallList ball
    glPopMatrix
    GLPresent
    view.DrawText 4, 4, "OpenGL Boing", RGB(60, 20, 60)
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

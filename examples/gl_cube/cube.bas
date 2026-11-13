' OpenGL Cube: the smallest OpenGL program. A cube with a different colour on each face
' turns in front of the camera. Esc or closing the window ends it; "--frames N" ends after
' N frames and prints a checksum of the last picture (the tests use it).
Option Explicit

Private t As Long, maxFrames As Long, t0 As Double, busy As Double

Private Sub Form_Load()
    GLAttach view                            ' OpenGL draws into the canvas from now on
    glEnable GL_DEPTH_TEST                   ' near faces hide far ones
    glMatrixMode GL_PROJECTION               ' the camera lens: 45 degrees, 320 x 256
    gluPerspective 45, 320 / 256, 1, 50
    glMatrixMode GL_MODELVIEW
    glClearColor 0.05, 0.05, 0.2, 1
    If InStr(Command$(), "--frames") > 0 Then maxFrames = Val(Mid$(Command$(), InStr(Command$(), "--frames") + 8))
    t0 = Timer
End Sub

Private Sub tick_Timer()
    Dim ts As Double
    ts = Timer
    glClear GL_COLOR_BUFFER_BIT Or GL_DEPTH_BUFFER_BIT
    glLoadIdentity
    glTranslatef 0, 0, -6                    ' move the cube away from the camera
    glRotatef t * 2, 1, 0, 0                 ' and turn it (by frame, so every run is the same)
    glRotatef t * 3, 0, 1, 0

    glBegin GL_QUADS
    glColor3f 1, 0, 0                        ' front
    glVertex3f -1, -1, 1: glVertex3f 1, -1, 1: glVertex3f 1, 1, 1: glVertex3f -1, 1, 1
    glColor3f 0, 1, 0                        ' back
    glVertex3f -1, -1, -1: glVertex3f -1, 1, -1: glVertex3f 1, 1, -1: glVertex3f 1, -1, -1
    glColor3f 0, 0, 1                        ' top
    glVertex3f -1, 1, -1: glVertex3f -1, 1, 1: glVertex3f 1, 1, 1: glVertex3f 1, 1, -1
    glColor3f 1, 1, 0                        ' bottom
    glVertex3f -1, -1, -1: glVertex3f 1, -1, -1: glVertex3f 1, -1, 1: glVertex3f -1, -1, 1
    glColor3f 1, 0, 1                        ' right
    glVertex3f 1, -1, -1: glVertex3f 1, 1, -1: glVertex3f 1, 1, 1: glVertex3f 1, -1, 1
    glColor3f 0, 1, 1                        ' left
    glVertex3f -1, -1, -1: glVertex3f -1, -1, 1: glVertex3f -1, 1, 1: glVertex3f -1, 1, -1
    glEnd

    GLPresent                                ' OpenGL has finished the picture
    view.DrawText 4, 4, "OpenGL Cube", vbWhite
    view.Refresh                             ' show it
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

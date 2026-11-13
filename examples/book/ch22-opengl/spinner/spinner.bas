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

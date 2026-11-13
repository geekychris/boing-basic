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

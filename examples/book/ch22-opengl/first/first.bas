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

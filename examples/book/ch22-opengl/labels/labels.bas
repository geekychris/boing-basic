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

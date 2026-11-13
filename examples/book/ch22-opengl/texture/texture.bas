' texture.bas - two textures on a square that fills the canvas: one from an array of colours,
' one drawn with the Canvas methods (a picture with text) into an image
Option Explicit

Sub Main()
    Dim cv As Canvas, px(63) As Long, x As Long, y As Long, checker As Long, label As Long, img As Long

    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 128, 128
    GLAttach cv
    glMatrixMode GL_PROJECTION
    glLoadIdentity
    gluOrtho2D 0, 1, 0, 1
    glMatrixMode GL_MODELVIEW
    glLoadIdentity
    glEnable GL_TEXTURE_2D

    ' 1. an 8 x 8 checkerboard: colours &HAARRGGBB, row by row from the top
    For y = 0 To 7
        For x = 0 To 7
            If (x + y) Mod 2 = 0 Then px(y * 8 + x) = &HFFFFFFFF Else px(y * 8 + x) = &HFFC00000
        Next
    Next
    checker = glGenTexture()
    glBindTexture GL_TEXTURE_2D, checker
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST   ' sharp squares
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST
    GLTexImage 8, 8, px
    Square
    Print "checker: top left "; Hex$(cv.Point(4, 4)); ", next square "; Hex$(cv.Point(20, 4))

    ' 2. a texture drawn with the Canvas: an image of 64 x 64, then text on it
    img = cv.CreateImage(64, 64)
    cv.SetTarget img
    cv.Box 0, 0, 64, 64, RGB(0, 90, 160)
    cv.DrawText 8, 28, "BOING", vbYellow
    cv.SetTarget 0
    label = glGenTexture()
    glBindTexture GL_TEXTURE_2D, label
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST
    glTexParameteri GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST
    GLTexImageCanvas cv, img
    Square
    Print "label: background "; Hex$(cv.Point(4, 4)); ", yellow text pixels"; CountColour(cv, vbYellow)
    Print "error"; glGetError()
End Sub

' a square over the whole canvas: texture coordinates (0, 0) at the bottom left, (1, 1) at
' the top right, so the picture shows the right way up
Sub Square()
    glClear GL_COLOR_BUFFER_BIT
    glBegin GL_QUADS
    glTexCoord2f 0, 0: glVertex2f 0, 0
    glTexCoord2f 1, 0: glVertex2f 1, 0
    glTexCoord2f 1, 1: glVertex2f 1, 1
    glTexCoord2f 0, 1: glVertex2f 0, 1
    glEnd
    GLPresent
End Sub

Function CountColour(ByVal cv As Canvas, ByVal c As Long) As Long
    Dim x As Long, y As Long
    For y = 0 To cv.Height - 1
        For x = 0 To cv.Width - 1
            If cv.Point(x, y) = c Then CountColour = CountColour + 1
        Next
    Next
End Function

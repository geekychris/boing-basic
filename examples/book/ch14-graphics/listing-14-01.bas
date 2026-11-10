Option Explicit

Sub Main()
    Dim cv As Canvas
    Set cv = CreateObject("Boing.Canvas")
    Print "new canvas:"; cv.Width; "x"; cv.Height
    cv.Resize 160, 100
    cv.Cls RGB(0, 0, 64)
    cv.Box 10, 10, 40, 30, vbRed
    cv.Circle 100, 50, 20, vbYellow, True
    cv.Line 0, 99, 159, 0, vbWhite
    cv.DrawText 4, 88, "HELLO", vbGreen
    Print "pixel in the box: &H"; Hex$(cv.Point(20, 20))
    Print "pixel in the disc: &H"; Hex$(cv.Point(100, 50))
    Print "outside:"; cv.Point(200, 0)
    Print "hash:"; cv.Hash
End Sub

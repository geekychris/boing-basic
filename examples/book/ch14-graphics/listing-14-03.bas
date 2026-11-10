Option Explicit

Sub Main()
    Dim cv As Canvas, c As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 32, 32
    cv.Cls vbWhite
    cv.Alpha = 128                     ' half see-through
    cv.Box 0, 0, 16, 16, vbBlack       ' a shadow
    cv.Alpha = 255                     ' back to solid drawing
    c = cv.Point(4, 4)
    Print "red"; c And &HFF; " green"; (c \ &H100) And &HFF; " blue"; (c \ &H10000) And &HFF
    Print "outside the shadow: &H"; Hex$(cv.Point(20, 20))
End Sub

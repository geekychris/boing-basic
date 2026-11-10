Option Explicit

Sub Main()
    Dim cv As Canvas
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 120, 40
    Print "TextWidth(""SCORE 100"") ="; cv.TextWidth("SCORE 100")
    Print "TextHeight ="; cv.TextHeight()
    cv.CurrentX = 2: cv.CurrentY = 2
    cv.Print "line one"
    cv.Print "line two"
    Print "after two Prints: CurrentX"; cv.CurrentX; " CurrentY"; cv.CurrentY
    cv.DrawText 2, 25, "abc"
    Print "after DrawText: CurrentX"; cv.CurrentX
    cv.DrawTextScaled 60, 2, "BIG", vbYellow, 3
    Print "hash"; cv.Hash
End Sub

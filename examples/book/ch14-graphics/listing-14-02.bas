Option Explicit

Const N As Long = 200

Sub Main()
    Dim cv As Canvas, i As Long, f As Long
    Dim sx(0 To N - 1) As Long, sy(0 To N - 1) As Long, col(0 To N - 1) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 200
    Rnd -1: Randomize 7                      ' the same stars every run
    For i = 0 To N - 1
        sx(i) = Int(Rnd * 320): sy(i) = Int(Rnd * 200)
        col(i) = RGB(100 + i Mod 156, 100 + i Mod 156, 255)
    Next i
    For f = 1 To 50                          ' 50 frames of a scrolling starfield
        For i = 0 To N - 1
            sx(i) = (sx(i) + 1 + i Mod 3) Mod 320
        Next i
        cv.Cls
        cv.PSetMany sx, sy, col, N           ' all the stars in one call
        cv.Refresh
    Next f
    Print "frames"; cv.Frames; " hash"; cv.Hash
End Sub

' Engine3D demo, off-screen: draw N frames (default 200) and print the frame rate and the
' last picture's hash. Usage: boing run Bench.bbp [frames]
Option Explicit

Sub Main()
    Dim cv As Object, n As Long, i As Long, t0 As Double, dt As Double
    n = Val(Command$())
    If n <= 0 Then n = 200
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 256
    SceneInit cv
    t0 = Timer
    For i = 0 To n - 1
        SceneFrame cv, i
    Next i
    dt = Timer - t0
    If dt <= 0 Then dt = 0.001
    Print "frames"; n; " seconds "; Format$(dt, "0.00"); " fps "; Format$(n / dt, "0.0"); " polys"; e.NPolys; " hash "; Hex$(cv.Hash)
    Print "PASS"
End Sub

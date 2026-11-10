Option Explicit

Sub GameFrame(cv As Canvas)
    cv.Cls RGB(0, 0, 48)
    cv.Box 80, 140, 40, 4, vbWhite
    cv.Circle 100, 75, 4, RGB(255, 200, 0), True
    cv.DrawText 4, 2, "SCORE 0", vbWhite
    cv.Refresh
End Sub

Sub Main()
    Dim cv As Canvas, f As Long, t0 As Double, ms As Double
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 200, 150
    t0 = TimerMs()
    For f = 1 To 1000
        GameFrame cv
    Next f
    ms = TimerMs() - t0
    Print "1000 frames in"; Format$(ms, "0"); " ms:"; Format$(ms / 1000, "0.000"); " ms a frame"
    If ms > 0 Then Print Format$(1000000 / ms, "0"); " frames a second"
End Sub

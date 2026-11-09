' micro-benchmarks of the pieces the game renderers use (A3Fix, A3Scene, Canvas calls)
Option Explicit

Private Sub Report(ByVal what As String, ByVal t0 As Double, ByVal n As Long)
    Print Left$(what & Space$(28), 28) & Format$((TimerMs() - t0) * 1000# / n, "0.00") & " us"
End Sub

Sub Main()
    Dim cv As Object, i As Long, t As Double, s As Long, c As A3Cam, d As Double, x As Long
    Dim xs(0 To 9) As Long, ys(0 To 9) As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 320, 256
    A3FixInit
    GfxPalette Array(0, &HFFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    t = TimerMs()
    For i = 1 To 20000
        s = s + i * 3 - (s \ 7)
    Next i
    Report "int loop step", t, 20000
    t = TimerMs()
    For i = 1 To 20000
        d = d + i * 0.5 - d / 7#
    Next i
    Report "double loop step", t, 20000
    t = TimerMs()
    For i = 1 To 20000
        x = Int(CDbl(i) * 1234# / 4096#)
    Next i
    Report "Int(CDbl*/4096#)", t, 20000
    t = TimerMs()
    For i = 1 To 20000
        x = ShrA(i * 1234, 12)
    Next i
    Report "ShrA call", t, 20000
    t = TimerMs()
    For i = 1 To 20000
        x = A3Sin(i)
    Next i
    Report "A3Sin call", t, 20000
    t = TimerMs()
    For i = 1 To 20000
        x = FMul(i * 100, 54321)
    Next i
    Report "FMul call", t, 20000
    t = TimerMs()
    For i = 1 To 20000
        x = FHypot(i * 100, 54321)
    Next i
    Report "FHypot call", t, 20000
    c.yaw = 1000: c.pitch = 300
    CamView c, 320, 256, 160, 118, 220
    CamSetup c
    CamPlace c, 65536 * 5, 65536 * 34, -65536 * 800
    t = TimerMs()
    For i = 1 To 5000
        CamXform c, i Mod 900, 20, 300
    Next i
    Report "CamXform", t, 5000
    A3Begin 3000
    t = TimerMs()
    For i = 1 To 1000
        A3QuadW c, -1, 1, -50, 0, 200, 50, 0, 200, 50, 60, 200, -50, 60, 200
        If a3NPolys > 1000 Then A3Begin 3000
    Next i
    Report "A3QuadW (on screen)", t, 1000
    t = TimerMs()
    For i = 1 To 1000
        A3QuadW c, -1, 1, -900, 0, -500, 900, 0, -500, 900, 0, 900, -900, 0, 900
        If a3NPolys > 1000 Then A3Begin 3000
    Next i
    Report "A3QuadW (clipped floor)", t, 1000
    xs(0) = 10: ys(0) = 10: xs(1) = 100: ys(1) = 20: xs(2) = 90: ys(2) = 90: xs(3) = 15: ys(3) = 80
    t = TimerMs()
    For i = 1 To 1000
        cv.Polygon xs, ys, 4, vbWhite, True
    Next i
    Report "cv.Polygon 90x80", t, 1000
    t = TimerMs()
    For i = 1 To 1000
        cv.Box 0, 0, 320, 8, vbWhite
    Next i
    Report "cv.Box 320x8", t, 1000
    t = TimerMs()
    For i = 1 To 1000
        cv.DrawText 4, 4, "ROUND 3", vbWhite
    Next i
    Report "cv.DrawText 7 chars", t, 1000
    t = TimerMs()
    For i = 1 To 1000
        GRect cv, 4, 4, 40, 10, 1
    Next i
    Report "GRect", t, 1000
    t = TimerMs()
    For i = 1 To 200
        A3Flush cv
    Next i
    Report "A3Flush (" & a3NPolys & " polys)", t, 200
    t = TimerMs()
    For i = 1 To 200
        cv.Cls 0
    Next i
    Report "cv.Cls", t, 200
    Print "picture hash " & cv.Hash
End Sub

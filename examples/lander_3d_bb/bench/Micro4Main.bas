' the parts of a Lander 3D simulation step, on the guest
Option Explicit

Private Type T2
    a As Long
    b As Long
End Type
Private loc As T2
Private gv As Long

Private Sub Report(ByVal what As String, ByVal t0 As Double, ByVal n As Long)
    Print Left$(what & Space$(26), 26) & Format$((TimerMs() - t0) * 1000# / n, "0.00") & " us"
End Sub

Private Sub Empty0()
End Sub

Private Function Arg3(ByVal a As Long, ByVal b As Long, ByVal c As Long) As Long
    Arg3 = a + b + c
End Function

Sub Main()
    Dim i As Long, t As Double, x As Long, n As Long, lv As Long
    LdInit
    LdNewLevel 0, 1, 1018, False
    n = 500
    t = TimerMs()
    For i = 1 To n
        Empty0
    Next i
    Report "empty Sub call", t, n
    t = TimerMs()
    For i = 1 To n
        x = Arg3(i, 2, 3)
    Next i
    Report "3-arg Function", t, n
    t = TimerMs()
    For i = 1 To n
        x = ld.px + i
    Next i
    Report "x = ld.px + i", t, n
    t = TimerMs()
    For i = 1 To n
        ld.t = ld.t + 1
    Next i
    Report "ld.t = ld.t + 1", t, n
    t = TimerMs()
    For i = 1 To n
        loc.a = loc.a + 1
    Next i
    Report "loc.a = loc.a + 1", t, n
    t = TimerMs()
    For i = 1 To n
        x = tH(i)
    Next i
    Report "x = tH(i)", t, n
    lv = 5: gv = 5
    t = TimerMs()
    For i = 1 To n
        x = Arg3(lv, 2, 3)
    Next i
    Report "Arg3(local)", t, n
    t = TimerMs()
    For i = 1 To n
        x = Arg3(gv, 2, 3)
    Next i
    Report "Arg3(module var)", t, n
    t = TimerMs()
    For i = 1 To n
        x = Arg3(ld.px, 2, 3)
    Next i
    Report "Arg3(ld.px)", t, n
    t = TimerMs()
    For i = 1 To n
        x = Arg3(loc.a, 2, 3)
    Next i
    Report "Arg3(loc.a) private UDT", t, n
    t = TimerMs()
    For i = 1 To n
        x = Arg3(padX(1), 2, 3)
    Next i
    Report "Arg3(padX(1))", t, n
    t = TimerMs()
    For i = 1 To n
        x = LdHeight(lv, gv)
    Next i
    Report "LdHeight(locals)", t, n
    t = TimerMs()
    For i = 1 To n
        LdUp
    Next i
    Report "LdUp", t, n
    t = TimerMs()
    For i = 1 To n
        LdFeet
    Next i
    Report "LdFeet", t, n
    t = TimerMs()
    For i = 1 To n
        x = LdTilt()
    Next i
    Report "LdTilt", t, n
    t = TimerMs()
    For i = 1 To n
        x = LdAgl()
    Next i
    Report "LdAgl", t, n
    t = TimerMs()
    For i = 1 To n
        x = FAtan2(i * 100, 65536)
    Next i
    Report "FAtan2", t, n
    t = TimerMs()
    For i = 1 To n
        x = FHypot3(i * 100, 65536, 3000)
    Next i
    Report "FHypot3", t, n
    t = TimerMs()
    For i = 1 To n
        x = LdNearestPad(True)
    Next i
    Report "LdNearestPad", t, n
    t = TimerMs()
    For i = 1 To n
        x = MulDiv(i, 65536, 77777)
    Next i
    Report "MulDiv", t, n
    t = TimerMs()
    For i = 1 To 100
        inThr = 30000: inPitch = 0: inRoll = 0
        LdStep
    Next i
    Report "LdStep", t, 100
    Print "picture hash 0"
End Sub

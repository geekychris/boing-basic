' Lander 3D micro benchmarks: what a simulation step is made of
Option Explicit

Private Sub Report(ByVal what As String, ByVal t0 As Double, ByVal n As Long)
    Print Left$(what & Space$(24), 24) & Format$((TimerMs() - t0) * 1000# / n, "0.00") & " us"
End Sub

Sub Main()
    Dim i As Long, t As Double, x As Long, n As Long, d As Double
    LdInit
    LdNewLevel 0, 1, 1018, False
    n = 2000
    t = TimerMs()
    For i = 1 To n
        x = x + i * 3 - (x \ 7)
    Next i
    Report "int loop", t, n
    t = TimerMs()
    For i = 1 To n
        d = d + i * 0.5
    Next i
    Report "double add", t, n
    t = TimerMs()
    For i = 1 To n
        x = Int(CDbl(i) * 54321# * 1.52587890625E-05)
    Next i
    Report "Int(CDbl*)", t, n
    t = TimerMs()
    For i = 1 To n
        x = FMul(i * 100, 54321)
    Next i
    Report "FMul", t, n
    t = TimerMs()
    For i = 1 To n
        x = ShrA(i * 100, 16)
    Next i
    Report "ShrA", t, n
    t = TimerMs()
    For i = 1 To n
        x = LdSin(i * 100)
    Next i
    Report "LdSin", t, n
    t = TimerMs()
    For i = 1 To n
        x = FHypot(i * 100, 54321)
    Next i
    Report "FHypot", t, n
    t = TimerMs()
    For i = 1 To n
        x = LdHeight(i * 1000, 54321)
    Next i
    Report "LdHeight", t, n
    t = TimerMs()
    For i = 1 To 200
        LdAutopilot
    Next i
    Report "LdAutopilot", t, 200
    t = TimerMs()
    For i = 1 To 200
        LdStep
    Next i
    Report "LdStep", t, 200
    Print "picture hash 0"
End Sub

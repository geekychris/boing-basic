' which floating point operations are slow on the QEMU guest, and integer alternatives
Option Explicit

Private Sub Report(ByVal what As String, ByVal t0 As Double, ByVal n As Long)
    Print Left$(what & Space$(24), 24) & Format$((TimerMs() - t0) * 1000# / n, "0.00") & " us"
End Sub

Private Function FMulI(ByVal a As Long, ByVal b As Long) As Long
    Dim al As Long, ah As Long, bl As Long, bh As Long
    al = a And 65535: ah = ShrA(a, 16)
    bl = b And 65535: bh = ShrA(b, 16)
    FMulI = Shl(ah * bh, 16) + al * bh + ah * bl + ShrL(al * ShrL(bl, 8) + ShrL(al * (bl And 255), 8), 8)
End Function

Sub Main()
    Dim i As Long, t As Double, x As Long, n As Long, d As Double, e As Object, y As Double
    n = 2000
    Set e = CreateObject("Boing.Engine3D")
    t = TimerMs()
    For i = 1 To n
        d = i * 0.5
    Next i
    Report "d = i * 0.5 (exact)", t, n
    t = TimerMs()
    For i = 1 To n
        d = i * 0.1
    Next i
    Report "d = i * 0.1 (inexact)", t, n
    t = TimerMs()
    For i = 1 To n
        d = i / 3#
    Next i
    Report "d = i / 3", t, n
    d = 1234.5678
    t = TimerMs()
    For i = 1 To n
        y = Int(d)
    Next i
    Report "Int(d) to Double", t, n
    t = TimerMs()
    For i = 1 To n
        x = Int(d)
    Next i
    Report "x = Int(d)", t, n
    t = TimerMs()
    For i = 1 To n
        x = CLng(d)
    Next i
    Report "x = CLng(d)", t, n
    t = TimerMs()
    For i = 1 To n
        x = d
    Next i
    Report "x = d", t, n
    t = TimerMs()
    For i = 1 To n
        y = Sqr(d)
    Next i
    Report "Sqr(d)", t, n
    t = TimerMs()
    For i = 1 To n
        x = ShrA(i * 100, 16)
    Next i
    Report "ShrA builtin", t, n
    t = TimerMs()
    For i = 1 To n
        x = FMulI(i * 100, 54321)
    Next i
    Report "FMulI (integer)", t, n
    t = TimerMs()
    For i = 1 To n
        x = e.FMul(i * 100, 54321)
    Next i
    Report "e.FMul", t, n
    t = TimerMs()
    For i = 1 To n
        x = e.FSqrt(i * 100)
    Next i
    Report "e.FSqrt", t, n
    t = TimerMs()
    For i = 1 To n
        x = e.Sin(i * 100)
    Next i
    Report "e.Sin", t, n
    Print "picture hash 0"
End Sub

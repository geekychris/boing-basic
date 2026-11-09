' what costs what on the OS4 guest: Double -> Long conversions, floor, and procedures with
' an Object parameter (on the guest ~20 us a call when they make a late-bound call)
Option Explicit

Private cvG As Object

Private Sub Report(ByVal what As String, ByVal t0 As Double, ByVal n As Long)
    Print Left$(what & Space$(30), 30) & Format$((TimerMs() - t0) * 1000# / n, "0.00") & " us"
End Sub

Private Sub NoArgs()
End Sub

Private Sub LongArg(ByVal a As Long)
End Sub

Private Sub ObjArg(c As Object)
End Sub

Private Sub ObjBox(c As Object, ByVal x As Long)
    c.Box x, 0, 4, 4, vbWhite
End Sub

Private Sub ObjBoxByVal(ByVal c As Object, ByVal x As Long)
    c.Box x, 0, 4, 4, vbWhite
End Sub

Private Sub ObjBox5(c As Object, ByVal x As Long)
    c.Box x, 0, 4, 4, vbWhite
    c.Box x, 0, 4, 4, vbWhite
    c.Box x, 0, 4, 4, vbWhite
    c.Box x, 0, 4, 4, vbWhite
    c.Box x, 0, 4, 4, vbWhite
End Sub

Private Sub GlobBox(ByVal x As Long)
    cvG.Box x, 0, 4, 4, vbWhite
End Sub

Sub Main()
    Dim c As Object, i As Long, t As Double, d As Double, x As Long, s As Single
    Set c = CreateObject("Boing.Canvas")
    c.Resize 320, 256
    Set cvG = c
    d = 1234.75
    t = TimerMs(): For i = 1 To 2000: x = x + i: Next i: Report "x = x + i", t, 2000
    t = TimerMs(): For i = 1 To 2000: d = d + 0.5: Next i: Report "d = d + 0.5", t, 2000
    t = TimerMs(): For i = 1 To 2000: x = d: Next i: Report "x = d (Double->Long)", t, 2000
    t = TimerMs(): For i = 1 To 2000: d = Int(d): Next i: Report "d = Int(d)", t, 2000
    t = TimerMs(): For i = 1 To 2000: d = Sqr(d): Next i: Report "d = Sqr(d)", t, 2000
    t = TimerMs(): For i = 1 To 2000: x = i \ 7: Next i: Report "x = i \ 7", t, 2000
    t = TimerMs(): For i = 1 To 2000: x = (i - (i And 4095)) \ 4096: Next i: Report "x = i >> 12 by \", t, 2000
    t = TimerMs(): For i = 1 To 2000: s = s + 0.5!: Next i: Report "Single add", t, 2000
    t = TimerMs(): For i = 1 To 2000: NoArgs: Next i: Report "call Sub()", t, 2000
    t = TimerMs(): For i = 1 To 2000: LongArg i: Next i: Report "call Sub(ByVal Long)", t, 2000
    t = TimerMs(): For i = 1 To 2000: ObjArg c: Next i: Report "call Sub(c As Object)", t, 2000
    t = TimerMs(): For i = 1 To 2000: c.Box 0, 0, 4, 4, vbWhite: Next i: Report "c.Box 4x4 inline", t, 2000
    t = TimerMs(): For i = 1 To 2000: GlobBox 0: Next i: Report "Sub: module cvG.Box", t, 2000
    t = TimerMs(): For i = 1 To 2000: ObjBox c, 0: Next i: Report "Sub(c As Object): c.Box", t, 2000
    t = TimerMs(): For i = 1 To 2000: ObjBoxByVal c, 0: Next i: Report "Sub(ByVal c): c.Box", t, 2000
    t = TimerMs(): For i = 1 To 400: ObjBox5 c, 0: Next i: Report "Sub(c): 5 x c.Box", t, 400
    Print "picture hash " & c.Hash
End Sub

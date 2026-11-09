' which part of FHypot is slow on the guest
Option Explicit

Private Sub Report(ByVal what As String, ByVal t0 As Double, ByVal n As Long)
    Print Left$(what & Space$(26), 26) & Format$((TimerMs() - t0) * 1000# / n, "0.00") & " us"
End Sub

Private Function ISqD(ByVal v As Double) As Long
    ISqD = Int(Sqr(v))
End Function

Private Function ISqL(ByVal v As Long) As Long
    Dim d As Double
    d = v
    ISqL = Int(Sqr(d))
End Function

' a3_isqrt, bit by bit, on a Long holding uint32 bits
Private Function ISqBits(ByVal v As Long) As Long
    Dim r As Long, b As Long, t As Long
    b = &H40000000
    Do While b > 0
        t = r + b
        If (v Xor &H80000000) >= (t Xor &H80000000) Then
            v = v - t
            r = ShrL(r, 1) + b
        Else
            r = ShrL(r, 1)
        End If
        b = ShrL(b, 2)
    Loop
    ISqBits = r
End Function

Private Function HypA(ByVal a As Long, ByVal b As Long) As Long
    Dim x As Long, y As Long, sh As Long, d As Double, r As Long, q As Double
    If a < 0 Then x = -a Else x = a
    If b < 0 Then y = -b Else y = b
    Do While (x Or y) >= 46000
        x = ShrL(x, 1)
        y = ShrL(y, 1)
        sh = sh + 1
    Loop
    d = x
    q = y
    d = d * d + q * q
    r = Int(Sqr(d))
    q = r
    If q * q > d Then r = r - 1
    HypA = Shl(r, sh)
End Function

Private Function HypC(ByVal a As Long, ByVal b As Long) As Long
    Dim x As Long, y As Long, sh As Long, d As Double, r As Long, q As Double
    If a < 0 Then x = -a Else x = a
    If b < 0 Then y = -b Else y = b
    HypC = x + y
End Function

Private Function HypD(ByVal a As Long, ByVal b As Long) As Long
    Dim x As Long, y As Long, sh As Long
    x = a: y = b
    Do While (x Or y) >= 46000
        x = ShrL(x, 1)
        y = ShrL(y, 1)
        sh = sh + 1
    Loop
    HypD = Shl(x + y, sh)
End Function

Sub Main()
    Dim i As Long, t As Double, x As Long, n As Long, d As Double, e As Double, y As Long
    n = 2000
    d = 12345.678
    t = TimerMs()
    For i = 1 To n
        e = Sqr(d)
    Next i
    Report "e = Sqr(d)", t, n
    t = TimerMs()
    For i = 1 To n
        x = Int(Sqr(d))
    Next i
    Report "x = Int(Sqr(d))", t, n
    t = TimerMs()
    For i = 1 To n
        e = i
        e = e * e + d
    Next i
    Report "e = i: e*e+d", t, n
    t = TimerMs()
    For i = 1 To n
        x = ISqD(d)
    Next i
    Report "ISqD(d) call", t, n
    t = TimerMs()
    For i = 1 To n
        x = ISqL(i * 1000)
    Next i
    Report "ISqL(long) call", t, n
    t = TimerMs()
    For i = 1 To n
        x = ISqBits(i * 1000)
    Next i
    Report "ISqBits (integer)", t, n
    t = TimerMs()
    For i = 1 To n
        e = d
        If e * e > d Then y = 1
    Next i
    Report "If e*e > d", t, n
    t = TimerMs()
    For i = 1 To n
        x = Shl(i, 3)
    Next i
    Report "Shl", t, n
    t = TimerMs()
    For i = 1 To n
        y = (i Or 5) >= 46000
    Next i
    Report "(x Or y) >= k", t, n
    t = TimerMs()
    For i = 1 To n
        x = Abs(i - 1000)
    Next i
    Report "x = Abs(i - 1000)", t, n
    t = TimerMs()
    For i = 1 To n
        x = AbsL(i - 1000)
    Next i
    Report "x = AbsL(i - 1000)", t, n
    t = TimerMs()
    For i = 1 To n
        x = FHypot(i * 100, 54321)
    Next i
    Report "FHypot (no Abs)", t, n
    t = TimerMs()
    For i = 1 To n
        x = HypA(i * 100, 54321)
    Next i
    Report "HypA (sqrt inline)", t, n
    t = TimerMs()
    For i = 1 To n
        x = HypC(i * 100, 54321)
    Next i
    Report "HypC (abs only)", t, n
    t = TimerMs()
    For i = 1 To n
        x = HypD(i * 100, 54321)
    Next i
    Report "HypD (the loop only)", t, n
    Print "picture hash 0"
End Sub

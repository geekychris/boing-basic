' a 20 ms Timer whose handler takes ~10 ms: about 50 ticks a second (a fixed timeline), not 33
Dim n As Long, t0 As Double

Private Sub tick_Timer()
    Dim t As Double
    If n = 0 Then t0 = TimerMs()
    n = n + 1
    t = TimerMs()
    Do While TimerMs() - t < 10: Loop
    If TimerMs() - t0 >= 1000 Then
        If n >= 45 And n <= 53 Then Print "ticks ok" Else Print "ticks"; n
        End
    End If
End Sub

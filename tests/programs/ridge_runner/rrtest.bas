' Ridge Runner host test: races whose state hashes must equal the C original's
' (examples/ridge_runner/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal seed As Long, ByVal track As Long, ByVal maxT As Long, ByVal whole As Boolean, ByVal wobble As Boolean)
    Dim t As Long, s As Long, inp As Long, w As String
    s = 3
    RrNewGame seed, track
    Do While t < maxT And rrOver = 0 And rrWon = 0 And (whole Or rrFinished = 0)
        If wobble Then
            If t Mod 10 = 0 Then inp = A3Rand(s) Mod 32
        Else
            inp = RrBot()
        End If
        RrTick inp
        rrNEv = 0
        t = t + 1
    Loop
    If whole Then w = " whole game"
    If wobble Then w = w & " random input"
    Print "seed " & seed & " track " & track & w & ", " & t & " ticks: track " & rrTrack & " place " & rrPlace & _
          " score " & rrScore & " gates " & rrGatesHit & " jumps " & rrJumps & " bumps " & rrBumps & " hash " & Hex8(RrStateHash())
End Sub

Sub Main()
    RrInit
    Play 1234, 3, 4000, False, False
    Play 1, 1, 12000, True, False
    Play 77, 5, 3000, False, False
    Play 8, 2, 1500, False, True
End Sub

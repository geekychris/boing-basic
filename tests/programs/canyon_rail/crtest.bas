' Canyon Rail host test: autopilot games and random input, state hashes equal to the
' C original's (examples/canyon_rail/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal seed As Long, ByVal stage As Long, ByVal maxT As Long, ByVal wobble As Boolean)
    Dim t As Long, s As Long, inp As Long, w As String
    s = 7
    CrNewGame seed, stage
    Do While t < maxT And crOver = 0 And crWon = 0
        If wobble Then
            If t Mod 6 = 0 Then inp = A3Rand(s) Mod 32
        Else
            inp = CrBot()
        End If
        CrTick inp
        crNEv = 0
        t = t + 1
    Loop
    If wobble Then w = " random input"
    Print "seed " & seed & " stage " & stage & w & ", " & t & " ticks: stage " & crStage & " score " & crScore & _
          " shield " & crShield & " hits " & crHits & "/" & crShots & " combo " & crBestCombo & " hash " & Hex8(CrStateHash())
End Sub

Sub Main()
    CrInit
    Play 1234, 1, 4500, False
    Play 5, 2, 3000, False
    Play 99, 3, 3000, False
    Play 42, 1, 2500, True
End Sub

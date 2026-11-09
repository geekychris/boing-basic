' Marble Tilt host test: autopilot games whose state hashes must equal the C
' original's (examples/marble_tilt/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal lvl As Long, ByVal maxT As Long)
    Dim t As Long
    t = MtAutoGame(1, lvl, maxT)
    Print "from level " & lvl & ", " & t & " ticks: level " & mtLevel & " score " & mtScore & " falls " & mtFalls & _
          " bumps " & mtBumps & " time " & mtTimeLeft & " won " & mtWon & " hash " & Hex8(MtStateHash())
End Sub

' random tilting (bumpers, walls, holes, falls): A3Rand picks the input every 8 ticks
Private Sub Wobble(ByVal lvl As Long, ByVal maxT As Long)
    Dim s As Long, inp As Long, t As Long
    s = 99
    MtNewGame 1, lvl
    Do While t < maxT And mtOver = 0 And mtWon = 0
        If t Mod 8 = 0 Then inp = A3Rand(s) Mod 16
        MtTick inp
        mtNEv = 0
        t = t + 1
    Loop
    Print "wobble level " & lvl & ", " & t & " ticks: level " & mtLevel & " falls " & mtFalls & " bumps " & mtBumps & _
          " time " & mtTimeLeft & " hash " & Hex8(MtStateHash())
End Sub

Sub Main()
    Dim k As Long
    MtInit
    Wobble 5, 1500
    Wobble 4, 1500
    Wobble 8, 1500
    Play 1, 6000
    For k = 2 To 8
        Play k, 2000
    Next k
End Sub

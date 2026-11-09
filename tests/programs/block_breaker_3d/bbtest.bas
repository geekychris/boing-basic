' Block Breaker 3D host test: autopilot games whose state hashes must equal the C
' original's (examples/block_breaker_3d/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal seed As Long, ByVal lvl As Long, ByVal maxT As Long)
    Dim t As Long
    t = BbAutoGame(seed, lvl, maxT)
    Print "seed " & seed & " level " & lvl & ", " & t & " ticks: level " & bbLevel & " score " & bbScore & _
          " lives " & bbLives & " broken " & bbBroken & " caps " & bbCapsDropped & " hash " & Hex8(BbStateHash())
End Sub

Sub Main()
    BbInit
    Play 1234, 1, 20000
    Play 7, 3, 6000
    Play 99, 5, 6000
    Play 2026, 8, 8000
End Sub

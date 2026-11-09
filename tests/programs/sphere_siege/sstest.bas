' Sphere Siege host test: autopilot games whose state hashes must equal the C
' original's (examples/sphere_siege/tools/trace.sh prints the same lines)
Option Explicit

Private Sub Play(ByVal seed As Long, ByVal wave As Long, ByVal maxT As Long)
    Dim t As Long
    t = SsAutoGame(seed, wave, maxT)
    Print "seed " & seed & " wave " & wave & ", " & t & " ticks: wave " & ssWave & " lives " & ssLives & _
          " score " & ssScore & " shots " & ssShots & " hits " & ssHits & " kills " & ssKills & " hash " & Hex8(SsStateHash())
End Sub

Sub Main()
    SsInit
    Play 1234, 1, 6000
    Play 5, 4, 3000
    Play 31337, 6, 3000
End Sub

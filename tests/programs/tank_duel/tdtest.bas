' Tank Duel host test: autopilot fights, whose state hashes must equal the C
' original's (tools/trace.sh prints the same lines from amiga_mcp's td_core.c)
Option Explicit

Private Sub Fight(ByVal seed As Long, ByVal rnd As Long, ByVal maxT As Long)
    Dim t As Long
    t = TdFight(seed, rnd, maxT)
    Print "seed " & seed & " round " & rnd & ", " & t & " ticks: round " & tdRound & " score " & tdScore & _
          " kills " & tdKills & " shots " & tdShots & " hits " & tdHits & " hp " & tk(0).hp & " hash " & Hex8(TdStateHash())
End Sub

Sub Main()
    TdInit
    Fight 1234, 1, 9000
    Fight 1, 1, 3000
    Fight 77, 3, 4000
    Fight 4242, 5, 4000
    Fight 9, 8, 3000
End Sub

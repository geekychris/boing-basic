' Ace Pilot 2 trace: the same campaigns as tools/trace.c (the C original), the same lines.
Option Explicit

Private Sub Campaign(ByVal seed As Long, ByVal m As Long, ByVal ticks As Long, ByVal every As Long)
    Dim t As Long, nev As Long, evh As Long, et As Long, ea As Long, eb As Long, ex As Long, ey As Long, ez As Long
    evh = FNV_START
    ApNewGame seed, m
    t = 0
    Do While t < ticks And apOver = 0 And apWon = 0
        ApTick ApBot()
        Do While ApPopEvent(et, ea, eb, ex, ey, ez)
            evh = Fnv(Fnv(Fnv(evh, et), ea), eb)
            evh = Fnv(Fnv(Fnv(evh, ex), ey), ez)
            nev = nev + 1
        Loop
        If apPhase >= PH_DONE And apEndT = 0 Then ApNext
        If every > 0 Then
            If (t + 1) Mod every = 0 Then Print "  t " & (t + 1) & " mission " & apMission & " phase " & apPhase & _
                                               " score " & apScore & " hash " & Hex8(ApStateHash())
        End If
        t = t + 1
    Loop
    Print "seed " & seed & " from mission " & m & ", " & t & " ticks: mission " & apMission & " phase " & apPhase & _
          " score " & apScore & " kills " & apKills & " ground " & apGKills & " shots " & apShots & " hits " & apHits & _
          " lives " & apLives & " over " & apOver & " won " & apWon & " events " & nev & "/" & Hex8(evh) & " hash " & Hex8(ApStateHash())
End Sub

Sub Main()
    Dim m As Long
    ApInit
    Campaign 1234, 1, 20000, 1000
    Print "  vectors.h: 2B867448"
    For m = 1 To AP_MISSIONS
        Campaign m * 31 + 5, m, 4000, 0
    Next m
End Sub

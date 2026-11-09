' Stack Tower trace: the same games as tools/trace.c (the C original), the same lines.
'   boing run Trace.bbp          (tests/examples/stack_tower_trace runs it in make test)
Option Explicit

Private Sub Script(ByVal mode As Long, ByVal seed As Long)
    Dim k As Long, i As Long, r As Long, m As Long, q(0 To 4) As Long, d As Long
    StNewGame mode, seed, 1, 0
    k = 0
    Do While k < 120 And stOver = 0 And stWon = 0
        r = (k * 7 + seed) Mod 5
        m = ((k * 13 + seed) Mod 9) - 4
        If k Mod 11 = 5 Then StHoldPiece
        For i = 0 To r - 1
            If i Mod 2 = 1 Then StRotate -1 Else StRotate 1
        Next i
        If m < 0 Then d = -1 Else d = 1
        For i = 1 To Abs(m): StMove d: Next i
        StHardDrop
        k = k + 1
    Loop
    StPreview 5, q
    Print "script " & stModeName(mode) & " " & seed & ": pieces " & k & " score " & stScore & " rings " & stLines & _
          " over " & stOver & " won " & stWon & " board " & CStr(UD(StBoardHash())) & " queue " & q(0) & " " & q(1) & " " & _
          q(2) & " " & q(3) & " " & q(4) & " hold " & stHold & " hash " & Hex8(StStateHash())
End Sub

Private Sub Play(ByVal bot As Boolean, ByVal mode As Long, ByVal seed As Long, ByVal lv As Long, ByVal ticks As Long)
    Dim t As Long, games As Long, nev As Long, evh As Long, et As Long, ea As Long, eb As Long
    evh = FNV_START
    games = 1
    BotReset
    StNewGame mode, seed, lv, 0
    For t = 1 To ticks
        If bot Then BotTick Else DemoStep
        StTick 40
        Do While StPopEvent(et, ea, eb)
            evh = Fnv(Fnv(Fnv(evh, et), ea), eb)
            nev = nev + 1
        Loop
        If stOver <> 0 Or stWon <> 0 Then
            Print "  t " & t & " game " & games & " over " & stOver & " won " & stWon & " score " & stScore & " rings " & _
                  stLines & " level " & stLevel & " pieces " & stPieces & " hash " & Hex8(StStateHash())
            games = games + 1
            StNewGame mode, A3Hash(stSeed) And &H7FFFFFFF, lv, stLastCol
            BotReset
        End If
    Next t
    Print IIf(bot, "bot ", "demo ") & stModeName(mode) & " seed " & seed & " level " & lv & ", " & ticks & " ticks: games " & _
          games & " score " & stScore & " rings " & stLines & " level " & stLevel & " pieces " & stPieces & " events " & _
          nev & "/" & Hex8(evh) & " hash " & Hex8(StStateHash())
End Sub

Sub Main()
    Dim t0 As Double
    StInit
    t0 = Timer
    Script MODE_MARATHON, 12345
    Print "  browser: pieces 16 score 406 board 3902978329 queue 3 2 4 1 7 hold 4"
    Script MODE_MARATHON, 987654321
    Print "  browser: pieces 20 score 478 board 2330888977 queue 1 0 2 6 5 hold 4"
    Script MODE_DIG, 42
    Print "  browser: pieces 11 score 140 board 3304110537 queue 6 5 0 3 0 hold 3"
    Script MODE_DIG, 2026
    Print "  browser: pieces 11 score 142 board 475790452 queue 5 4 1 7 1 hold 7"
    Play False, MODE_MARATHON, 778, 1, 6000
    Play True, MODE_MARATHON, 1, 1, 20000
    Play True, MODE_RISING, 7, 3, 12000
    Play True, MODE_DIG, 42, 1, 8000
    Play True, MODE_MARATHON, 2026, 9, 8000
    If InStr(Command$, "--time") > 0 Then Print "time " & Format$(Timer - t0, "0.00") & " s"
End Sub

' Orbit Docking trace: the same games as tools/trace.c (the C original), the same lines.
Option Explicit

' bot: the autopilot; else random thrusters (a new input every 5 ticks)
Private Sub Play(ByVal bot As Boolean, ByVal seed As Long, ByVal lv As Long, ByVal maxT As Long)
    Dim t As Long, nev As Long, evh As Long, lcg As Long, inp As Long, et As Long, ea As Long, eb As Long
    evh = FNV_START
    lcg = AddW(MulW(seed, &H9E3779B1), 1)
    OdNewGame seed, lv
    Do While t < maxT And odOver = 0 And odWon = 0
        If bot Then
            inp = OdBot()
        ElseIf t Mod 5 = 0 Then
            lcg = AddW(MulW(lcg, 1103515245), 12345)
            inp = ShrU(lcg, 16) And 255
        End If
        OdTick inp
        Do While OdPopEvent(et, ea, eb)
            evh = Fnv(Fnv(Fnv(evh, et), ea), eb)
            nev = nev + 1
        Loop
        t = t + 1
    Loop
    Print IIf(bot, "bot", "random") & " seed " & seed & " level " & lv & ", " & t & " ticks: level " & odLevel & " docks " & _
          odDocks & " crashes " & odCrashes & " lives " & odLives & " score " & odScore & " fuel " & odFuel & " fail " & _
          odLastFail & " over " & odOver & " won " & odWon & " events " & nev & "/" & Hex8(evh) & " hash " & Hex8(OdStateHash())
End Sub

Sub Main()
    Dim s As Long, lv As Long
    OdInit
    Play True, 1234, 1, 100000
    Print "  vectors.h: EFE8A63F"
    For lv = 1 To OD_LEVELS
        For s = 1 To 3
            Play True, s * 7919 + lv, lv, 6000
        Next s
    Next lv
    For s = 1 To 6
        Play False, s * 101, 1 + s Mod OD_LEVELS, 3000
    Next s
End Sub

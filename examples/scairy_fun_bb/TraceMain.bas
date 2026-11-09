' ScAIry Fun trace: the same drives as tools/trace.c (the C original), the same lines.
Option Explicit

' mode 0: the title's demo; 1: the perfect autopilot from route r; 2: the shipped autopilot,
' hands off; 3: random hands (a new input every 10 frames)
Private Sub Drive(ByVal mode As Long, ByVal r As Long, ByVal traffic As Long, ByVal frames As Long, ByVal every As Long)
    Dim f As Long, nev As Long, evh As Long, lcg As Long, inp As Long, et As Long, ea As Long, eb As Long
    evh = FNV_START
    lcg = r * 7 + mode * 131 + 1
    tuSpeedPct = 0                       ' WorldInit: the defaults
    WorldInit
    tuTrafficPct = traffic
    If mode = 1 Then tuAiPerfect = 1
    If mode <> 0 Then
        WorldStartGame
        If r <> 0 Then WorldStartRoute r
        wState = GS_PLAY
    End If
    For f = 0 To frames - 1
        If mode = 3 And f Mod 10 = 0 Then
            lcg = AddW(MulW(lcg, 1103515245), 12345)
            inp = Choose(UModL(ShrU(lcg, 16), 6) + 1, 0, IN_LEFT, IN_RIGHT, IN_UP, IN_DOWN, IN_FIRE)
        End If
        WorldUpdate inp
        Do While WorldPopEvent(et, ea, eb)
            evh = Fnv(Fnv(Fnv(evh, et), ea), eb)
            nev = nev + 1
        Loop
        If every > 0 Then
            If (f + 1) Mod every = 0 Then Print "  f " & (f + 1) & " route " & (wRoute + 1) & " state " & wState & " seg " & _
                                               SegOf(carZ) & " score " & wScore & " cover " & wCover & " hash " & Hex8(ScStateHash())
        End If
        If mode <> 0 And mode <> 3 And wState <> GS_PLAY And wState <> GS_INTRO Then Exit For
    Next f
    Print "mode " & mode & " route " & (r + 1) & " traffic " & traffic & ", " & f & " frames: route " & (wRoute + 1) & " state " & _
          wState & " seg " & SegOf(carZ) & " score " & wScore & " cover " & wCover & " saves " & wSaves & " needless " & _
          wNeedless & " takeovers " & wTakeovers & " events " & nev & "/" & Hex8(evh) & " hash " & Hex8(ScStateHash())
End Sub

Sub Main()
    Dim r As Long
    ScInit
    Drive 0, 0, 100, 3000, 0
    For r = 0 To NUM_ROUTES - 1: Drive 1, r, 100, 9000, 1000: Next r
    For r = 0 To NUM_ROUTES - 1: Drive 2, r, 100, 9000, 1000: Next r
    For r = 0 To NUM_ROUTES - 1: Drive 3, r, 60, 4000, 0: Next r
End Sub

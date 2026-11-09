' Boing Pinball trace: the bot plays each table from the seeds the C original's
' tools/trace.c uses and prints the same lines (state hash every 1000 steps).
'   boing run Trace.bbp [games [steps [table]]]
Option Explicit

Sub Main()
    Dim args() As String, games As Long, steps As Long, t As Long, g As Long, s As Long, t0 As Long, t1 As Long
    games = 2: steps = 6000: t0 = 0: t1 = TB_COUNT - 1
    args = Split(Trim$(Command$), " ")
    If UBound(args) >= 0 Then If Len(args(0)) Then games = CLng(args(0))
    If UBound(args) >= 1 Then steps = CLng(args(1))
    If UBound(args) >= 2 Then t0 = CLng(args(2)): t1 = t0
    PbCoreInit
    For t = t0 To t1
        PbBuildTable t
        Print "table " & t & " " & tName & ": nseg " & tNseg & " ncirc " & tNcirc & " nsens " & tNsens & " hash " & Hex8(TableHash())
        For g = 0 To games - 1
            BotReset 1234 + g * 77
            GameInit 99 + g
            GameStart
            s = 1
            Do While s <= steps And gState <> GS_OVER
                PbBot
                GameTick
                gNev = 0
                If s Mod 1000 = 0 Then Print "  t" & t & " g" & g & " step " & s & " score " & gScore & " ball " & gBallNo & " hash " & Hex8(StateHash())
                s = s + 1
            Loop
            Print "  t" & t & " g" & g & " end step " & (s - 1) & " score " & gScore & " ball " & gBallNo & " state " & gState & " hash " & Hex8(StateHash())
        Next g
    Next t
    ' random input: flippers, the plunger held, nudges (tilt), every 20 steps
    Dim r As Long, v As Long
    For t = 0 To TB_COUNT - 1
        r = 4242 + t
        PbBuildTable t
        GameInit 7 + t
        GameStart
        s = 1
        Do While s <= steps And gState <> GS_OVER
            If s Mod 20 = 1 Then v = A3Rand(r)
            inLeft = v And 1: inRight = (v \ 2) And 1
            If ((v \ 4) And 3) = 0 Then inPlunger = 1 Else inPlunger = 0
            inPullTo = -1
            If s Mod 20 = 1 And (v \ 16) Mod 31 = 0 Then inNudgeX = ((v \ 128) Mod 3) - 1 Else inNudgeX = 0
            If s Mod 20 = 1 And (v \ 512) Mod 37 = 0 Then inNudgeY = 1 Else inNudgeY = 0
            GameTick
            gNev = 0
            If s Mod 1000 = 0 Then Print "  wobble t" & t & " step " & s & " score " & gScore & " ball " & gBallNo & " tilts " & gTiltWarnings & " hash " & Hex8(StateHash())
            s = s + 1
        Loop
        Print "  wobble t" & t & " end step " & (s - 1) & " score " & gScore & " ball " & gBallNo & " hash " & Hex8(StateHash())
    Next t
End Sub

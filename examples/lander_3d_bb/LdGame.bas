' Lander 3D - the game around the simulation (game.c of the original, without the
' AmigaBridge part): the title with the autopilot flying a demo, flying (four
' 1/100 s steps a 40 ms frame), the outcome of each landing, ships and levels, the
' level's autopilot check in the background, sound events. No drawing, no OS calls.
Option Explicit

Public Const LS_TITLE As Long = 0
Public Const LS_PLAY As Long = 1
Public Const LS_RESULT As Long = 2
Public Const LS_OVER As Long = 3
Public Const LS_ENTRY As Long = 4          ' (new) typing a name for the high scores
Public Const LS_SCORES As Long = 5         ' (new) the high-score table
Public Const MODE_TOUR As Long = 3         ' the menu's worlds 0..2, then the tour

' the pilot's keys (held) for PilotInput
Public Const IN_LEFT As Long = 1
Public Const IN_RIGHT As Long = 2
Public Const IN_UP As Long = 4
Public Const IN_DOWN As Long = 8
Public Const IN_FIRE As Long = 16

Public gState As Long, gStateTimer As Long
Public gMenu As Long                       ' 0..2 a world, 3 the tour
Public gShips As Long, gLevel As Long
Public gScore As Long, gLastScore As Long, gBest As Long
Public gPaused As Boolean, gHelp As Long, gDemo As Boolean
Public gSteady As Long                     ' the steady throttle (Q/E), 16.16
Public gHeld As Long                       ' IN_* bits held
Public gMsg As String, gMsg2 As String
Public gFrame As Long
Public gProbing As Boolean
Public gTitleFrame0 As Long                ' when the title (painting, then demo) started
Public gLog As Boolean                     ' print the game's events (tests)
Public gNextSeed As Long
Public gWorldChanged As Boolean            ' the front end reloads the world's palette and sky
Public gProbeSlice As Long                 ' autopilot steps of the level check a frame (the C: 150)

Public Sub GameInit()
    LdInit
    gNextSeed = 2026
    gProbeSlice = 25
    ToTitle
End Sub

Private Function WorldFor(ByVal menu As Long, ByVal lv As Long) As Long
    If menu < W_COUNT Then WorldFor = menu Else WorldFor = (lv - 1) Mod W_COUNT
End Function

Private Sub LogEv(ByVal s As String)
    If gLog Then Print s
End Sub

Public Sub BeginLevel()
    Dim w As Long
    w = WorldFor(gMenu, gLevel)
    LdNewLevel w, gLevel, gNextSeed, False
    gNextSeed = gNextSeed + 1
    LdProbeBegin
    gProbing = True
    gWorldChanged = True
    gSteady = 0
    LogEv "LEVEL " & wName(w) & " " & gLevel & " seed " & ld.seed & " fuel " & FInt(ld.fuel)
End Sub

Public Sub StartGame(ByVal menu As Long, ByVal lv As Long)
    gMenu = menu
    If lv < 1 Then lv = 1
    gLevel = lv
    gShips = 3
    gScore = 0
    gDemo = False
    gPaused = False
    gHelp = 0
    gState = LS_PLAY
    BeginLevel
End Sub

Public Sub ToTitle()
    gState = LS_TITLE
    gDemo = True
    gTitleFrame0 = gFrame
    LdNewLevel W_MOON, 2, A3Hash(gNextSeed), False
    gNextSeed = gNextSeed + 1
    gProbing = False
    gWorldChanged = True
End Sub

' "2.5": a 16.16 value with one decimal, as the C's "%ld.%ld"
Public Function Dec1(ByVal v As Long) As String
    Dec1 = FInt(v) & "." & ((ShrA(AbsL(v) * 10, 16)) Mod 10)
End Function

Private Sub Outcome()
    Dim w As Long
    w = ld.world
    gState = LS_RESULT
    gStateTimer = 100
    gLastScore = ld.rScore
    gScore = gScore + ld.rScore
    Select Case ld.outcome
        Case OUT_LANDED
            If ld.rPad = 5 Then
                gMsg = "PERFECT x5"
            ElseIf ld.rPad = 2 Then
                gMsg = "LANDED x2"
            Else
                gMsg = "LANDED"
            End If
            gMsg2 = "SOFT " & ld.rSoft & "  FUEL " & ld.rFuelBonus
            Sfx SFX_LAND
        Case OUT_OFFPAD
            gMsg = "OFF THE PAD"
            gMsg2 = "SAFE, BUT NOT ON A PAD"
            Sfx SFX_BEEP
        Case OUT_CRASHED
            gMsg = "CRASHED"
            If ld.rVsOk = 0 Then
                gMsg2 = "DOWN AT " & Dec1(ld.rVs) & " M/S (LIMIT " & Dec1(wLimVs(w)) & ")"
            ElseIf ld.rHsOk = 0 Then
                gMsg2 = "SLIDING AT " & Dec1(ld.rHs) & " M/S"
            ElseIf ld.rTiltOk = 0 Then
                gMsg2 = "TILTED " & FInt(MulShr(ld.rTilt, 3754936, 16)) & " DEGREES"
            Else
                gMsg2 = "THE GROUND WAS TOO STEEP"
            End If
            gShips = gShips - 1
            Sfx SFX_CRASH
        Case Else
            gMsg = "LOST"
            gMsg2 = "LEFT THE LANDING AREA"
            gShips = gShips - 1
            Sfx SFX_CRASH
    End Select
    If gScore > gBest Then gBest = gScore
    LogEv "OUTCOME " & outcomeName(ld.outcome) & " score " & ld.rScore & " total " & gScore & " ships " & gShips
    If gShips <= 0 Then
        gState = LS_OVER
        gStateTimer = 50
    End If
End Sub

Public Sub AfterResult()
    If ld.outcome = OUT_LANDED Or ld.outcome = OUT_OFFPAD Then gLevel = gLevel + 1
    gState = LS_PLAY
    BeginLevel
End Sub

' the steady throttle, Q / E
Public Sub ThrottleStep(ByVal up As Boolean)
    If gState <> LS_PLAY Then Exit Sub
    If up Then
        gSteady = gSteady + 6553
        If gSteady > FONE Then gSteady = FONE
    Else
        gSteady = gSteady - 6553
        If gSteady < 0 Then gSteady = 0
    End If
End Sub

Private Sub PilotInput()
    If (gHeld And IN_FIRE) <> 0 Then inThr = FONE Else inThr = gSteady
    If (gHeld And IN_UP) <> 0 Then
        inPitch = FONE
    ElseIf (gHeld And IN_DOWN) <> 0 Then
        inPitch = -FONE
    Else
        inPitch = 0
    End If
    If (gHeld And IN_LEFT) <> 0 Then
        inRoll = FONE
    ElseIf (gHeld And IN_RIGHT) <> 0 Then
        inRoll = -FONE
    Else
        inRoll = 0
    End If
End Sub

' one 40 ms frame of the game (game_update's loop body)
Public Sub GameFrame()
    Dim k As Long, e As Long
    If gHelp <> 0 Or gPaused Then Exit Sub
    gFrame = gFrame + 1
    If gStateTimer > 0 Then gStateTimer = gStateTimer - 1
    If gState = LS_RESULT And gStateTimer = 0 Then AfterResult
    If gState = LS_PLAY Or gState = LS_TITLE Or gState = LS_ENTRY Or gState = LS_SCORES Then
        For k = 1 To 4
            If gDemo Or gState <> LS_PLAY Then LdAutopilot Else PilotInput
            LdStep
        Next k
        e = LdPopEvent()
        Do While e <> LDE_NONE
            If e = LDE_FUEL_OUT And gState = LS_PLAY Then
                Sfx SFX_FUEL
                LogEv "FUEL OUT"
            End If
            e = LdPopEvent()
        Loop
        If gState = LS_PLAY And ld.outcome = 0 Then
            If ld.thr > 3276 And (gFrame Mod 6) = 0 Then Sfx SFX_THRUST
            If (ld.rcs0 <> 0 Or ld.rcs1 <> 0) And (gFrame Mod 5) = 0 Then Sfx SFX_RCS
        End If
        If ld.outcome <> 0 Then
            If gState = LS_PLAY Then
                Outcome
            ElseIf gFrame Mod 75 = 0 Then          ' the demo goes round again
                LdNewLevel (gFrame \ 75) Mod W_COUNT, 2, A3Hash(gNextSeed), False
                gNextSeed = gNextSeed + 1
                gWorldChanged = True
            End If
        End If
    End If
    ' the level's autopilot check, a slice a frame
    If gProbing And gState <> LS_TITLE Then
        Dim before As Long
        before = ld.fuelMax
        If LdProbeRun(gProbeSlice) Then
            gProbing = False
            LogEv "PROBE " & outcomeName(ld.probeOutcome) & ", used " & FInt(ld.probeUsed) & " s of fuel"
            If ld.fuelMax > before Then
                gMsg2 = "TANK TOPPED UP"
                gFrame = 0
            End If
        End If
    End If
End Sub

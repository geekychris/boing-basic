' ApShell - the game shell's 40 ms tick (game.c's game_update): the title's autopilot war, the
' mission, its result, the explosions and smoke for the events, the chase camera easing round,
' the flash texts and the sound. Used by the form and the console bench.
Option Explicit

Public playIn As Long                   ' the player's AP_IN_ bits this tick
Public nextSeed As Long
Public quietEvents As Boolean           ' no sound (the bench)
Private nextPuff As Long

Public Sub ShellFlash(ByVal s As String, ByVal p As Long)
    acFlash = Left$(s, 39)
    acFlashTimer = 40
    acFlashPen = p
End Sub

Private Sub Blast(ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal size As Long)
    Dim k As Long
    For k = 0 To 11
        If blT(k) <= 0 Then
            blT(k) = 12
            blX(k) = ShrA(x, 16): blY(k) = ShrA(y, 16): blZ(k) = ShrA(z, 16)
            blSize(k) = size
            Exit Sub
        End If
    Next k
End Sub

Private Sub Puff(ByVal x As Long, ByVal y As Long, ByVal z As Long, ByVal size As Long)
    Dim k As Long
    k = nextPuff
    nextPuff = (nextPuff + 1) Mod 40
    puT(k) = 40: puX(k) = x: puY(k) = y: puZ(k) = z: puSize(k) = size
End Sub

' smoke from the damaged and the falling, and from what burns below
Private Sub Smoke()
    Dim k As Long
    For k = 0 To 39
        If puT(k) > 0 Then puT(k) = puT(k) - 1
    Next k
    If apTicks Mod 3 <> 0 Then Exit Sub
    For k = 0 To apNP - 1
        If plState(k) = PS_FALL Or (plState(k) = PS_FLY And plHp(k) * 2 < plMaxHp(k)) Then
            Puff ShrA(plX(k), 16), ShrA(plY(k), 16), ShrA(plZ(k), 16), IIf(plState(k) = PS_FALL, 5, 3)
        End If
    Next k
    If apTicks Mod 12 <> 0 Then Exit Sub
    For k = 0 To apNGr - 1
        If grAlive(k) = 0 And grType(k) <> GT_BALLOON Then Puff ShrA(grX(k), 16), 8, ShrA(grZ(k), 16), 7
    Next k
End Sub

Private Sub ClearEffects()
    Dim k As Long
    For k = 0 To 11: blT(k) = 0: Next k
    For k = 0 To 39: puT(k) = 0: Next k
End Sub

Private Sub HandleEvents()
    Dim t As Long, a As Long, b As Long, x As Long, y As Long, z As Long, quiet As Boolean, s As String
    quiet = acState = AS_TITLE
    Do While ApPopEvent(t, a, b, x, y, z)
        Select Case t                    ' what is seen happens in the demo too
            Case APE_KILL: Blast x, y, z, 26
            Case APE_GKILL: Blast x, y, z, IIf(b = GT_BALLOON, 40, 30)
            Case APE_CRASH: Blast x, y + 4 * 65536, z, 34
            Case APE_HURT: If Not quiet Then acHurtTimer = 5
        End Select
        If Not quiet Then
            If Not quietEvents Then SoundEvent t, a
            Select Case t
                Case APE_KILL
                    If b = PT_FALCON Then
                        s = "THE GREY FALCON"
                    ElseIf b = PT_HERON Then
                        s = "A HERON"
                    Else
                        s = UCase$(apPlaneName(b))
                    End If
                    ShellFlash s & " DOWN", IIf(b = PT_HERON, PEN_RED, PEN_GREEN)
                Case APE_GKILL: ShellFlash UCase$(apGroundName(b)) & " DESTROYED", PEN_GREEN
                Case APE_UNJAM: ShellFlash "GUNS CLEARED", PEN_GREEN
                Case APE_WAYPOINT: ShellFlash "MARKER " & a & " OF " & b, PEN_GREEN
                Case APE_HOMEWARD: ShellFlash "WELL DONE: NOW HOME", PEN_GREEN
                Case APE_DONE: ShellFlash "MISSION COMPLETE", PEN_GREEN
                Case APE_FAILED
                    If a = 1 Then
                        s = "THE TRAIN GOT THROUGH"
                    ElseIf a = 2 Then
                        If apMission = 5 Then s = "THE DEPOT IS LOST" Else s = "THE HERONS ARE LOST"
                    Else
                        s = "MISSION FAILED"
                    End If
                    ShellFlash s, PEN_RED
                Case APE_DOWN: ShellFlash "YOU ARE HIT - GOING DOWN", PEN_RED
                Case APE_LANDED: ShellFlash "LANDED", PEN_GREEN
                Case APE_REARMED: ShellFlash "REARMED AND REPAIRED", PEN_GREEN
                Case APE_BOMBS: ShellFlash "A BOMBER GOT THROUGH", PEN_RED
                Case APE_ALLY_LOST: ShellFlash "A HERON IS DOWN", PEN_RED
                Case APE_ARRIVE
                    If apMission = 3 Then ShellFlash IIf(plHome(a) <> 0, "A HERON IS HOME", "THE HERONS ARE OVER ORME"), PEN_GREEN
                Case APE_EDGE: ShellFlash "THE EDGE OF THE SECTOR", PEN_RED
            End Select
        End If
    Loop
End Sub

Public Sub MissionStart()
    acMScore = apScore: acMKills = apKills: acMGKills = apGKills
    acMShots = apShots: acMHits = apHits
    acCamYaw = plYaw(0)
    ClearEffects
End Sub

Public Sub ShellBrief()
    acState = AS_BRIEF
    acStateTimer = 15
    MissionStart
End Sub

Public Sub ShellStartGame(ByVal mission As Long, ByVal briefing As Boolean)
    ApNewGame nextSeed, mission
    nextSeed = nextSeed + 1
    acPaused = 0
    acHelp = 0
    acAutoplay = False
    If briefing Then
        ShellBrief
    Else
        acState = AS_PLAY
        MissionStart
    End If
End Sub

' the title's war: one of five missions, the autopilot flying it
Public Sub ShellDemo()
    ApNewGame 777 + nextSeed, Choose((nextSeed Mod 5) + 1, 8, 2, 1, 7, 5)
    nextSeed = nextSeed + 1
    acCamYaw = plYaw(0)
    ClearEffects
End Sub

Public Sub ShellToTitle()
    acState = AS_TITLE
    acAutoplay = False
    ShellDemo
End Sub

' the mission over: on to the next, or the same again, or the end
Public Sub ShellNext()
    If ApNext() Then
        ShellBrief
    Else
        acState = AS_OVER
        acStateTimer = 30
        If apScore > acBest Then acBest = apScore
        If Not quietEvents Then SoundEnd apWon <> 0
    End If
End Sub

' one 40 ms tick
Public Sub ShellTick()
    Dim k As Long, d As Long, inp As Long
    acTicks = acTicks + 1
    If acHelp <> 0 Or acPaused <> 0 Then Exit Sub
    If acStateTimer > 0 Then acStateTimer = acStateTimer - 1
    If acFlashTimer > 0 Then acFlashTimer = acFlashTimer - 1
    If acState = AS_TITLE Or acState = AS_SCORES Then
        If apOver <> 0 Or apWon <> 0 Or (apPhase >= PH_DONE And apEndT = 0) Or apMTick > 6000 Then ShellDemo
        ApTick ApBot()
    ElseIf acState = AS_PLAY Or acState = AS_RESULT Then
        If acState = AS_PLAY Then
            If acAutoplay Then inp = ApBot() Else inp = playIn
        End If
        ApTick inp
        If acState = AS_PLAY And apPhase >= PH_DONE And apEndT = 0 Then
            acState = AS_RESULT
            acResult = apPhase
            acStateTimer = 25
            If apScore > acBest Then acBest = apScore
        End If
    Else
        Exit Sub
    End If
    HandleEvents
    Smoke
    d = ((plYaw(0) - acCamYaw + 32768) And &HFFFF&) - 32768      ' the chase camera eases round
    acCamYaw = (acCamYaw + d \ 4) And &HFFFF&
    For k = 0 To 11
        If blT(k) > 0 Then blT(k) = blT(k) - 1
    Next k
    If acHurtTimer > 0 Then acHurtTimer = acHurtTimer - 1
End Sub

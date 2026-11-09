' OdShell - the game shell's 40 ms tick (game.c's game_update): the title's autopilot game,
' play (the player's thrusters or the autopilot), the thruster sound, the events (sound and
' the flash text), the timers and game over. Used by the form and the console bench.
Option Explicit

Public playIn As Long                   ' the player's OD_IN_ bits this tick
Public nextSeed As Long
Public quietEvents As Boolean           ' no sound (the bench)
Private thrustTimer As Long

Public Sub ShellFlash(ByVal s As String, ByVal p As Long)
    dkFlash = Left$(s, 31)
    dkFlashTimer = 40
    dkFlashPen = p
End Sub

Public Sub ShellStartGame(ByVal lv As Long)
    OdNewGame nextSeed, lv
    nextSeed = nextSeed + 1
    dkState = DS_PLAY
    dkPaused = 0
    dkHelp = 0
    dkAutoplay = False
End Sub

Public Sub ShellToTitle()
    dkState = DS_TITLE
    OdNewGame 777 + nextSeed, 1
End Sub

Private Sub HandleEvents()
    Dim t As Long, a As Long, b As Long, quiet As Boolean
    quiet = dkState = DS_TITLE
    Do While OdPopEvent(t, a, b)
        If Not quiet Then
            If Not quietEvents Then SoundEvent t
            Select Case t
                Case ODE_CRASH, ODE_DEBRIS: ShellFlash "CRASH: " & odFailName(a), PEN_RED
                Case ODE_FUEL_OUT: ShellFlash "OUT OF FUEL", PEN_RED
            End Select
        End If
    Loop
End Sub

' one 40 ms tick
Public Sub ShellTick()
    Dim bits As Long
    dkTicks = dkTicks + 1
    If dkHelp <> 0 Or dkPaused <> 0 Then Exit Sub
    If dkState = DS_TITLE Or dkState = DS_SCORES Then
        If odOver <> 0 Or odWon <> 0 Or odBetween = 1 Then OdNewGame AddW(odSeed, 1), 1 + UModL(odSeed, 3)
        OdTick OdBot()
    ElseIf dkState = DS_PLAY Then
        If dkAutoplay Then bits = OdBot() Else bits = playIn
        OdTick bits
    End If
    If bits <> 0 And odFuel > 0 Then
        thrustTimer = thrustTimer - 1
        If thrustTimer <= 0 Then
            If Not quietEvents Then SoundThrust
            thrustTimer = 6
        End If
    End If
    HandleEvents
    If dkFlashTimer > 0 Then dkFlashTimer = dkFlashTimer - 1
    If dkStateTimer > 0 Then dkStateTimer = dkStateTimer - 1
    If dkState = DS_PLAY And (odOver <> 0 Or odWon <> 0) Then
        dkState = DS_OVER
        dkStateTimer = 40
        If odScore > dkBest Then dkBest = odScore
    End If
End Sub

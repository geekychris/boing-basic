' StShell - the game shell's tick (game.c's game_update): the title's demo or the bot, the
' turn auto-repeat, the rules' tick, the events (sound, the flash text), the timers, game
' over, and the tower turning towards the piece. Used by the form and the console bench.
Option Explicit

Public dasDir As Long, dasTimer As Long
Public autoplay As Boolean              ' the bot plays (B, --bench)
Public nextSeed As Long
Public quietEvents As Boolean           ' no sound (the bench)

Public Sub ShellFlash(ByVal s As String)
    svFlash = s
    svFlashTimer = 40
End Sub

Public Sub ShellStartGame(ByVal mode As Long, ByVal lv As Long)
    StNewGame mode, nextSeed, lv, ((svView + 128) \ 256) And 15
    nextSeed = nextSeed + 1
    svState = SS_PLAY
    svPaused = 0
    svHelp = 0
    dasDir = 0
    BotReset
End Sub

Public Sub ShellToTitle()
    svState = SS_TITLE
    StNewGame MODE_MARATHON, 777 + nextSeed, 1, 0
    BotReset
    TitleRestart
End Sub

Private Sub HandleEvents()
    Dim t As Long, a As Long, b As Long
    Do While StPopEvent(t, a, b)
        If svState = SS_PLAY And Not quietEvents Then SoundEvent t
        Select Case t
            Case STE_CLEAR
                If svState = SS_PLAY Then ShellFlash Choose(IIf(a < 7, a, 6), "RING!", "DOUBLE!", "TRIPLE!", "QUAD!", "PENTA!", "MEGA!")
            Case STE_LEVEL
                If svState = SS_PLAY Then ShellFlash "LEVEL UP"
        End Select
    Loop
End Sub

' one 40 ms tick
Public Sub ShellTick()
    Dim target As Long, d As Long
    svTicks = svTicks + 1
    If svHelp <> 0 Or svPaused <> 0 Then Exit Sub
    If svState = SS_TITLE Or svState = SS_SCORES Or svState = SS_ENTRY Then
        If svState = SS_TITLE Then DemoStep
    ElseIf svState = SS_PLAY Then
        If autoplay Then
            BotTick
        ElseIf dasDir <> 0 Then
            dasTimer = dasTimer - 1
            If dasTimer <= 0 Then            ' held: repeat after 0.28 s
                StMove dasDir
                dasTimer = 1
            End If
        End If
    End If
    If svState <> SS_ENTRY And svState <> SS_SCORES Then StTick 40
    HandleEvents
    If svFlashTimer > 0 Then svFlashTimer = svFlashTimer - 1
    If svStateTimer > 0 Then svStateTimer = svStateTimer - 1
    If svState = SS_PLAY And (stOver <> 0 Or stWon <> 0) Then
        svState = SS_OVER
        svStateTimer = 40
        If stScore > svBest(stMode) Then svBest(stMode) = stScore
    End If
    ' the tower turns towards the piece's column, the short way round
    target = pCol * 256
    d = ((target - svView + 2048) And 4095) - 2048
    If d \ 3 <> 0 Then d = d \ 3
    svView = (svView + d) And 4095
End Sub

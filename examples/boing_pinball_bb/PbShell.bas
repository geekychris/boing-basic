' PbShell - Boing Pinball's screens and timing (game.c's game_input / game_update),
' shared by the form (Pinball.bas) and the console bench: the title (the bot plays
' the chosen table behind the backglass), play, game over, the high scores of each
' table, the help pages. The physics runs in 1/120 s steps from the real time; the
' lights and the title count a 25 Hz clock, as the C's frames.
Option Explicit

Public Const PS_TITLE As Long = 0
Public Const PS_PLAY As Long = 1
Public Const PS_OVER As Long = 2
Public Const PS_ENTRY As Long = 3
Public Const PS_SCORES As Long = 4

' the keys (bits of keysHeld; edges are the keys pressed since the last frame)
Public Const IN_LFLIP As Long = 1
Public Const IN_RFLIP As Long = 2
Public Const IN_PLUNGE As Long = 4
Public Const IN_NL As Long = 8
Public Const IN_NR As Long = 16
Public Const IN_NU As Long = 32
Public Const IN_PAUSE As Long = 64
Public Const IN_HELP As Long = 128
Public Const IN_ESC As Long = 256
Public Const IN_START As Long = 512
Public Const IN_SCORES As Long = 1024

Private Const STEP_US As Long = 8333

Public pState As Long
Public pHelp As Long
Public pPaused As Long
Public pDemo As Boolean
Public botPlay As Boolean
Public stateTimer As Long
Public titleFrames As Long
Public titleHold As Boolean                    ' --screen title/demo: the title's cycle stays where it is
Public entryName As String
Public entryRank As Long
Public keysHeld As Long
Public keysEdge As Long
Public quitRequest As Boolean
Public logStates As Boolean
Public stepsRun As Long
Public musicPath As String
Public showPerf As Boolean

Private seed As Long
Private plungerLock As Boolean
Private pendNx As Long, pendNy As Long
Private accUs As Long
Private animMs As Double
Private lastState As Long

Public Function TableKey(ByVal t As Long) As String
    TableKey = Choose(t + 1, "comet", "deep", "foundry")
End Function

Private Sub LoadScores()
    HsSetup Array("BOING", "AMIGA", "PAULA", "DENISE", "AGNUS", "GARY", "LISA", "ALICE"), 5000
    HsLoad HsPath("boing_pinball_" & TableKey(dTable) & ".scores")
    bestScore = hsScore(0)
End Sub

Public Sub ChooseTable(ByVal which As Long)
    DrawBuild which
    LoadScores
    GameInit seed
End Sub

Private Sub StartDemo()
    pDemo = True
    GameInit seed
    seed = seed + 1
    GameStart
    BotReset MulW(seed, -1640531535)                ' seed * 2654435761, as the C
    DrawFollow True
    titleFrames = 0
End Sub

Public Sub ToTitle()
    pState = PS_TITLE
    pPaused = 0
    StartDemo
End Sub

Public Sub StartGame(ByVal which As Long)
    If which <> dTable Then ChooseTable which
    pDemo = False
    GameInit seed
    seed = seed + 1
    GameStart
    pState = PS_PLAY
    pPaused = 0
    plungerLock = True
    accUs = 0
    DrawFollow True
End Sub

Public Sub ShellInit(cv As Object, ByVal firstSeed As Long)
    PbCoreInit
    DrawInit cv
    DrawLoadTitles
    seed = firstSeed
    If seed = 0 Then seed = 1
    lastState = -1
    ChooseTable TB_COMET
    ToTitle
End Sub

' a key went down or up (the form's KeyDown/KeyUp, or the bench)
Public Sub ShellKeys(ByVal bits As Long, ByVal down As Boolean)
    If down Then
        keysEdge = keysEdge Or (bits And Not keysHeld)
        keysHeld = keysHeld Or bits
    Else
        keysHeld = keysHeld And Not bits
    End If
End Sub

Private Sub ToScores(ByVal rank As Long)
    entryRank = rank
    pState = PS_SCORES
    stateTimer = 250
End Sub

' the menus' keys
Private Sub Menus()
    Dim e As Long, r As Long
    e = keysEdge
    keysEdge = 0
    If e And IN_HELP Then
        pHelp = (pHelp + 1) Mod 3
        Exit Sub
    End If
    If pHelp Then
        If e And (IN_PLUNGE Or IN_START Or IN_ESC) Then pHelp = 0
        Exit Sub
    End If
    If e And IN_ESC Then
        If pState = PS_TITLE Then quitRequest = True Else ToTitle
        Exit Sub
    End If
    Select Case pState
        Case PS_TITLE
            If e And (IN_NL Or IN_LFLIP) Then ChooseTable (dTable + TB_COUNT - 1) Mod TB_COUNT: StartDemo
            If e And (IN_NR Or IN_RFLIP) Then ChooseTable (dTable + 1) Mod TB_COUNT: StartDemo
            If e And (IN_PLUNGE Or IN_START) Then StartGame dTable
            If e And IN_SCORES Then ToScores -1
        Case PS_PLAY
            If e And IN_PAUSE Then pPaused = 1 - pPaused
            If pPaused Then Exit Sub
            If e And IN_NL Then pendNx = -1
            If e And IN_NR Then pendNx = 1
            If e And IN_NU Then pendNy = 1
        Case PS_OVER
            If stateTimer = 0 And (e And (IN_PLUNGE Or IN_START)) <> 0 Then
                r = HsRank(gScore)
                If r >= 0 And gScore > 0 Then
                    entryName = ""
                    pState = PS_ENTRY
                Else
                    ToScores -1
                End If
            End If
        Case PS_SCORES
            If e And (IN_PLUNGE Or IN_START) Then ToTitle
    End Select
End Sub

' the name typed for a new high score (the form's KeyPress)
Public Sub ShellType(ByVal k As Long)
    Dim ch As String
    If pState <> PS_ENTRY Then Exit Sub
    If k = 13 Then
        If Len(entryName) = 0 Then entryName = "PLAYER"
        entryRank = HsInsert(entryName, gScore)
        HsSave HsPath("boing_pinball_" & TableKey(dTable) & ".scores")
        bestScore = hsScore(0)
        ToScores entryRank
    ElseIf k = 27 Then
        ToScores -1
    ElseIf k = 8 Then
        If Len(entryName) > 0 Then entryName = Left$(entryName, Len(entryName) - 1)
    Else
        ch = UCase$(Chr$(k And 255))
        If Len(entryName) < 8 And ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then entryName = entryName & ch
    End If
End Sub

' dtMs of real time has passed: run the physics, then draw one picture (not shown: the caller Refreshes)
Public Sub ShellFrame(ByVal dtMs As Double)
    Dim steps As Long, h As Long
    Menus
    accUs = accUs + CLng(dtMs * 1000#)
    If accUs > 100000 Then accUs = 100000           ' at most 0.1 s behind
    If pHelp <> 0 Or pPaused <> 0 Or pState = PS_ENTRY Then accUs = 0
    Do While accUs >= STEP_US
        accUs = accUs - STEP_US
        If pDemo Or botPlay Then
            PbBot
        Else
            h = keysHeld
            If (h And IN_LFLIP) Then inLeft = 1 Else inLeft = 0
            If (h And IN_RFLIP) Then inRight = 1 Else inRight = 0
            If (h And IN_PLUNGE) = 0 Then plungerLock = False
            If (h And IN_PLUNGE) <> 0 And Not plungerLock Then inPlunger = 1 Else inPlunger = 0
            inPullTo = -1
            inNudgeX = 0: inNudgeY = 0
        End If
        If steps = 0 Then
            inNudgeX = pendNx: inNudgeY = pendNy
            pendNx = 0: pendNy = 0
        End If
        GameTick
        steps = steps + 1
        stepsRun = stepsRun + 1
        DrawEvents
        If Not pDemo Then SoundEvents
        gNev = 0
        If pDemo And gState = GS_OVER Then StartDemo
    Loop
    ' the 25 Hz clock
    If pHelp = 0 And pPaused = 0 Then animMs = animMs + dtMs
    Do While animMs >= 40#
        animMs = animMs - 40#
        DrawAge
        If stateTimer > 0 Then stateTimer = stateTimer - 1
        If pState = PS_TITLE And Not titleHold Then titleFrames = titleFrames + 1
        If pState = PS_SCORES And stateTimer = 0 Then ToTitle
    Loop
    If pState = PS_PLAY And gState = GS_OVER Then
        pState = PS_OVER
        stateTimer = 40
    End If
    If pHelp = 0 And pPaused = 0 Then DrawFollow False
    If logStates And pState <> lastState Then
        Print "state " & Choose(pState + 1, "title", "play", "over", "entry", "scores") & " " & tName & " score " & gScore
    End If
    lastState = pState
End Sub

Public Sub ShellDraw()
    If pHelp Then
        DrawHelp pHelp
    Else
        Select Case pState
            Case PS_TITLE: DrawTitle titleFrames
            Case PS_ENTRY: DrawScores -1, entryName, True
            Case PS_SCORES: DrawScores entryRank, "", False
            Case Else: DrawGame pState = PS_OVER, pPaused <> 0, stateTimer
        End Select
    End If
End Sub

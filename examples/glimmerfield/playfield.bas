' Glimmerfield - the playfield form: title, play, name entry, high scores
'
'   Glimmerfield                 play (Space fires, cursor keys fly)
'   Glimmerfield --attract       the bot plays from a fixed seed, forever
'   Glimmerfield --bench N       the bot plays N frames as fast as it can,
'                                then prints a timing report and quits
'   Glimmerfield --blit M        how frames reach the window (Canvas.BlitMode 0-3)
'   Glimmerfield --perf          timing overlay on screen and in the log
'   Glimmerfield --lives N --log tests: N lives, and print each change of screen
'   Glimmerfield --nosound       music and effects off (with --bench: off unless --sound)
'
' Keys: Left/Right turn, Up thrust, Space fire, P pause, M music on/off, S effects on/off,
' F1 timing overlay, Esc back to the title (or quit from the title).
Option Explicit

Private Const MODE_TITLE As Long = 0
Private Const MODE_PLAY As Long = 1
Private Const MODE_ENTRY As Long = 2
Private Const MODE_SCORES As Long = 3

Private Const ATTRACT_SEED As Long = 1987



Private mode As Long
Private modeTimer As Long
Private paused As Boolean
Private attractOnly As Boolean
Private benchN As Long
Private benchDone As Long
Private entryName As String
Private entryRank As Long
Private attractGames As Long
Private keyDown(0 To 255) As Boolean
Private firePressed As Boolean
Private startLives As Long          ' --lives N (tests): lives at the start of a game
Private logModes As Boolean         ' --log: print each change of screen
Private noSound As Boolean          ' --nosound
Private benchSound As Boolean       ' --sound (with --bench)

' totals for the --bench report
Private benchLogic As Double
Private benchDraw As Double
Private benchBlit As Double
Private benchWorst As Double

Private Function ScorePath() As String
    Dim p As String
    p = App.Path
    If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    ScorePath = p & "glimmerfield.scores"
End Function

Private Function AppDir() As String
    Dim p As String
    p = App.Path
    If Len(p) > 0 And Right$(p, 1) <> ":" And Right$(p, 1) <> "/" Then p = p & "/"
    AppDir = p
End Function

Private Sub ParseArgs()
    Dim args() As String, i As Long
    args = Split(Trim$(Command$), " ")
    i = 0
    Do While i <= UBound(args)
        Select Case LCase$(args(i))
            Case "--bench"
                benchN = 1000
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then
                        i = i + 1
                        benchN = CLng(args(i))
                    End If
                End If
            Case "--attract"
                attractOnly = True
            Case "--perf"
                showPerf = True
                perfLog = True
            Case "--lives"
                If i < UBound(args) Then
                    i = i + 1
                    startLives = CLng(args(i))
                End If
            Case "--log"
                logModes = True
            Case "--nosound"
                noSound = True
            Case "--sound"
                benchSound = True
            Case "--blit"
                If i < UBound(args) Then
                    i = i + 1
                    view.BlitMode = CLng(args(i))
                End If
        End Select
        i = i + 1
    Loop
End Sub

Private Sub SetMode(ByVal m As Long)
    mode = m
    If logModes Then Print "mode " & Choose(m + 1, "title", "play", "entry", "scores") & " score " & CStr(score)
End Sub

Private Sub StartAttract()
    SetMode MODE_TITLE
    modeTimer = 0
    botMode = True
    attractGames = 0
    NewGame ATTRACT_SEED
End Sub

Private Sub StartPlay()
    botMode = False
    NewGame CLng(Timer * 100) Mod 100000
    If startLives > 0 Then lives = startLives
    SetMode MODE_PLAY
End Sub

Private Sub Form_Load()
    InitTables
    InitRender
    HsLoad ScorePath()
    ParseArgs
    SoundInit AppDir(), Not noSound And (benchN = 0 Or benchSound)
    PerfReset
    StartAttract
    If benchN > 0 Then showPerf = True      ' the first tick starts the bench (RunBench)
End Sub

Private Sub Form_Deactivate()
    If logModes Then Print "inactive"
End Sub

Private Sub Form_Activate()
    If logModes Then Print "active"
End Sub

' --bench: run the frames back to back, keeping the window alive. Started by the first Timer
' tick, not by Form_Activate: on a shared screen another window may stay in front.
Private Sub RunBench()
    Dim t0 As Double, t As Double
    t0 = NowMs()
    Do While benchDone < benchN
        FrameStep
        benchDone = benchDone + 1
        DoEvents
    Loop
    t = NowMs() - t0
    BenchReport t
    Unload Me
End Sub

Private Sub tick_Timer()
    If benchN > 0 Then
        If benchDone = 0 Then
            tick.Enabled = False
            RunBench
        End If
        Exit Sub
    End If
    If Not paused Then FrameStep
End Sub

Private Sub ReadKeys()
    keyLeft = keyDown(vbKeyLeft)
    keyRight = keyDown(vbKeyRight)
    keyThrust = keyDown(vbKeyUp)
    keyFire = keyDown(vbKeySpace)
End Sub

' One frame: logic, drawing, blit, timed separately.
Private Sub FrameStep()
    Dim t As Double
    PerfBegin
    t = NowMs()
    Select Case mode
        Case MODE_TITLE
            GameStep
            If state = ST_GAMEOVER And overTimer = 0 Then
                attractGames = attractGames + 1
                NewGame ATTRACT_SEED + attractGames
            End If
            modeTimer = modeTimer + 1
            If firePressed And Not attractOnly And benchN = 0 Then StartPlay
        Case MODE_PLAY
            ReadKeys
            GameStep
            If state = ST_GAMEOVER And overTimer = 0 Then
                entryRank = HsRank(score)
                If entryRank >= 0 Then
                    entryName = ""
                    SetMode MODE_ENTRY
                Else
                    modeTimer = 400
                    SetMode MODE_SCORES
                End If
            End If
        Case MODE_ENTRY
            GameStep
        Case MODE_SCORES
            GameStep
            modeTimer = modeTimer - 1
            If modeTimer <= 0 Or firePressed Then StartAttract
    End Select
    firePressed = False
    PerfAdd PH_LOGIC
    t = NowMs() - t
    benchLogic = benchLogic + t

    t = NowMs()
    DrawWorld view
    DrawOverlay
    PerfAdd PH_DRAW
    benchDraw = benchDraw + (NowMs() - t)

    t = NowMs()
    view.Flip
    PerfAdd PH_BLIT
    benchBlit = benchBlit + (NowMs() - t)
    PerfEnd
    If perfWorst > benchWorst Then benchWorst = perfWorst
    PlaySounds
End Sub

' a dark panel with a frame, so text stays readable over the game
Private Sub Panel(ByVal y1 As Long, ByVal y2 As Long)
    view.Box 40, y1, ARENA_W - 80, y2 - y1, pal(0)
    view.Rect 40, y1, ARENA_W - 80, y2 - y1, pal(24)
End Sub

Private Sub DrawOverlay()
    Dim i As Long, y As Long, c As Long
    Select Case mode
        Case MODE_TITLE
            If benchN > 0 Then
                DrawCentred view, 40, "BENCHMARK " & CStr(benchDone) & " / " & CStr(benchN), pal(7)
                Exit Sub
            End If
            Panel 48, 248
            DrawCentred view, 60, "G L I M M E R F I E L D", pal(COL_HUE0)
            If (modeTimer \ 300) Mod 2 = 0 Then
                DrawCentred view, 90, "SHOOT THE CRYSTALS BEFORE THEY GROW BACK", pal(6)
                DrawCentred view, 106, "BEWARE THE WISPS", pal(COL_WISP)
                DrawCentred view, 140, "CURSOR KEYS FLY    SPACE FIRES", pal(6)
            Else
                For i = 0 To HS_COUNT - 1
                    DrawCentred view, 90 + i * 14, HsLine(i), pal(6)
                Next i
            End If
            If Not attractOnly And (modeTimer And 32) = 0 Then
                DrawCentred view, 230, "PRESS SPACE TO PLAY", pal(7)
            End If
            DrawCentred view, 200, SoundStatus(), pal(6)
        Case MODE_PLAY
            If state = ST_GAMEOVER Then DrawCentred view, 130, "GAME OVER", pal(28)
            If paused Then DrawCentred view, 150, "PAUSED", pal(7)
        Case MODE_ENTRY
            Panel 78, 186
            DrawCentred view, 90, "A NEW HIGH SCORE!", pal(7)
            DrawCentred view, 110, "PLACE " & CStr(entryRank + 1) & "   " & Format$(score, "0000000"), pal(6)
            DrawCentred view, 140, "TYPE YOUR NAME: " & entryName & IIfS((frame And 16) = 0, "_", " "), pal(COL_HUE0)
            DrawCentred view, 170, "RETURN TO CONFIRM", pal(6)
        Case MODE_SCORES
            Panel 38, 200
            DrawCentred view, 50, "HIGH SCORES", pal(7)
            For i = 0 To HS_COUNT - 1
                If i = entryRank Then c = pal(COL_HUE0 + 3) Else c = pal(6)
                DrawCentred view, 80 + i * 14, HsLine(i), c
            Next i
    End Select
End Sub

Private Function IIfS(ByVal cond As Boolean, ByVal a As String, ByVal b As String) As String
    If cond Then
        IIfS = a
    Else
        IIfS = b
    End If
End Function

Private Sub PlaySounds()
    ' sfx holds this frame's events (Game.bas SFX_*); effects only while a person plays
    SoundFrame sfx, ship.thrust And ship.alive, mode = MODE_PLAY And Not paused
End Sub

Private Sub BenchReport(ByVal totalMs As Double)
    Dim n As Double
    n = benchN
    If totalMs <= 0# Then totalMs = 0.001
    Print "Glimmerfield --bench " & CStr(benchN) & " (bot, seed " & CStr(ATTRACT_SEED) & ")"
    Print "state: score " & CStr(score) & " wave " & CStr(wave) & " games " & CStr(attractGames) & _
          " hash " & CStr(StateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame, worst 1 s window frame " & _
          Format$(benchWorst, "0.0") & " ms"
    Print "blit: " & view.BlitInfo
    If benchSound Then Print "sound: " & SoundStatus() & ", mixer cpu " & Format$(SoundCpu() / 10#, "0.0") & " %"
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    keyDown(KeyCode And 255) = True
    Select Case KeyCode
        Case vbKeySpace, vbKeyReturn
            firePressed = True
        Case vbKeyF1
            showPerf = Not showPerf
        Case vbKeyP
            If mode = MODE_PLAY Then paused = Not paused: SoundPause paused
        Case vbKeyM
            If mode <> MODE_ENTRY Then SoundToggleMusic
        Case vbKeyS
            If mode <> MODE_ENTRY Then SoundToggleEffects
        Case vbKeyEscape
            Select Case mode
                Case MODE_TITLE
                    Unload Me
                Case MODE_ENTRY
                    ' keep the old table
                    modeTimer = 400
                    entryRank = -1
                    SetMode MODE_SCORES
                Case Else
                    StartAttract
            End Select
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyDown(KeyCode And 255) = False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If mode <> MODE_ENTRY Then Exit Sub
    If KeyAscii = 13 Then
        If Len(entryName) = 0 Then entryName = "PILOT"
        entryRank = HsInsert(entryName, score)
        If Not HsSave(ScorePath()) And logModes Then Print "cannot save " & ScorePath()
        modeTimer = 500
        SetMode MODE_SCORES
        firePressed = False
    ElseIf KeyAscii = 8 Then
        If Len(entryName) > 0 Then entryName = Left$(entryName, Len(entryName) - 1)
    Else
        ch = UCase$(Chr$(KeyAscii))
        If Len(entryName) < 8 And ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then
            entryName = entryName & ch
        End If
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    tick.Enabled = False
    If logModes Then Print "bye"
End Sub

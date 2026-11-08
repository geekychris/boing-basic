' Glimmerfield - the playfield form: title, play, name entry, high scores
'
'   Glimmerfield                 play (Space fires, cursor keys fly)
'   Glimmerfield --attract       the bot plays from a fixed seed, forever
'   Glimmerfield --bench N       the bot plays N frames as fast as it can,
'                                then prints a timing report and quits
'
' Keys: Left/Right turn, Up thrust, Space fire, P pause, F1 timing overlay,
' Esc back to the title (or quit from the title).
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
        End Select
        i = i + 1
    Loop
End Sub

Private Sub StartAttract()
    mode = MODE_TITLE
    modeTimer = 0
    botMode = True
    attractGames = 0
    NewGame ATTRACT_SEED
End Sub

Private Sub StartPlay()
    mode = MODE_PLAY
    botMode = False
    NewGame CLng(Timer * 100) Mod 100000
End Sub

Private Sub Form_Load()
    InitTables
    InitRender
    HsLoad ScorePath()
    ParseArgs
    PerfReset
    StartAttract
    If benchN > 0 Then
        tick.Enabled = False
        showPerf = True
    End If
End Sub

Private Sub Form_Activate()
    Dim t0 As Double, t As Double
    If benchN <= 0 Or benchDone > 0 Then Exit Sub
    ' --bench: run the frames back to back, keeping the window alive
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
                    mode = MODE_ENTRY
                    entryName = ""
                Else
                    mode = MODE_SCORES
                    modeTimer = 400
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

Private Sub DrawOverlay()
    Dim i As Long, y As Long, c As Long
    Select Case mode
        Case MODE_TITLE
            If benchN > 0 Then
                DrawCentred view, 40, "BENCHMARK " & CStr(benchDone) & " / " & CStr(benchN), pal(7)
                Exit Sub
            End If
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
        Case MODE_PLAY
            If state = ST_GAMEOVER Then DrawCentred view, 130, "GAME OVER", pal(28)
            If paused Then DrawCentred view, 150, "PAUSED", pal(7)
        Case MODE_ENTRY
            DrawCentred view, 90, "A NEW HIGH SCORE!", pal(7)
            DrawCentred view, 110, "PLACE " & CStr(entryRank + 1) & "   " & Format$(score, "0000000"), pal(6)
            DrawCentred view, 140, "TYPE YOUR NAME: " & entryName & IIfS((frame And 16) = 0, "_", " "), pal(COL_HUE0)
            DrawCentred view, 170, "RETURN TO CONFIRM", pal(6)
        Case MODE_SCORES
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
    ' no sound API yet; sfx holds this frame's events (Game.bas SFX_*)
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
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    keyDown(KeyCode And 255) = True
    Select Case KeyCode
        Case vbKeySpace, vbKeyReturn
            firePressed = True
        Case vbKeyF1
            showPerf = Not showPerf
        Case vbKeyP
            If mode = MODE_PLAY Then paused = Not paused
        Case vbKeyEscape
            Select Case mode
                Case MODE_TITLE
                    Unload Me
                Case MODE_ENTRY
                    ' keep the old table
                    mode = MODE_SCORES
                    modeTimer = 400
                    entryRank = -1
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
        HsSave ScorePath()
        mode = MODE_SCORES
        modeTimer = 500
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
End Sub

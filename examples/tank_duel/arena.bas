' Tank Duel - the arena form: title (the autopilot fights behind it), the fight,
' game over, a new high score, the help pages.
'
'   TankDuel                    play
'   TankDuel --round N          start at round N (also Up/Down on the title)
'   TankDuel --bench N          the autopilot fights N ticks as fast as it can,
'                               drawing every frame, then prints a timing report
'   TankDuel --attract          the title's autopilot fight only, forever
'   TankDuel --perf             timing overlay (also F1) and a log line a second
'   TankDuel --log              print each change of screen (tests)
'   TankDuel --seed N           the first game's seed
'
' Keys: cursor keys / WASD drive, Space fires, P pause, B autopilot, Help/H the
' rules, Esc back to the title (or quit from it). F1 the timing overlay.
Option Explicit

Private Const DS_TITLE As Long = 0
Private Const DS_PLAY As Long = 1
Private Const DS_OVER As Long = 2
Private Const DS_ENTRY As Long = 3
Private Const DS_SCORES As Long = 4
Private Const KEY_HELP As Long = 47       ' the Help key (VB's vbKeyHelp)

Private keyIsDown(0 To 255) As Boolean
Private edgeFire As Boolean, edgeUp As Boolean, edgeDown As Boolean
Private fireLock As Boolean
Private benchN As Long, benchDone As Long, attractOnly As Boolean, logModes As Boolean
Private nextSeed As Long
Private lastMs As Double, accMs As Double
Private entryName As String
Private benchLogic As Double, benchDraw As Double, benchBlit As Double

Private Sub ParseArgs()
    Dim args() As String, i As Long, a As String
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        a = LCase$(args(i))
        Select Case a
            Case "--bench"
                benchN = 2000
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then benchN = CLng(args(i + 1))
                End If
            Case "--attract": attractOnly = True
            Case "--perf"
                showPerf = True
                perfLog = True
            Case "--log": logModes = True
            Case "--round"
                If i < UBound(args) Then startRound = CLng(args(i + 1))
            Case "--seed"
                If i < UBound(args) Then nextSeed = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
        End Select
    Next i
    If startRound < 1 Then startRound = 1
    If startRound > TD_ROUNDS Then startRound = TD_ROUNDS
End Sub

Private Sub SetState(ByVal s As Long)
    duState = s
    If logModes Then Print "state " & Choose(s + 1, "title", "fight", "over", "entry", "scores") & _
                           " round " & tdRound & " score " & tdScore
End Sub

Private Sub ToTitle()
    SetState DS_TITLE
    TdNewGame 777 + nextSeed, 1
    ClearBlasts
End Sub

Private Sub StartGame()
    TdNewGame nextSeed, startRound
    nextSeed = nextSeed + 1
    SetState DS_PLAY
    duPaused = False
    duAutoplay = False
    fireLock = True
    ClearBlasts
End Sub

Private Sub Form_Load()
    TdInit
    DrawInit
    SoundInit
    HsSetup Array("ROMMEL", "PATTON", "GUDERIAN", "ZHUKOV", "MONTY", "BRADLEY", "KONEV", "MANTEUF"), 1500
    HsLoad HsPath("tank_duel.scores")
    nextSeed = 1
    startRound = 1
    ParseArgs
    PerfReset
    ToTitle
    If benchN > 0 Then
        showPerf = True
        duAutoplay = True
        TdNewGame 1234, startRound
        SetState DS_PLAY
        duAutoplay = True
    End If
    lastMs = TimerMs()
End Sub

' --bench: the frames back to back, from the first timer tick (the window
' need not be the active one), keeping the window alive
Private Sub RunBench()
    Dim t0 As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        Frame 1
        benchDone = benchDone + 1
        If tdOver <> 0 Or tdWon <> 0 Then
            TdNewGame A3Hash(tdSeed) And &H7FFF&, 1
        End If
        DoEvents
    Loop
    BenchReport TimerMs() - t0
    Unload Me
End Sub

Private Sub tick_Timer()
    Dim now As Double, steps As Long
    If benchN > 0 Then
        If benchDone = 0 Then RunBench
        Exit Sub
    End If
    now = TimerMs()
    accMs = accMs + (now - lastMs)
    lastMs = now
    steps = Int(accMs / 40#)
    If steps < 1 Then steps = 1
    If steps > 4 Then steps = 4
    accMs = accMs - steps * 40#
    If accMs > 40# Or accMs < -40# Then accMs = 0
    Frame steps
End Sub

Private Function PlayInput() As Long
    Dim inp As Long
    If keyIsDown(vbKeyLeft) Or keyIsDown(vbKeyA) Then inp = inp Or TD_IN_LEFT
    If keyIsDown(vbKeyRight) Or keyIsDown(vbKeyD) Then inp = inp Or TD_IN_RIGHT
    If keyIsDown(vbKeyUp) Or keyIsDown(vbKeyW) Then inp = inp Or TD_IN_UP
    If keyIsDown(vbKeyDown) Or keyIsDown(vbKeyS) Then inp = inp Or TD_IN_DOWN
    If keyIsDown(vbKeySpace) Then
        If Not fireLock Then inp = inp Or TD_IN_FIRE
    Else
        fireLock = False
    End If
    PlayInput = inp
End Function

' steps game ticks (40 ms each), then one picture
Private Sub Frame(ByVal steps As Long)
    Dim t As Double, k As Long, r As Long
    PerfBegin
    t = TimerMs()
    ' the menus' keys
    Select Case duState
        Case DS_TITLE
            If edgeUp And startRound < TD_ROUNDS Then startRound = startRound + 1
            If edgeDown And startRound > 1 Then startRound = startRound - 1
            If edgeFire And duHelp = 0 And Not attractOnly Then StartGame
        Case DS_OVER
            If edgeFire And duStateTimer = 0 Then
                r = HsRank(tdScore)
                If r >= 0 And tdScore > 0 Then
                    entryName = ""
                    SetState DS_ENTRY
                Else
                    duStateTimer = 250
                    entryRank = -1
                    SetState DS_SCORES
                End If
            End If
        Case DS_SCORES
            If edgeFire Then ToTitle
    End Select
    edgeFire = False: edgeUp = False: edgeDown = False
    For k = 1 To steps
        If duHelp = 0 And Not duPaused Then
            Select Case duState
                Case DS_TITLE, DS_ENTRY, DS_SCORES
                    If tdOver <> 0 Or tdWon <> 0 Then TdNewGame A3Hash(tdSeed) And &H7FFFFFFF, 1 + UModL(tdSeed, 3)
                    TdTick TdBot()
                Case DS_PLAY
                    If duAutoplay Then TdTick TdBot() Else TdTick PlayInput()
                Case DS_OVER
            End Select
            HandleEvents duState = DS_PLAY
            AgeEffects
            If duStateTimer > 0 Then duStateTimer = duStateTimer - 1
            If duState = DS_PLAY And (tdOver <> 0 Or tdWon <> 0) Then
                SetState DS_OVER
                duStateTimer = 40
            End If
            If duState = DS_SCORES And duStateTimer = 0 Then ToTitle
        End If
    Next k
    PerfAdd PH_LOGIC
    benchLogic = benchLogic + (TimerMs() - t)

    t = TimerMs()
    If duHelp > 0 Then
        DrawHelp view, duHelp
    Else
        Select Case duState
            Case DS_TITLE: DrawTitle view
            Case DS_ENTRY: DrawEntry view, entryName
            Case DS_SCORES: DrawScores view
            Case Else: DrawFight view, duState = DS_OVER
        End Select
    End If
    If showPerf Then DrawPerf view
    PerfAdd PH_DRAW
    benchDraw = benchDraw + (TimerMs() - t)

    t = TimerMs()
    view.Flip
    PerfAdd PH_BLIT
    benchBlit = benchBlit + (TimerMs() - t)
    PerfEnd
End Sub

Private Sub BenchReport(ByVal totalMs As Double)
    Dim n As Double
    n = benchN
    If totalMs <= 0# Then totalMs = 0.001
    Print "Tank Duel --bench " & benchN & " (autopilot, seed 1234, round " & startRound & ")"
    Print "state: round " & tdRound & " score " & tdScore & " kills " & tdKills & " hash " & Hex8(TdStateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & view.Hash
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim already As Boolean
    already = keyIsDown(KeyCode And 255)
    keyIsDown(KeyCode And 255) = True
    If already Then Exit Sub
    If duState = DS_ENTRY Then
        If KeyCode = vbKeyEscape Then
            duStateTimer = 250
            entryRank = -1
            SetState DS_SCORES
        End If
        Exit Sub
    End If
    Select Case KeyCode
        Case KEY_HELP, vbKeyH
            duHelp = (duHelp + 1) Mod 3
        Case vbKeySpace, vbKeyReturn
            If duHelp > 0 Then duHelp = 0 Else edgeFire = True
        Case vbKeyUp, vbKeyW: edgeUp = True
        Case vbKeyDown, vbKeyS: edgeDown = True
        Case vbKeyP
            If duState = DS_PLAY Then duPaused = Not duPaused
        Case vbKeyB
            If duState = DS_PLAY Then duAutoplay = Not duAutoplay
        Case vbKeyF1
            showPerf = Not showPerf
        Case vbKeyEscape
            If duHelp > 0 Then
                duHelp = 0
            ElseIf duState = DS_TITLE Then
                Unload Me
            Else
                ToTitle
            End If
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyIsDown(KeyCode And 255) = False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If duState <> DS_ENTRY Then Exit Sub
    If KeyAscii = 13 Then
        If Len(entryName) = 0 Then entryName = "TANKER"
        entryRank = HsInsert(entryName, tdScore)
        If Not HsSave(HsPath("tank_duel.scores")) And logModes Then Print "cannot save the scores"
        duStateTimer = 300
        SetState DS_SCORES
    ElseIf KeyAscii = 8 Then
        If Len(entryName) > 0 Then entryName = Left$(entryName, Len(entryName) - 1)
    Else
        ch = UCase$(Chr$(KeyAscii))
        If Len(entryName) < 8 And ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then entryName = entryName & ch
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    tick.Enabled = False
    SoundCleanup
    If logModes Then Print "bye"
End Sub

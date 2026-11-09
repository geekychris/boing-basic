' Ridge Runner - the valley form: title (the autopilot races behind it), the race,
' game over, a new high score, the help pages.
'
'   RidgeRunner                    play
'   RidgeRunner --track N          start at track N (also Up/Down on the title)
'   RidgeRunner --bench N          the autopilot races N ticks as fast as it can,
'                               drawing every frame, then prints a timing report
'   RidgeRunner --attract          the title's autopilot only, forever
'   RidgeRunner --perf             timing overlay (also F1) and a log line a second
'   RidgeRunner --log              print each change of screen (tests)
'   --demo                      start a game with the autopilot on (screenshots)
'   --help N / --scores         start on a help page / the high scores
'   RidgeRunner --seed N           the first game's seed
'
' Keys: cursor keys / WASD steer, throttle (up) and brake (down), Space boosts, P pause, B autopilot, Help/H the
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
Private lastTrack As Long
Private demoStart As Boolean, scoresStart As Boolean
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
            Case "--demo": demoStart = True
            Case "--scores": scoresStart = True
            Case "--help"
                duHelp = 1
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then duHelp = CLng(args(i + 1))
                End If
            Case "--track"
                If i < UBound(args) Then startTrack = CLng(args(i + 1))
            Case "--seed"
                If i < UBound(args) Then nextSeed = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
        End Select
    Next i
    If startTrack < 1 Then startTrack = 1
    If startTrack > RR_TRACKS Then startTrack = RR_TRACKS
End Sub

Private Sub SetState(ByVal s As Long)
    duState = s
    If logModes Then Print "state " & Choose(s + 1, "title", "fight", "over", "entry", "scores") & _
                           " track " & rrTrack & " score " & rrScore
End Sub

Private Sub ToTitle()
    SetState DS_TITLE
    RrNewGame 777 + nextSeed, 1
    NewRace False
End Sub

' a race starts: the camera behind the bike, the track's look, the countdown when playing
Private Sub NewRace(ByVal withCountdown As Boolean)
    camYaw = rrYaw
    SetTheme rrTrack
    lastTrack = rrTrack
    If withCountdown Then countdown = 75 Else countdown = 0
    duFlashTimer = 0
End Sub

Private Sub StartGame()
    RrNewGame nextSeed, startTrack
    nextSeed = nextSeed + 1
    SetState DS_PLAY
    duPaused = False
    duAutoplay = False
    fireLock = True
    NewRace True
End Sub

Private Sub Form_Load()
    Set gcv = view
    RrInit
    DrawInit
    SoundInit
    HsSetup Array("VIPER", "BLADE", "DRIFT", "NITRO", "SPARK", "COMET", "RAZOR", "SLIDE"), 3000
    HsLoad HsPath("ridge_runner.scores")
    nextSeed = 1
    startTrack = 1
    ParseArgs
    PerfReset
    ToTitle
    If demoStart Then
        StartGame
        duAutoplay = True
    ElseIf scoresStart Then
        entryRank = -1
        duStateTimer = 30000
        SetState DS_SCORES
    End If
    If benchN > 0 Then
        showPerf = True
        duAutoplay = True
        RrNewGame 1234, startTrack
        NewRace False
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
        If rrOver <> 0 Or rrWon <> 0 Then
            RrNewGame A3Hash(rrSeed), 1
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
    If keyIsDown(vbKeyLeft) Or keyIsDown(vbKeyA) Then inp = inp Or RR_IN_LEFT
    If keyIsDown(vbKeyRight) Or keyIsDown(vbKeyD) Then inp = inp Or RR_IN_RIGHT
    If keyIsDown(vbKeyUp) Or keyIsDown(vbKeyW) Then inp = inp Or RR_IN_UP
    If keyIsDown(vbKeyDown) Or keyIsDown(vbKeyS) Then inp = inp Or RR_IN_DOWN
    If keyIsDown(vbKeySpace) Then
        If Not fireLock Then inp = inp Or RR_IN_FIRE
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
            If edgeUp And startTrack < RR_TRACKS Then startTrack = startTrack + 1
            If edgeDown And startTrack > 1 Then startTrack = startTrack - 1
            If edgeFire And duHelp = 0 And Not attractOnly Then StartGame
        Case DS_OVER
            If edgeFire And duStateTimer = 0 Then
                r = HsRank(rrScore)
                If r >= 0 And rrScore > 0 Then
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
                    If rrOver <> 0 Or rrWon <> 0 Or rrFinished <> 0 Then RrNewGame A3Hash(rrSeed), 1 + UModL(rrSeed, RR_TRACKS)
                    RrTick RrBot()
                Case DS_PLAY
                    If countdown > 0 Then
                        If countdown Mod 25 = 0 Then Sfx SFX_BEEP
                        countdown = countdown - 1
                        If countdown = 0 Then Sfx SFX_GO
                    ElseIf duAutoplay Then
                        RrTick RrBot()
                    Else
                        RrTick PlayInput()
                    End If
                Case DS_OVER
            End Select
            HandleEvents duState = DS_PLAY
            AgeEffects
            ' the camera's heading eases after the bike's
            camYaw = (camYaw + ADiff(rrYaw, camYaw) \ 4) And &HFFFF&
            If rrTrack <> lastTrack Then
                SetTheme rrTrack
                lastTrack = rrTrack
                camYaw = rrYaw
                If duState = DS_PLAY Then countdown = 75
            End If
            If duStateTimer > 0 Then duStateTimer = duStateTimer - 1
            If duState = DS_PLAY And (rrOver <> 0 Or rrWon <> 0) Then
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
        DrawHelp duHelp
    Else
        Select Case duState
            Case DS_TITLE: DrawTitle
            Case DS_ENTRY: DrawEntry entryName
            Case DS_SCORES: DrawScores
            Case Else: DrawGame duState = DS_OVER, duState = DS_PLAY
        End Select
    End If
    If showPerf Then DrawPerf
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
    Print "Ridge Runner --bench " & benchN & " (autopilot, seed 1234, track " & startTrack & ")"
    Print "state: track " & rrTrack & " score " & rrScore & " gates " & rrGatesHit & " hash " & Hex8(RrStateHash())
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
        If Len(entryName) = 0 Then entryName = "RACER"
        entryRank = HsInsert(entryName, rrScore)
        If Not HsSave(HsPath("ridge_runner.scores")) And logModes Then Print "cannot save the scores"
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

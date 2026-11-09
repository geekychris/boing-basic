' ScAIry Fun - the form: the title (the painting, the autopilot driving, the rules in turn), the
' four routes with their arrivals and software updates, the end, a new high score, the high
' scores, the help pages (game.c's shell).
'
'   ScairyFun                     play
'   ScairyFun --bench N           the perfect autopilot drives N frames as fast as it can,
'                                 drawing every frame, then a timing report
'   ScairyFun --route R           start on route R (1-4) straight away, the autopilot on
'   ScairyFun --cockpit           the cockpit view;  --help N / --scores: open on those
'   ScairyFun --smoke N           drive N frames in real time with music, effects and the
'                                 voice, then a report (the guest smoke test)
'   ScairyFun --saveshot PATH --shotframe N   save frame N's picture (PPM) and quit
'   ScairyFun --perf --log --nosound --nomusic --blit N --data DIR
'
' Keys: Left/Right steer (takes over), Down brake (takes over), Up accelerate (driving
' yourself), Space or Return-less fire: the autopilot on/off, V or C the chase / cockpit view,
' P pause, Help/H the rules, Esc the title (or quit from it), M music, S effects, F9 timing.
Option Explicit

Private Const KEY_HELP As Long = 47

Private keyIsDown(0 To 255) As Boolean
Private benchN As Long, benchDone As Long, logModes As Boolean, noSound As Boolean, noMusic As Boolean
Private lastMs As Double, accMs As Double
Private benchLogic As Double, benchDraw As Double, benchBlit As Double
Private lastState As Long, startRoute As Long, startHelp As Long, startScores As Boolean, startCockpit As Boolean
Private gone As Boolean, shotPath As String, shotFrame As Long, frameNo As Long
Private smokeN As Long, smokeDone As Long, showScores As Boolean, scoreTimer As Long, entering As Boolean
Private entryName As String, entryRank As Long, pendingStart As Boolean, lastScore As Long

Private Sub ParseArgs()
    Dim args() As String, i As Long
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        Select Case LCase$(args(i))
            Case "--bench"
                benchN = 2000
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then benchN = CLng(args(i + 1))
                End If
            Case "--smoke"
                smokeN = 500
                If startRoute = 0 Then startRoute = 1
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then smokeN = CLng(args(i + 1))
                End If
            Case "--perf"
                showPerf = True
                perfLog = True
            Case "--log": logModes = True
            Case "--nosound": noSound = True
            Case "--nomusic": noMusic = True
            Case "--cockpit": startCockpit = True
            Case "--scores": startScores = True
            Case "--help"
                startHelp = 1
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then startHelp = CLng(args(i + 1))
                End If
            Case "--route"
                If i < UBound(args) Then startRoute = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
            Case "--data"
                If i < UBound(args) Then dataDir = args(i + 1)
            Case "--saveshot"
                If i < UBound(args) Then shotPath = args(i + 1)
                If shotFrame = 0 Then shotFrame = 50
            Case "--shotframe"
                If i < UBound(args) Then shotFrame = CLng(args(i + 1))
        End Select
    Next i
    If startRoute > NUM_ROUTES Then startRoute = NUM_ROUTES
End Sub

Private Sub LogState()
    If wState <> lastState Then
        If logModes Then Print "state " & Choose(wState + 1, "title", "intro", "play", "arrived", "update", "gameover", "win") & _
                               " route " & (wRoute + 1) & " score " & wScore & " cover " & wCover
        lastState = wState
    End If
End Sub

Private Sub StartOnRoute(ByVal r As Long, ByVal perfect As Boolean)
    WorldStartGame
    If r > 1 Then WorldStartRoute r - 1
    wState = GS_PLAY
    If perfect Then tuAiPerfect = 1
End Sub

Private Sub Form_Load()
    DrawInit view
    HsSetup Array("ROBOTAXI", "CRUISE", "LIDAR", "WAYMO", "TESSA", "PILOT", "AUTOBOT", "BETA"), 5000
    lastState = -1
    entryRank = -1
    ParseArgs
    tuSpeedPct = 0
    WorldInit
    If startCockpit Then wView = CAM_COCKPIT
    If Not noSound Then SoundInit benchN = 0 And Not noMusic
    HsLoad DataFile("scairy_fun.scores")
    If benchN > 0 Then
        quietEvents = True
        showPerf = True
        StartOnRoute IIf(startRoute > 0, startRoute, 1), True
    ElseIf startRoute > 0 Then
        StartOnRoute startRoute, smokeN > 0
    End If
    If startScores Then
        showScores = True
        scoreTimer = 30000
    End If
    If startHelp >= 1 And startHelp <= HELP_PAGES Then helpPage = startHelp
    PerfReset
    LogState
    lastMs = TimerMs()
End Sub

' the bench and the smoke run drive on through the routes
Private Sub KeepDriving()
    If wState = GS_ARRIVED Or wState = GS_UPDATE Or wState = GS_GAMEOVER Or wState = GS_WIN Then
        WorldStartRoute (wRoute + 1) Mod NUM_ROUTES
        wState = GS_PLAY
    End If
End Sub

Private Sub RunBench()
    Dim t0 As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        KeepDriving
        Frame 1
        benchDone = benchDone + 1
        DoEvents
    Loop
    BenchReport TimerMs() - t0
    Unload Me
End Sub

Private Sub tick_Timer()
    Dim now As Double, steps As Long, iv As Long
    If benchN > 0 Then
        If benchDone = 0 Then RunBench
        Exit Sub
    End If
    now = TimerMs()
    TickFrame now
    If gone Then Exit Sub
    ' the timer starts again only when this returns: take this frame's time off the next wait,
    ' so a frame comes every 20 ms, or as soon as the last one is done when it took longer
    iv = 20 - CLng(TimerMs() - now)
    If iv < 1 Then iv = 1
    If tick.Interval <> iv Then tick.Interval = iv
End Sub

Private Sub TickFrame(ByVal now As Double)
    Dim steps As Long
    accMs = accMs + (now - lastMs)
    lastMs = now
    steps = Int(accMs / 40#)
    If steps > 4 Then steps = 4
    accMs = accMs - steps * 40#
    If accMs > 80# Or accMs < -40# Then accMs = 0
    If smokeN > 0 Then KeepDriving
    Frame steps
    frameNo = frameNo + 1
    If Len(shotPath) > 0 And frameNo >= shotFrame Then
        view.SaveImage shotPath
        Print "saved " & shotPath & " at frame " & frameNo
        gone = True
        Unload Me
        Exit Sub
    End If
    If smokeN > 0 Then
        smokeDone = smokeDone + 1
        If smokeDone >= smokeN Then
            Print "ScAIry Fun smoke: " & smokeN & " frames, route " & (wRoute + 1) & " seg " & SegOf(carZ) & " score " & wScore & _
                  " cover " & wCover & " fps " & Format$(perfFps, "0.0") & " (" & PerfText() & ")"
            If Not au Is Nothing Then Print "audio: " & au.Device & ", music " & IIf(au.Playing, "playing", "stopped") & _
                                            ", voice lines " & voiceCount & ", effects " & sfxCount(SFX_CHIME_ON) & " chimes"
            Print "picture hash " & view.Hash
            gone = True
            Unload Me
        End If
    End If
End Sub

Private Function InputBits() As Long
    Dim b As Long
    If keyIsDown(vbKeyLeft) Then b = b Or IN_LEFT
    If keyIsDown(vbKeyRight) Then b = b Or IN_RIGHT
    If keyIsDown(vbKeyUp) Then b = b Or IN_UP
    If keyIsDown(vbKeyDown) Then b = b Or IN_DOWN
    If keyIsDown(vbKeySpace) Then b = b Or IN_FIRE
    If keyIsDown(vbKeyReturn) Or keyIsDown(vbKeyF1) Then b = b Or IN_START
    InputBits = b
End Function

Private Sub Frame(ByVal steps As Long)
    Dim t As Double, k As Long, inp As Long, prev As Long
    PerfBegin
    t = TimerMs()
    TitleCycle TimerMs(), HasTitleArt(view)
    inp = InputBits()
    If showScores Or entering Then inp = 0
    If pendingStart Then
        inp = inp Or IN_START
        pendingStart = False
    End If
    prev = wState
    For k = 1 To steps
        If wState = GS_GAMEOVER Or wState = GS_WIN Then lastScore = wScore
        ShellTick inp
        If (prev = GS_GAMEOVER Or prev = GS_WIN) And wState = GS_TITLE Then AfterGame
        prev = wState
    Next k
    If showScores And Not entering Then
        scoreTimer = scoreTimer - steps
        If scoreTimer <= 0 Then showScores = False
    End If
    LogState
    PerfAdd PH_LOGIC
    benchLogic = benchLogic + (TimerMs() - t)
    t = TimerMs()
    If entering Then
        DrawEntry
    ElseIf showScores Then
        DrawScoreTable
    Else
        DrawFrame view
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

' the game over (cancelled or home): a new high score (name entry) or the table
Private Sub AfterGame()
    If HsRank(lastScore) >= 0 And lastScore > 0 Then
        entryName = ""
        entering = True
    Else
        entryRank = -1
        showScores = True
        scoreTimer = 250
    End If
End Sub

Private Sub DrawEntry()
    Dim cur As String
    DrawFrame view
    GBox view, 40, 70, 280, 180, PEN_PANEL, PEN_YELLOW
    GTextCentre view, 90, PEN_YELLOW, "A NEW HIGH SCORE!"
    GTextCentre view, 110, PEN_WHITE, "PLACE " & (HsRank(lastScore) + 1) & "   " & lastScore
    If (wFrame And 8) = 0 Then cur = "_" Else cur = " "
    GTextCentre view, 140, PEN_AI2, "YOUR NAME: " & entryName & cur
    GTextCentre view, 166, PEN_GREY, "RETURN TO CONFIRM"
End Sub

Private Sub DrawScoreTable()
    Dim i As Long, p As Long
    DrawFrame view
    GBox view, 50, 30, 270, 196, PEN_PANEL, PEN_AI
    GTextBig view, (G_W - GTextBigWidth(view, "HIGH SCORES", 2)) \ 2, 38, PEN_AI, "HIGH SCORES", 2
    For i = 0 To HS_COUNT - 1
        If i = entryRank Then p = PEN_AI2 Else p = PEN_WHITE
        GTextCentre view, 80 + i * 14, p, HsLine(i)
    Next i
End Sub

Private Sub BenchReport(ByVal totalMs As Double)
    Dim n As Double
    n = benchN
    If totalMs <= 0# Then totalMs = 0.001
    Print "ScAIry Fun --bench " & benchN & " (the perfect autopilot from route " & IIf(startRoute > 0, startRoute, 1) & ")"
    Print "state: route " & (wRoute + 1) & " seg " & SegOf(carZ) & " score " & wScore & " hash " & Hex8(ScStateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & view.Hash
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim already As Boolean, k As Long
    k = KeyCode And 255
    already = keyIsDown(k)
    keyIsDown(k) = True
    If already Then Exit Sub
    If entering Then
        If k = vbKeyEscape Then
            entering = False
            entryRank = -1
            showScores = True
            scoreTimer = 250
        End If
        Exit Sub
    End If
    If showScores Then
        If k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyEscape Then showScores = False
        Exit Sub
    End If
    If k = KEY_HELP Or k = vbKeyH Then
        If helpPage < HELP_PAGES Then helpPage = helpPage + 1 Else helpPage = 0
        helpAuto = False
        Exit Sub
    End If
    If helpPage <> 0 And Not helpAuto And wState <> GS_TITLE Then
        If k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1 Or k = vbKeyEscape Then
            helpPage = 0                         ' back to the game; this press does nothing else
            keyIsDown(k) = False
            Exit Sub
        End If
    End If
    Select Case k
        Case vbKeyF9: showPerf = Not showPerf
        Case vbKeyM: ToggleMusic
        Case vbKeyS: ToggleEffects
        Case vbKeyV, vbKeyC: wView = wView Xor 1
        Case vbKeyP
            If wState <> GS_TITLE Then paused = Not paused
        Case vbKeyEscape
            If wState = GS_TITLE Then
                Unload Me
            Else
                tuSpeedPct = 0
                tuAiPerfect = 0
                WorldInit
            End If
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyIsDown(KeyCode And 255) = False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If Not entering Then Exit Sub
    If KeyAscii = 13 Then
        If Len(entryName) = 0 Then entryName = "DRIVER"
        entryRank = HsInsert(entryName, lastScore)
        If Not HsSave(DataFile("scairy_fun.scores")) And logModes Then Print "cannot save the scores"
        entering = False
        showScores = True
        scoreTimer = 300
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

' Canyon Rail - the canyon form: title (the autopilot rides behind it), the ride,
' game over, a new high score, the help pages.
'
'   CanyonRail                    play
'   CanyonRail --stage N          start at stage N (also Up/Down on the title)
'   CanyonRail --bench N          the autopilot rides N ticks as fast as it can,
'                               drawing every frame, then prints a timing report
'   CanyonRail --attract          the title's autopilot only, forever
'   CanyonRail --perf             timing overlay (also F1) and a log line a second
'   CanyonRail --log              print each change of screen (tests)
'   --demo                      start a game with the autopilot on (screenshots)
'   --help N / --scores         start on a help page / the high scores
'   --front                     move the window to the top left and to the front (screenshots)
'   --saveshot PATH --shotframe N   save frame N (default 150) as a PPM and quit (guest screenshots)
'   --nosound                   no sound
'   --saveshot PATH --shotframe N   save frame N (default 150) as a PPM and quit (guest screenshots)
'   CanyonRail --seed N           the first game's seed
'
' Keys: cursor keys / WASD move the sight, Space fires (hold), P pause, B autopilot, Help/H the
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
Private demoStart As Boolean, scoresStart As Boolean, frontReq As Boolean
Private saveShot As String, shotFrame As Long, frameNo As Long
Private noSound As Boolean
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
            Case "--front": frontReq = True
            Case "--nosound": noSound = True
            Case "--saveshot"
                If i < UBound(args) Then saveShot = args(i + 1)
            Case "--shotframe"
                If i < UBound(args) Then shotFrame = CLng(args(i + 1))
            Case "--scores": scoresStart = True
            Case "--help"
                duHelp = 1
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then duHelp = CLng(args(i + 1))
                End If
            Case "--stage"
                If i < UBound(args) Then startStage = CLng(args(i + 1))
            Case "--seed"
                If i < UBound(args) Then nextSeed = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
        End Select
    Next i
    If startStage < 1 Then startStage = 1
    If startStage > CR_STAGES Then startStage = CR_STAGES
End Sub

Private Sub SetState(ByVal s As Long)
    duState = s
    If logModes Then Print "state " & Choose(s + 1, "title", "fight", "over", "entry", "scores") & _
                           " stage " & crStage & " score " & crScore
End Sub

Private Sub ToTitle()
    SetState DS_TITLE
    CrNewGame 777 + nextSeed, 1
    ClearBursts
End Sub

Private Sub StartGame()
    CrNewGame nextSeed, startStage
    nextSeed = nextSeed + 1
    SetState DS_PLAY
    duPaused = False
    duAutoplay = False
    fireLock = True
    ClearBursts
End Sub

Private Sub Form_Load()
    Set gcv = view
    CrInit
    DrawInit
    HsSetup Array("RANGER", "SCOUT", "HAWK", "ARROW", "MESA", "BUTTE", "CANYON", "GORGE"), 8000
    HsLoad HsPath("canyon_rail.scores")
    nextSeed = 1
    shotFrame = 150
    startStage = 1
    ParseArgs
    If Not noSound Then SoundInit
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
        CrNewGame 1234, startStage
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
        If crOver <> 0 Or crWon <> 0 Then
            CrNewGame crSeed + 1, 1
        End If
        DoEvents
    Loop
    BenchReport TimerMs() - t0
    Unload Me
End Sub

Private Sub tick_Timer()
    Dim now As Double, steps As Long
    If frontReq Then                        ' --front: our window to the front (screenshots)
        frontReq = False
        Me.Move 0, 0
        Me.SetFocus
    End If
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
    If keyIsDown(vbKeyLeft) Or keyIsDown(vbKeyA) Then inp = inp Or CR_IN_LEFT
    If keyIsDown(vbKeyRight) Or keyIsDown(vbKeyD) Then inp = inp Or CR_IN_RIGHT
    If keyIsDown(vbKeyUp) Or keyIsDown(vbKeyW) Then inp = inp Or CR_IN_UP
    If keyIsDown(vbKeyDown) Or keyIsDown(vbKeyS) Then inp = inp Or CR_IN_DOWN
    If keyIsDown(vbKeySpace) Then
        If Not fireLock Then inp = inp Or CR_IN_FIRE
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
            If edgeUp And startStage < CR_STAGES Then startStage = startStage + 1
            If edgeDown And startStage > 1 Then startStage = startStage - 1
            If edgeFire And duHelp = 0 And Not attractOnly Then StartGame
        Case DS_OVER
            If edgeFire And duStateTimer = 0 Then
                r = HsRank(crScore)
                If r >= 0 And crScore > 0 Then
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
                    If crOver <> 0 Or crWon <> 0 Or crBetween = 1 Then CrNewGame crSeed + 1, 1 + (crSeed Mod CR_STAGES)
                    CrTick CrBot()
                Case DS_PLAY
                    If duAutoplay Then CrTick CrBot() Else CrTick PlayInput()
                Case DS_OVER
            End Select
            HandleEvents duState = DS_PLAY
            AgeEffects
            If duStateTimer > 0 Then duStateTimer = duStateTimer - 1
            If duState = DS_PLAY And (crOver <> 0 Or crWon <> 0) Then
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
    frameNo = frameNo + 1
    If Len(saveShot) > 0 And frameNo = shotFrame Then   ' --saveshot: this frame as a PPM, then quit
        gcv.SaveImage saveShot
        Print "saved " & saveShot
        Unload Me
    End If
End Sub

Private Sub BenchReport(ByVal totalMs As Double)
    Dim n As Double
    n = benchN
    If totalMs <= 0# Then totalMs = 0.001
    Print "Canyon Rail --bench " & benchN & " (autopilot, seed 1234, stage " & startStage & ")"
    Print "state: stage " & crStage & " score " & crScore & " kills " & crKills & " hash " & Hex8(CrStateHash())
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
        If Len(entryName) = 0 Then entryName = "RIDER"
        entryRank = HsInsert(entryName, crScore)
        If Not HsSave(HsPath("canyon_rail.scores")) And logModes Then Print "cannot save the scores"
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

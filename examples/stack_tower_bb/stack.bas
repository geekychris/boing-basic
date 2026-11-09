' Stack Tower - the form: the title (the demo game plays behind it), the game, game over,
' a new high score, the high scores, the help pages (game.c's shell).
'
'   StackTower                    play
'   StackTower --bench N          the bot plays N frames as fast as it can, drawing every
'                                 frame, then prints a timing report
'   StackTower --mode M --level L the title's mode (0 marathon, 1 rising, 2 dig) and level
'   StackTower --perf             timing overlay (also F9) and a log line a second
'   StackTower --log              print each change of screen (tests)
'   StackTower --seed N           the first game's seed
'   StackTower --blit N           the canvas's BlitMode
'
' Keys: Left/Right (A/D) turn the tower (held: repeats), Up/X rotate clockwise, Z
' anticlockwise, Down soft drop, Space hard drop, C hold, G ghost, P pause, B the bot
' plays, Help/H the rules, Esc the title (or quit from it), F9 the timing overlay.
' On the title Left/Right choose the mode, Up/Down the level, Space or Return start.
Option Explicit

Private Const KEY_HELP As Long = 47       ' the Help key (VB's vbKeyHelp)

Private keyIsDown(0 To 255) As Boolean
Private benchN As Long, benchDone As Long, logModes As Boolean
Private lastMs As Double, accMs As Double
Private benchLogic As Double, benchDraw As Double, benchBlit As Double
Private lastState As Long

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
            Case "--perf"
                showPerf = True
                perfLog = True
            Case "--log": logModes = True
            Case "--mode"
                If i < UBound(args) Then svMode = CLng(args(i + 1)) Mod MODE_COUNT
            Case "--level"
                If i < UBound(args) Then svStartLevel = CLng(args(i + 1))
            Case "--seed"
                If i < UBound(args) Then nextSeed = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
        End Select
    Next i
    If svStartLevel < 1 Then svStartLevel = 1
    If svStartLevel > 10 Then svStartLevel = 10
End Sub

Private Function ScoreFile(ByVal m As Long) As String
    ScoreFile = HsPath("stack_tower_" & stModeName(m) & ".scores")
End Function

Private Sub LoadBests()
    Dim m As Long
    For m = 0 To MODE_COUNT - 1
        HsLoad ScoreFile(m)
        svBest(m) = hsScore(0)
    Next m
End Sub

Private Sub LogState()
    If svState <> lastState Then
        If logModes Then Print "state " & Choose(svState + 1, "title", "play", "over", "entry", "scores") & _
                               " " & stModeName(stMode) & " level " & stLevel & " score " & stScore
        lastState = svState
    End If
End Sub

Private Sub Form_Load()
    DrawInit view
    SoundInit
    HsSetup Array("TOWER", "STACK", "RING", "ROD", "ELBOW", "ANCHOR", "BOLT", "STAIRS"), 1000
    svGhost = 1
    svStartLevel = 1
    nextSeed = 1
    lastState = -1
    ParseArgs
    LoadBests
    PerfReset
    ShellToTitle
    If benchN > 0 Then
        showPerf = True
        quietEvents = True
        nextSeed = 1234
        ShellStartGame svMode, svStartLevel
        autoplay = True
    End If
    LogState
    lastMs = TimerMs()
End Sub

' --bench: the frames back to back from the first timer tick, keeping the window alive
Private Sub RunBench()
    Dim t0 As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        If svState = SS_OVER Then
            ShellStartGame svMode, svStartLevel
            autoplay = True
        End If
        Frame 1
        benchDone = benchDone + 1
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
    If steps > 4 Then steps = 4
    accMs = accMs - steps * 40#
    If accMs > 80# Or accMs < -40# Then accMs = 0
    Frame steps
End Sub

' steps game ticks (40 ms each), then one picture
Private Sub Frame(ByVal steps As Long)
    Dim t As Double, k As Long, dir As Long
    PerfBegin
    t = TimerMs()
    If svState = SS_PLAY And svPaused = 0 And svHelp = 0 And Not autoplay Then
        StSoftDrop keyIsDown(vbKeyDown)
        If keyIsDown(vbKeyLeft) Or keyIsDown(vbKeyA) Then
            dir = -1
        ElseIf keyIsDown(vbKeyRight) Or keyIsDown(vbKeyD) Then
            dir = 1
        End If
        If dir <> dasDir Then dasDir = 0
    End If
    For k = 1 To steps
        ShellTick
        If svState = SS_SCORES And svStateTimer = 0 Then ShellToTitle
    Next k
    LogState
    PerfAdd PH_LOGIC
    benchLogic = benchLogic + (TimerMs() - t)

    t = TimerMs()
    If svHelp > 0 Then
        DrawHelp view, svHelp
    Else
        Select Case svState
            Case SS_TITLE: DrawTitle view
            Case SS_ENTRY: DrawEntry view
            Case SS_SCORES: DrawScores view
            Case Else: DrawGame view
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
    Print "Stack Tower --bench " & benchN & " (the bot, " & stModeName(svMode) & ", seed 1234, level " & svStartLevel & ")"
    Print "state: level " & stLevel & " score " & stScore & " rings " & stLines & " pieces " & stPieces & _
          " hash " & Hex8(StStateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & view.Hash
End Sub

' game over -> a new high score (name entry) or the table
Private Sub AfterGame()
    HsLoad ScoreFile(stMode)
    If HsRank(stScore) >= 0 And stScore > 0 Then
        svEntryName = ""
        svState = SS_ENTRY
    Else
        svEntryRank = -1
        svStateTimer = 250
        svState = SS_SCORES
    End If
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim already As Boolean, k As Long
    k = KeyCode And 255
    already = keyIsDown(k)
    keyIsDown(k) = True
    If already Then Exit Sub
    If svState = SS_ENTRY Then
        If k = vbKeyEscape Then
            svEntryRank = -1
            svStateTimer = 250
            svState = SS_SCORES
        End If
        Exit Sub
    End If
    If k = KEY_HELP Or k = vbKeyH Then
        svHelp = (svHelp + 1) Mod 3
        Exit Sub
    End If
    If k = vbKeyF9 Then
        showPerf = Not showPerf
        Exit Sub
    End If
    If svHelp <> 0 Then
        If k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1 Or k = vbKeyEscape Then svHelp = 0
        Exit Sub
    End If
    If k = vbKeyEscape Then
        If svState = SS_TITLE Then Unload Me Else ShellToTitle
        Exit Sub
    End If
    Select Case svState
        Case SS_TITLE
            Select Case k
                Case vbKeyLeft, vbKeyA: svMode = (svMode + MODE_COUNT - 1) Mod MODE_COUNT
                Case vbKeyRight, vbKeyD: svMode = (svMode + 1) Mod MODE_COUNT
                Case vbKeyUp, vbKeyW: If svStartLevel < 10 Then svStartLevel = svStartLevel + 1
                Case vbKeyDown, vbKeyS: If svStartLevel > 1 Then svStartLevel = svStartLevel - 1
                Case vbKeySpace, vbKeyReturn, vbKeyF1
                    autoplay = False
                    ShellStartGame svMode, svStartLevel
            End Select
        Case SS_PLAY
            If k = vbKeyP Then
                If svPaused <> 0 Then svPaused = 0 Else svPaused = 1
            End If
            If svPaused <> 0 Then Exit Sub
            Select Case k
                Case vbKeyB: autoplay = Not autoplay
                Case vbKeyG: svGhost = 1 - svGhost
            End Select
            If autoplay Then Exit Sub
            Select Case k
                Case vbKeyUp, vbKeyX: StRotate 1
                Case vbKeyZ: StRotate -1
                Case vbKeyC: StHoldPiece
                Case vbKeySpace: StHardDrop
                Case vbKeyDown: StSoftDrop True
                Case vbKeyLeft, vbKeyA, vbKeyRight, vbKeyD
                    ' turning: one column on the press; held, it repeats (ShellTick)
                    If k = vbKeyLeft Or k = vbKeyA Then dasDir = -1 Else dasDir = 1
                    StMove dasDir
                    dasTimer = 7
            End Select
        Case SS_OVER
            If svStateTimer = 0 And (k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1) Then AfterGame
        Case SS_SCORES
            If k = vbKeySpace Or k = vbKeyReturn Then ShellToTitle
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyIsDown(KeyCode And 255) = False
    If svState = SS_PLAY And (KeyCode = vbKeyDown) Then StSoftDrop False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If svState <> SS_ENTRY Then Exit Sub
    If KeyAscii = 13 Then
        If Len(svEntryName) = 0 Then svEntryName = "STACKER"
        svEntryRank = HsInsert(svEntryName, stScore)
        If Not HsSave(ScoreFile(stMode)) And logModes Then Print "cannot save the scores"
        svBest(stMode) = hsScore(0)
        svStateTimer = 300
        svState = SS_SCORES
    ElseIf KeyAscii = 8 Then
        If Len(svEntryName) > 0 Then svEntryName = Left$(svEntryName, Len(svEntryName) - 1)
    Else
        ch = UCase$(Chr$(KeyAscii))
        If Len(svEntryName) < 8 And ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then svEntryName = svEntryName & ch
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    tick.Enabled = False
    SoundCleanup
    If logModes Then Print "bye"
End Sub

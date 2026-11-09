' Orbit Docking - the form: the title (the autopilot docks behind it), the game, game over,
' a new high score, the high scores, the help pages (game.c's shell).
'
'   OrbitDocking                  play
'   OrbitDocking --bench N        the autopilot flies N frames as fast as it can, drawing every
'                                 frame, then a timing report
'   OrbitDocking --level L        the title's station (1-6);  --seed N  the first game's seed
'   OrbitDocking --autoplay       start a game with the autopilot flying (screenshots)
'   OrbitDocking --help N / --scores   open on a help page / the high scores
'   OrbitDocking --smoke N        the autopilot flies N frames in real time with sound, then
'                                 a report (the guest smoke test)
'   OrbitDocking --perf --log --nosound --blit N --data DIR
'
' Keys: cursor keys move across (the craft's own left, right, up, down), W / S forward and
' back, A / D roll; Space held turns the cursor keys into in/out (up/down) and roll
' (left/right), as fire does on the C's joystick. P pause, B autopilot, Help/H the rules,
' Esc the title (or quit from it), M effects on/off, F9 the timing overlay. On the title
' Up/Down choose the station, Space or Return start.
Option Explicit

Private Const KEY_HELP As Long = 47

Private keyIsDown(0 To 255) As Boolean
Private benchN As Long, benchDone As Long, logModes As Boolean, noSound As Boolean
Private lastMs As Double, accMs As Double
Private benchLogic As Double, benchDraw As Double, benchBlit As Double
Private lastState As Long, fireLock As Boolean
Private startPlaying As Boolean, startHelp As Long, startScores As Boolean, smokeN As Long, smokeDone As Long
Private dataDir As String

Private Function DataFile(ByVal name As String) As String
    If Len(dataDir) > 0 Then
        If Right$(dataDir, 1) = ":" Or Right$(dataDir, 1) = "/" Then DataFile = dataDir & name Else DataFile = dataDir & "/" & name
    Else
        DataFile = HsPath(name)
    End If
End Function

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
                startPlaying = True
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then smokeN = CLng(args(i + 1))
                End If
            Case "--perf"
                showPerf = True
                perfLog = True
            Case "--log": logModes = True
            Case "--nosound": noSound = True
            Case "--autoplay": startPlaying = True
            Case "--scores": startScores = True
            Case "--help"
                startHelp = 1
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then startHelp = CLng(args(i + 1))
                End If
            Case "--level"
                If i < UBound(args) Then dkStartLevel = CLng(args(i + 1))
            Case "--seed"
                If i < UBound(args) Then nextSeed = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
            Case "--data"
                If i < UBound(args) Then dataDir = args(i + 1)
        End Select
    Next i
    If dkStartLevel < 1 Then dkStartLevel = 1
    If dkStartLevel > OD_LEVELS Then dkStartLevel = OD_LEVELS
End Sub

Private Sub LogState()
    If dkState <> lastState Then
        If logModes Then Print "state " & Choose(dkState + 1, "title", "fly", "over", "entry", "scores") & _
                               " station " & odLevel & " score " & odScore
        lastState = dkState
    End If
End Sub

Private Sub Form_Load()
    DrawInit view
    HsSetup Array("GEMINI", "SOYUZ", "APOLLO", "MIR", "SKYLAB", "SALYUT", "DRAGON", "VOSTOK"), 3000
    dkStartLevel = 1
    nextSeed = 1
    lastState = -1
    ParseArgs
    If Not noSound Then SoundInit
    HsLoad DataFile("orbit_docking.scores")
    dkBest = hsScore(0)
    PerfReset
    ShellToTitle
    If benchN > 0 Or startPlaying Then
        quietEvents = benchN > 0
        nextSeed = 1234
        ShellStartGame dkStartLevel
        dkAutoplay = True
        If benchN > 0 Then showPerf = True
    End If
    If startScores Then
        dkEntryRank = -1
        dkStateTimer = 30000
        dkState = DS_SCORES
    End If
    If startHelp >= 1 And startHelp <= 2 Then dkHelp = startHelp
    LogState
    lastMs = TimerMs()
End Sub

Private Sub RunBench()
    Dim t0 As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        If dkState = DS_OVER Then
            ShellStartGame dkStartLevel
            dkAutoplay = True
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
    If smokeN > 0 And dkState = DS_OVER Then
        ShellStartGame dkStartLevel
        dkAutoplay = True
    End If
    Frame steps
    If smokeN > 0 Then
        smokeDone = smokeDone + 1
        If smokeDone >= smokeN Then
            Print "Orbit Docking smoke: " & smokeN & " frames, station " & odLevel & " score " & odScore & " docks " & _
                  odDocks & " crashes " & odCrashes & " fps " & Format$(perfFps, "0.0") & " (" & PerfText() & ")"
            If Not au Is Nothing Then Print "audio: " & au.Device & ", effects " & sfxCount(SFX_THRUST) & " thrust " & _
                                            sfxCount(SFX_DOCK) & " docks"
            Print "picture hash " & view.Hash
            Unload Me
        End If
    End If
End Sub

' the player's thrusters from the keys (game_input's play_in)
Private Function PlayBits() As Long
    Dim b As Long, l As Boolean, r As Boolean, u As Boolean, d As Boolean
    l = keyIsDown(vbKeyLeft): r = keyIsDown(vbKeyRight): u = keyIsDown(vbKeyUp): d = keyIsDown(vbKeyDown)
    If Not keyIsDown(vbKeySpace) Then fireLock = False
    If keyIsDown(vbKeySpace) And Not fireLock Then   ' fire shifts up/down to in/out, left/right to roll
        If u Then b = b Or OD_IN_FWD
        If d Then b = b Or OD_IN_BACK
        If l Then b = b Or OD_IN_ROLL_L
        If r Then b = b Or OD_IN_ROLL_R
    Else
        If l Then b = b Or OD_IN_LEFT
        If r Then b = b Or OD_IN_RIGHT
        If u Then b = b Or OD_IN_UP
        If d Then b = b Or OD_IN_DOWN
    End If
    If keyIsDown(vbKeyW) Then b = b Or OD_IN_FWD
    If keyIsDown(vbKeyS) Then b = b Or OD_IN_BACK
    If keyIsDown(vbKeyA) Then b = b Or OD_IN_ROLL_L
    If keyIsDown(vbKeyD) Then b = b Or OD_IN_ROLL_R
    PlayBits = b
End Function

Private Sub Frame(ByVal steps As Long)
    Dim t As Double, k As Long
    PerfBegin
    t = TimerMs()
    If dkState = DS_PLAY Then playIn = PlayBits() Else playIn = 0
    For k = 1 To steps
        ShellTick
        If dkState = DS_SCORES And dkStateTimer = 0 Then ShellToTitle
    Next k
    LogState
    PerfAdd PH_LOGIC
    benchLogic = benchLogic + (TimerMs() - t)
    t = TimerMs()
    If dkHelp > 0 Then
        DrawHelp view, dkHelp
    Else
        Select Case dkState
            Case DS_TITLE: DrawTitle view
            Case DS_ENTRY: DrawEntry view
            Case DS_SCORES: DrawScores view
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
    Print "Orbit Docking --bench " & benchN & " (the autopilot, seed 1234, station " & dkStartLevel & ")"
    Print "state: station " & odLevel & " score " & odScore & " docks " & odDocks & " crashes " & odCrashes & _
          " hash " & Hex8(OdStateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & view.Hash
End Sub

Private Sub AfterGame()
    If HsRank(odScore) >= 0 And odScore > 0 Then
        dkEntryName = ""
        dkState = DS_ENTRY
    Else
        dkEntryRank = -1
        dkStateTimer = 250
        dkState = DS_SCORES
    End If
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim already As Boolean, k As Long
    k = KeyCode And 255
    already = keyIsDown(k)
    keyIsDown(k) = True
    If already Then Exit Sub
    If dkState = DS_ENTRY Then
        If k = vbKeyEscape Then
            dkEntryRank = -1
            dkStateTimer = 250
            dkState = DS_SCORES
        End If
        Exit Sub
    End If
    If k = KEY_HELP Or k = vbKeyH Then
        dkHelp = (dkHelp + 1) Mod 3
        Exit Sub
    End If
    If k = vbKeyF9 Then
        showPerf = Not showPerf
        Exit Sub
    End If
    If k = vbKeyM Then
        ToggleEffects
        Exit Sub
    End If
    If dkHelp <> 0 Then
        If k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1 Or k = vbKeyEscape Then dkHelp = 0
        Exit Sub
    End If
    If k = vbKeyEscape Then
        If dkState = DS_TITLE Then Unload Me Else ShellToTitle
        Exit Sub
    End If
    Select Case dkState
        Case DS_TITLE
            Select Case k
                Case vbKeyUp: If dkStartLevel < OD_LEVELS Then dkStartLevel = dkStartLevel + 1
                Case vbKeyDown: If dkStartLevel > 1 Then dkStartLevel = dkStartLevel - 1
                Case vbKeySpace, vbKeyReturn, vbKeyF1
                    ShellStartGame dkStartLevel
                    fireLock = True
            End Select
        Case DS_PLAY
            If k = vbKeyP Then
                If dkPaused <> 0 Then dkPaused = 0 Else dkPaused = 1
            End If
            If k = vbKeyB Then dkAutoplay = Not dkAutoplay
        Case DS_OVER
            If dkStateTimer = 0 And (k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1) Then AfterGame
        Case DS_SCORES
            If k = vbKeySpace Or k = vbKeyReturn Then ShellToTitle
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyIsDown(KeyCode And 255) = False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If dkState <> DS_ENTRY Then Exit Sub
    If KeyAscii = 13 Then
        If Len(dkEntryName) = 0 Then dkEntryName = "PILOT"
        dkEntryRank = HsInsert(dkEntryName, odScore)
        If Not HsSave(DataFile("orbit_docking.scores")) And logModes Then Print "cannot save the scores"
        dkBest = hsScore(0)
        dkStateTimer = 300
        dkState = DS_SCORES
    ElseIf KeyAscii = 8 Then
        If Len(dkEntryName) > 0 Then dkEntryName = Left$(dkEntryName, Len(dkEntryName) - 1)
    Else
        ch = UCase$(Chr$(KeyAscii))
        If Len(dkEntryName) < 8 And ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then dkEntryName = dkEntryName & ch
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    tick.Enabled = False
    SoundCleanup
    If logModes Then Print "bye"
End Sub

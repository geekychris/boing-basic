' Ace Pilot 2 - the form: the title (the autopilot flies behind it), the briefing, the
' mission, its result, the end of the campaign, a new high score, the high scores, the help
' pages (game.c's shell).
'
'   AcePilot2                     play
'   AcePilot2 --bench N           the autopilot flies N frames of the campaign as fast as it
'                                 can, drawing every frame, then a timing report
'   AcePilot2 --mission M         the title's mission (1-8);  --seed N  the first game's seed
'   AcePilot2 --autoplay          start mission M straight in the air, the autopilot flying
'   AcePilot2 --cockpit           the cockpit view;  --brief: open on the briefing
'   AcePilot2 --help N / --scores open on a help page / the high scores
'   AcePilot2 --smoke N           the autopilot flies N frames in real time with sound, then
'                                 a report (the guest smoke test)
'   AcePilot2 --perf --log --nosound --blit N --data DIR
'
' Keys: Left/Right bank, Up/Down nose down/up (I inverts), Space the guns, A/Z throttle, V or C
' the chase view / the cockpit, P pause, B autopilot, Help/H how to fly, Esc the title (or
' quit from it), M effects on/off, F9 the timing overlay. On the title Up/Down choose the
' mission, Space or Return start.
Option Explicit

Private Const KEY_HELP As Long = 47

Private keyIsDown(0 To 255) As Boolean
Private benchN As Long, benchDone As Long, logModes As Boolean, noSound As Boolean
Private lastMs As Double, accMs As Double
Private benchLogic As Double, benchDraw As Double, benchBlit As Double
Private lastState As Long, fireLock As Boolean
Private startPlaying As Boolean, startBrief As Boolean, startHelp As Long, startScores As Boolean
Private smokeN As Long, smokeDone As Long
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
            Case "--brief": startBrief = True
            Case "--cockpit": acView = VIEW_COCKPIT
            Case "--scores": startScores = True
            Case "--help"
                startHelp = 1
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then startHelp = CLng(args(i + 1))
                End If
            Case "--mission"
                If i < UBound(args) Then acStartMission = CLng(args(i + 1))
            Case "--seed"
                If i < UBound(args) Then nextSeed = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
            Case "--data"
                If i < UBound(args) Then dataDir = args(i + 1)
        End Select
    Next i
    If acStartMission < 1 Then acStartMission = 1
    If acStartMission > AP_MISSIONS Then acStartMission = AP_MISSIONS
End Sub

Private Sub LogState()
    If acState <> lastState Then
        If logModes Then Print "state " & Choose(acState + 1, "title", "brief", "flying", "result", "over", "entry", "scores") & _
                               " mission " & apMission & " score " & apScore
        lastState = acState
    End If
End Sub

Private Sub Form_Load()
    DrawInit view
    HsSetup Array("BALL", "MANNOCK", "BISHOP", "MCCUDDEN", "COLLISHAW", "BARKER", "FONCK", "GUYNEMER"), 2000
    acStartMission = 1
    nextSeed = 1
    lastState = -1
    ParseArgs
    If Not noSound Then SoundInit
    HsLoad DataFile("ace_pilot2.scores")
    acBest = hsScore(0)
    PerfReset
    ShellToTitle
    If benchN > 0 Or startPlaying Then
        quietEvents = benchN > 0
        nextSeed = 1234
        ShellStartGame acStartMission, False
        acAutoplay = True
        If benchN > 0 Then showPerf = True
    ElseIf startBrief Then
        ShellStartGame acStartMission, True
    End If
    If startScores Then
        acEntryRank = -1
        acStateTimer = 30000
        acState = AS_SCORES
    End If
    If startHelp >= 1 And startHelp <= 2 Then acHelp = startHelp
    LogState
    lastMs = TimerMs()
End Sub

' the bench and the smoke run fly on through results and campaigns
Private Sub KeepFlying()
    If acState = AS_RESULT And acStateTimer = 0 Then
        ShellNext
        If acState = AS_BRIEF Then
            acState = AS_PLAY
            MissionStart
        End If
        acAutoplay = True
    End If
    If acState = AS_OVER Then
        ShellStartGame acStartMission, False
        acAutoplay = True
    End If
End Sub

Private Sub RunBench()
    Dim t0 As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        KeepFlying
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
    If smokeN > 0 Then KeepFlying
    Frame steps
    If smokeN > 0 Then
        smokeDone = smokeDone + 1
        If smokeDone >= smokeN Then
            Print "Ace Pilot 2 smoke: " & smokeN & " frames, mission " & apMission & " score " & apScore & " kills " & _
                  apKills & " ground " & apGKills & " fps " & Format$(perfFps, "0.0") & " (" & PerfText() & ")"
            If Not au Is Nothing Then Print "audio: " & au.Device & ", effects " & sfxCount(SFX_GUN) & " bursts " & _
                                            sfxCount(SFX_BOOM) & " booms"
            Print "picture hash " & view.Hash
            Unload Me
        End If
    End If
End Sub

' the stick, the guns and the throttle from the keys (game_input's play_in)
Private Function PlayBits() As Long
    Dim b As Long, up As Long, dn As Long
    If acInvert Then
        up = AP_IN_NOSEUP: dn = AP_IN_NOSEDN
    Else
        up = AP_IN_NOSEDN: dn = AP_IN_NOSEUP         ' stick forward (up) puts the nose down
    End If
    If keyIsDown(vbKeyLeft) Then b = b Or AP_IN_LEFT
    If keyIsDown(vbKeyRight) Then b = b Or AP_IN_RIGHT
    If keyIsDown(vbKeyUp) Then b = b Or up
    If keyIsDown(vbKeyDown) Then b = b Or dn
    If keyIsDown(vbKeySpace) And Not fireLock Then b = b Or AP_IN_FIRE
    If Not keyIsDown(vbKeySpace) Then fireLock = False
    If keyIsDown(vbKeyA) Then b = b Or AP_IN_THR_UP
    If keyIsDown(vbKeyZ) Then b = b Or AP_IN_THR_DN
    PlayBits = b
End Function

Private Sub Frame(ByVal steps As Long)
    Dim t As Double, k As Long
    PerfBegin
    t = TimerMs()
    If acState = AS_PLAY Then playIn = PlayBits() Else playIn = 0
    For k = 1 To steps
        ShellTick
        If acState = AS_SCORES And acStateTimer = 0 Then ShellToTitle
    Next k
    LogState
    PerfAdd PH_LOGIC
    benchLogic = benchLogic + (TimerMs() - t)
    t = TimerMs()
    If acHelp > 0 Then
        DrawHelp view, acHelp
    Else
        Select Case acState
            Case AS_TITLE: DrawTitle view
            Case AS_BRIEF: DrawBrief view
            Case AS_ENTRY: DrawEntry view
            Case AS_SCORES: DrawScores view
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
    Print "Ace Pilot 2 --bench " & benchN & " (the autopilot, seed 1234, from mission " & acStartMission & ")"
    Print "state: mission " & apMission & " phase " & apPhase & " score " & apScore & " kills " & apKills & _
          " hash " & Hex8(ApStateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame;  polys/frame " & Format$(polyTotal / n, "0.0")
    Print "picture hash " & view.Hash
End Sub

' the campaign over: a new high score (name entry) or the table
Private Sub AfterCampaign()
    If HsRank(apScore) >= 0 And apScore > 0 Then
        acEntryName = ""
        acState = AS_ENTRY
    Else
        acEntryRank = -1
        acStateTimer = 250
        acState = AS_SCORES
    End If
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Dim already As Boolean, k As Long
    k = KeyCode And 255
    already = keyIsDown(k)
    keyIsDown(k) = True
    If already Then Exit Sub
    If acState = AS_ENTRY Then
        If k = vbKeyEscape Then
            acEntryRank = -1
            acStateTimer = 250
            acState = AS_SCORES
        End If
        Exit Sub
    End If
    If k = KEY_HELP Or k = vbKeyH Then
        acHelp = (acHelp + 1) Mod 3
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
    If acHelp <> 0 Then
        If k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1 Or k = vbKeyEscape Then acHelp = 0
        Exit Sub
    End If
    If k = vbKeyEscape Then
        If acState = AS_TITLE Then Unload Me Else ShellToTitle
        Exit Sub
    End If
    If k = vbKeyI Then acInvert = Not acInvert
    If k = vbKeyV Or k = vbKeyC Then acView = acView Xor 1
    Select Case acState
        Case AS_TITLE
            Select Case k
                Case vbKeyUp: If acStartMission < AP_MISSIONS Then acStartMission = acStartMission + 1
                Case vbKeyDown: If acStartMission > 1 Then acStartMission = acStartMission - 1
                Case vbKeySpace, vbKeyReturn, vbKeyF1: ShellStartGame acStartMission, True
            End Select
        Case AS_BRIEF
            If acStateTimer = 0 And (k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1) Then
                acState = AS_PLAY
                MissionStart
                fireLock = True
            End If
        Case AS_PLAY
            If k = vbKeyP Then
                If acPaused <> 0 Then acPaused = 0 Else acPaused = 1
            End If
            If k = vbKeyB Then acAutoplay = Not acAutoplay
        Case AS_RESULT
            If acStateTimer = 0 And (k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1) Then
                ShellNext
                fireLock = True
            End If
        Case AS_OVER
            If acStateTimer = 0 And (k = vbKeySpace Or k = vbKeyReturn Or k = vbKeyF1) Then AfterCampaign
        Case AS_SCORES
            If k = vbKeySpace Or k = vbKeyReturn Then ShellToTitle
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyIsDown(KeyCode And 255) = False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If acState <> AS_ENTRY Then Exit Sub
    If KeyAscii = 13 Then
        If Len(acEntryName) = 0 Then acEntryName = "PILOT"
        acEntryRank = HsInsert(acEntryName, apScore)
        If Not HsSave(DataFile("ace_pilot2.scores")) And logModes Then Print "cannot save the scores"
        acBest = hsScore(0)
        acStateTimer = 300
        acState = AS_SCORES
    ElseIf KeyAscii = 8 Then
        If Len(acEntryName) > 0 Then acEntryName = Left$(acEntryName, Len(acEntryName) - 1)
    Else
        ch = UCase$(Chr$(KeyAscii))
        If Len(acEntryName) < 8 And ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then acEntryName = acEntryName & ch
    End If
End Sub

Private Sub Form_Unload(Cancel As Integer)
    tick.Enabled = False
    SoundCleanup
    If logModes Then Print "bye"
End Sub

' Boing Pinball - the form: a 640 x 512 Canvas, a 20 ms Timer, the keys and the
' mouse. Everything else is PbShell (screens), PbCore (the game) and PbDraw.
'
'   BoingPinball                   play
'   BoingPinball --table N         start on table N (0 Comet Tour, 1 Deep Dive, 2 Robot Foundry)
'   BoingPinball --bench N         the bot plays N frames as fast as it can (20 ms of game
'                                  time each), drawing every one, then prints a timing report
'   BoingPinball --attract         the title only, forever (no game starts)
'   BoingPinball --perf            timing overlay (also F1) and a log line a second
'   BoingPinball --log             print each change of screen (tests)
'   BoingPinball --blit M          the Canvas's BlitMode
'   BoingPinball --script          a fixed sequence of keys through the form's key handlers
'                                  (start, plunger, flippers, nudge, pause, help, tables, quit),
'                                  logged: the input test (tests/run.sh, headless)
'   BoingPinball --screen S        start on a screen (for screenshots): title, demo (the
'                                  title's backglass or demo, held), help1, help2, scores, play (the bot plays a game)
'
' Keys: Z / left mouse button the left flippers, / (slash) / right button the right
' ones, Space / Down / Return the plunger (hold, let go), cursor keys nudge (and
' choose the table on the title), P pause, Help / H the rules, S the high scores (on
' the title), M music on/off, Esc the title (or quit from it), F1 the timing overlay.
Option Explicit

Private Const KEY_HELP As Long = 47
Private Const KEY_SLASH As Long = 314               ' 256 + raw key 0x3A

Private scriptOn As Boolean, scriptFrame As Long
Private benchN As Long, benchDone As Long, attractOnly As Boolean, tableArg As Long, screenArg As String
Private lastMs As Double
Private benchLogic As Double, benchDraw As Double, benchBlit As Double

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
            Case "--attract": attractOnly = True
            Case "--perf": showPerf = True: perfLog = True
            Case "--log": logStates = True
            Case "--table"
                If i < UBound(args) Then tableArg = CLng(args(i + 1)) Mod TB_COUNT
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
            Case "--script": scriptOn = True: logStates = True
            Case "--screen"
                If i < UBound(args) Then screenArg = LCase$(args(i + 1))
        End Select
    Next i
End Sub

Private Sub Form_Load()
    ParseArgs
    ShellInit view, 1
    If tableArg <> 0 Then ChooseTable tableArg: ToTitle
    If benchN = 0 Then SoundInit App.Path & "/art/boing_pinball.mod"
    PerfReset
    If benchN > 0 Then
        StartGame dTable
        botPlay = True
        BotReset 99
    End If
    Select Case screenArg
        Case "title": titleHold = True
        Case "demo": titleFrames = 300: titleHold = True
        Case "help1": pHelp = 1
        Case "help2": pHelp = 2
        Case "scores": pState = PS_SCORES: entryRank = -1: stateTimer = 30000
        Case "play": StartGame dTable: botPlay = True: BotReset 99
    End Select
    lastMs = TimerMs()
End Sub

' --bench: the frames back to back from the first timer tick, keeping the window alive
Private Sub RunBench()
    Dim t0 As Double, t As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        PerfBegin
        t = TimerMs()
        ShellFrame 20
        PerfAdd PH_LOGIC
        benchLogic = benchLogic + TimerMs() - t
        t = TimerMs()
        ShellDraw
        If showPerf Then DrawPerf PerfText()
        PerfAdd PH_DRAW
        benchDraw = benchDraw + TimerMs() - t
        t = TimerMs()
        view.Refresh
        PerfAdd PH_BLIT
        benchBlit = benchBlit + TimerMs() - t
        PerfEnd
        benchDone = benchDone + 1
        If pState = PS_OVER Then StartGame dTable: botPlay = True
        DoEvents
    Loop
    BenchReport TimerMs() - t0
    Unload Me
End Sub

Private Sub BenchReport(ByVal totalMs As Double)
    Dim n As Double
    n = benchN
    If totalMs <= 0# Then totalMs = 0.001
    Print "Boing Pinball --bench " & benchN & " (the bot on " & tName & ", seed 99)"
    Print "state: score " & gScore & " ball " & gBallNo & " steps " & stepsRun & " hash " & Hex8(StateHash())
    Print "time: total " & Format$(totalMs, "0") & " ms = " & Format$(totalMs / n, "0.000") & _
          " ms/frame = " & Format$(n * 1000# / totalMs, "0.0") & " fps"
    Print "time: logic " & Format$(benchLogic / n, "0.000") & "  draw " & Format$(benchDraw / n, "0.000") & _
          "  blit " & Format$(benchBlit / n, "0.000") & " ms/frame (" & view.BlitInfo & ")"
    Print "picture hash " & view.Hash
End Sub

Private Sub tick_Timer()
    Dim now As Double, dt As Double
    If benchN > 0 Then
        If benchDone = 0 Then RunBench
        Exit Sub
    End If
    now = TimerMs()
    dt = now - lastMs
    lastMs = now
    If dt < 0 Or dt > 100 Then dt = 20
    If scriptOn Then
        dt = 20
        RunScript
    End If
    PerfBegin
    If attractOnly And pState <> PS_TITLE Then ToTitle
    ShellFrame dt
    If quitRequest Then
        Unload Me
        Exit Sub
    End If
    PerfAdd PH_LOGIC
    ShellDraw
    If showPerf Then DrawPerf PerfText()
    PerfAdd PH_DRAW
    view.Refresh
    PerfAdd PH_BLIT
    PerfEnd
End Sub

Private Sub Key(ByVal k As Integer, ByVal down As Boolean)
    Dim sh As Integer
    If down Then Form_KeyDown k, sh Else Form_KeyUp k, sh
End Sub

' --script: one step of the input test, at 50 frames a second of game time
Private Sub RunScript()
    Dim i As Long
    scriptFrame = scriptFrame + 1
    Select Case scriptFrame
        Case 300: Key vbKeySpace, True                  ' (the title's backglass shows for a while)
        Case 302: Key vbKeySpace, False
        Case 320: Print "ball in lane: " & (bl(0).st = BS_LANE) & " pull " & gPull
                  Key vbKeySpace, True                  ' pull the plunger back for a second
        Case 370: Print "pulled: " & (gPull > 50000)
                  Key vbKeySpace, False                 ' and let go
        Case 372: Print "launched: " & (bl(0).st = BS_PLAY And bl(0).vy > 0)
        Case 400: Key vbKeyZ, True: Key KEY_SLASH, True
        Case 410: Print "flippers up: " & (fl(0).ang = fl(0).up And fl(1).ang = fl(1).up)
                  Key vbKeyZ, False: Key KEY_SLASH, False
        Case 412: Key vbKeyUp, True
        Case 413: Key vbKeyUp, False
        Case 416: Print "nudged: tilt meter " & (gTiltMeter > 0)
        Case 420: Key vbKeyP, True: Key vbKeyP, False
        Case 430: i = gTime
        Case 440: Print "paused: " & (pPaused = 1): Key vbKeyP, True: Key vbKeyP, False
        Case 450: Key vbKeyH, True: Key vbKeyH, False
        Case 452: Print "help: " & pHelp: Key vbKeyH, True: Key vbKeyH, False
        Case 454: Print "help: " & pHelp: Key vbKeySpace, True: Key vbKeySpace, False
        Case 456: Print "help: " & pHelp
        Case 470: Key vbKeyEscape, True: Key vbKeyEscape, False
        Case 480: Key vbKeyRight, True: Key vbKeyRight, False
        Case 482: Print "table: " & tName
        Case 490: Key vbKeyS, True: Key vbKeyS, False
        Case 495: Print "scores of " & tName & ": " & (pState = PS_SCORES) & " best " & bestScore
                  Key vbKeySpace, True: Key vbKeySpace, False
        Case 500: Key vbKeyEscape, True: Key vbKeyEscape, False
    End Select
End Sub

Private Function KeyBits(ByVal k As Long) As Long
    Select Case k
        Case vbKeyZ: KeyBits = IN_LFLIP
        Case KEY_SLASH: KeyBits = IN_RFLIP
        Case vbKeySpace, vbKeyDown, vbKeyReturn: KeyBits = IN_PLUNGE
        Case vbKeyLeft: KeyBits = IN_NL
        Case vbKeyRight: KeyBits = IN_NR
        Case vbKeyUp: KeyBits = IN_NU
        Case vbKeyP: KeyBits = IN_PAUSE
        Case KEY_HELP, vbKeyH: KeyBits = IN_HELP
        Case vbKeyEscape: KeyBits = IN_ESC
        Case vbKeyS: KeyBits = IN_SCORES
    End Select
End Function

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If pState = PS_ENTRY Then
        If KeyCode = vbKeyEscape Then ShellType 27
        Exit Sub
    End If
    Select Case KeyCode
        Case vbKeyF1: showPerf = Not showPerf
        Case vbKeyM: SoundToggleMusic
        Case Else
            If attractOnly And KeyCode <> vbKeyEscape Then Exit Sub
            ShellKeys KeyBits(KeyCode), True
    End Select
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    ShellKeys KeyBits(KeyCode), False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    If pState = PS_ENTRY And KeyAscii <> 27 Then ShellType KeyAscii
End Sub

Private Sub view_MouseDown(Button As Integer, Shift As Integer, X As Long, Y As Long)
    If Button And 1 Then ShellKeys IN_LFLIP, True
    If Button And 2 Then ShellKeys IN_RFLIP, True
End Sub

Private Sub view_MouseUp(Button As Integer, Shift As Integer, X As Long, Y As Long)
    If Button And 1 Then ShellKeys IN_LFLIP, False
    If Button And 2 Then ShellKeys IN_RFLIP, False
End Sub

Private Sub Form_Unload(Cancel As Integer)
    tick.Enabled = False
    SoundCleanup
    If logStates Then Print "bye"
End Sub

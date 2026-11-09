' Lander 3D - the form: the title (the painting, then the autopilot's demo), flying,
' the result of each landing, game over, a new high score, the high scores, help.
'
'   Lander3D                    play
'   Lander3D --bench N          the autopilot flies the tour for N frames as fast as
'                               it can, drawing every frame, then prints a report
'   Lander3D --attract          the title only, forever
'   Lander3D --perf             timing overlay (also F1) and a log line a second
'   Lander3D --log              print the game's events (tests)
'   Lander3D --level N          start at level N (also Up/Down on the title)
'   Lander3D --win N            terrain cells drawn each side (default 20)
'   Lander3D --quiet            no music or sound
'   Lander3D --dir PATH         where the pictures, module and scores are (boing run: App.Path
'                               is boing's own folder)
'   Lander3D --ships N          ships a game (default 3; tests)
'   Lander3D --place            the first level starts 6 m over the x1 pad, still, with the
'                               autopilot on (tests: a quick landing)
'
' Keys: Space/J full thrust, Q/E steady throttle, cursor keys/WASD tip the lander,
' P pause, B autopilot, Help/H the rules, M music, N sound, F1 timing, F2 high scores,
' Esc back to the title (or quit from it).
Option Explicit

Private Const KEY_HELP As Long = 47       ' the Help key (VB's vbKeyHelp)

Private keyIsDown(0 To 255) As Boolean
Private edgeFire As Boolean
Private benchN As Long, benchDone As Long, attractOnly As Boolean, quiet As Boolean
Private startLevel As Long
Private lastMs As Double, accMs As Double
Private entryName As String
Private benchLogic As Double, benchDraw As Double, benchBlit As Double
Private shipsArg As Long, lastState As Long, placeArg As Boolean, frameNo As Long

Private Sub ParseArgs()
    Dim args() As String, i As Long, a As String
    args = Split(Trim$(Command$), " ")
    For i = 0 To UBound(args)
        a = LCase$(args(i))
        Select Case a
            Case "--bench"
                benchN = 1000
                If i < UBound(args) Then
                    If IsNumeric(args(i + 1)) Then benchN = CLng(args(i + 1))
                End If
            Case "--attract": attractOnly = True
            Case "--perf"
                showPerf = True
                perfLog = True
            Case "--log": gLog = True
            Case "--quiet": quiet = True
            Case "--level"
                If i < UBound(args) Then startLevel = CLng(args(i + 1))
            Case "--place": placeArg = True
            Case "--ships"
                If i < UBound(args) Then shipsArg = CLng(args(i + 1))
            Case "--win"
                If i < UBound(args) Then groundWin = CLng(args(i + 1))
            Case "--blit"
                If i < UBound(args) Then view.BlitMode = CLng(args(i + 1))
        End Select
    Next i
    If startLevel < 1 Then startLevel = 1
    If startLevel > 9 Then startLevel = 9
End Sub

Private Sub Form_Load()
    DrawInit view
    GameInit
    HsSetup Array("ALDRIN", "ARMSTRNG", "CONRAD", "BEAN", "SHEPARD", "MITCHELL", "SCOTT", "IRWIN"), 400
    HsLoad GameDir() & "lander_3d.scores"
    gBest = hsScore(0)
    startLevel = 1
    entryRank = -1
    lastState = -1
    ParseArgs
    SoundInit Not quiet And benchN = 0
    If gLog Then Print sndStatus
    PerfReset
    If benchN > 0 Then
        showPerf = True
        StartGame MODE_TOUR, startLevel
        gDemo = True
    End If
    lastMs = TimerMs()
End Sub

' --bench: the frames back to back, from the first timer tick
Private Sub RunBench()
    Dim t0 As Double
    tick.Enabled = False
    t0 = TimerMs()
    Do While benchDone < benchN
        Frame 1
        benchDone = benchDone + 1
        If gState = LS_OVER And gStateTimer = 0 Then
            StartGame MODE_TOUR, 1
            gDemo = True
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

Private Function Held() As Long
    Dim b As Long
    If keyIsDown(vbKeyLeft) Or keyIsDown(vbKeyA) Then b = b Or IN_LEFT
    If keyIsDown(vbKeyRight) Or keyIsDown(vbKeyD) Then b = b Or IN_RIGHT
    If keyIsDown(vbKeyUp) Or keyIsDown(vbKeyW) Then b = b Or IN_UP
    If keyIsDown(vbKeyDown) Or keyIsDown(vbKeyS) Then b = b Or IN_DOWN
    If keyIsDown(vbKeySpace) Or keyIsDown(vbKeyJ) Then b = b Or IN_FIRE
    Held = b
End Function

Private Sub GameOverNext()
    Dim r As Long
    r = HsRank(gScore)
    If r >= 0 And gScore > 0 Then
        entryName = ""
        gState = LS_ENTRY
    Else
        entryRank = -1
        gState = LS_SCORES
        gStateTimer = 250
    End If
End Sub

' steps game frames (40 ms each), then one picture
Private Sub Frame(ByVal steps As Long)
    Dim t As Double, k As Long, s0 As Long
    PerfBegin
    t = TimerMs()
    If edgeFire Then
        Select Case gState
            Case LS_TITLE
                If Not attractOnly Then
                    StartGame gMenu, startLevel
                    If shipsArg > 0 Then gShips = shipsArg
                End If
            Case LS_RESULT
                If gStateTimer < 75 Then AfterResult
            Case LS_OVER
                If gStateTimer = 0 Then GameOverNext
            Case LS_SCORES
                ToTitle
        End Select
        edgeFire = False
    End If
    gHeld = Held()
    For k = 1 To steps
        s0 = gState
        GameFrame
        If gState = LS_SCORES And gStateTimer = 0 And s0 = LS_SCORES Then ToTitle
    Next k
    If gWorldChanged Then
        DrawPalette ld.world
        gWorldChanged = False
    End If
    If gState <> lastState Then
        If placeArg And gState = LS_PLAY And lastState = LS_TITLE Then     ' the original's "place pad" hook
            ld.px = padX(0): ld.pz = padZ(0): ld.py = padY(0) + FromI(6)
            ld.vx = 0: ld.vy = 0: ld.vz = 0
            ld.pitch = 0: ld.roll = 0: ld.wp = 0: ld.wr = 0
            gDemo = True
        End If
        If gLog Then Print "state " & Choose(gState + 1, "title", "play", "result", "over", "entry", "scores") & _
                           " " & wName(ld.world) & " level " & gLevel & " score " & gScore & " ships " & gShips
        lastState = gState
    End If
    PerfAdd PH_LOGIC
    benchLogic = benchLogic + (TimerMs() - t)

    frameNo = frameNo + 1
    If gLog And frameNo <= 2 Then Print "frame " & frameNo & ": drawing"
    t = TimerMs()
    If gHelp > 0 Then
        DrawHelp gHelp
    Else
        Select Case gState
            Case LS_TITLE: DrawTitle
            Case LS_ENTRY: DrawEntry entryName
            Case LS_SCORES: DrawScores
            Case Else: DrawGame
        End Select
    End If
    If showPerf Then DrawPerf
    PerfAdd PH_DRAW
    benchDraw = benchDraw + (TimerMs() - t)

    If gLog And frameNo <= 2 Then Print "frame " & frameNo & ": refresh"
    t = TimerMs()
    view.Refresh
    If gLog And frameNo <= 2 Then Print "frame " & frameNo & ": shown"
    PerfAdd PH_BLIT
    benchBlit = benchBlit + (TimerMs() - t)
    PerfEnd
End Sub

Private Sub BenchReport(ByVal totalMs As Double)
    Dim n As Double
    n = benchN
    If totalMs <= 0# Then totalMs = 0.001
    Print "Lander 3D --bench " & benchN & " (autopilot, the tour from level " & startLevel & ", seed 2026)"
    Print "state: " & wName(ld.world) & " level " & ld.lvl & " score " & gScore & " ships " & gShips & _
          " t " & ld.t & " hash " & Hex8(LdStateHash())
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
    If gState = LS_ENTRY Then
        If KeyCode = vbKeyEscape Then
            entryRank = -1
            gState = LS_SCORES
            gStateTimer = 250
        End If
        Exit Sub
    End If
    Select Case KeyCode
        Case KEY_HELP, vbKeyH
            gHelp = (gHelp + 1) Mod 3
            Exit Sub
        Case vbKeyF1
            showPerf = Not showPerf
            Exit Sub
        Case vbKeyM
            ToggleMusic
            Exit Sub
        Case vbKeyN
            ToggleSound
            Exit Sub
    End Select
    If gHelp > 0 Then
        If KeyCode = vbKeySpace Or KeyCode = vbKeyJ Or KeyCode = vbKeyReturn Or KeyCode = vbKeyEscape Then gHelp = 0
        Exit Sub
    End If
    Select Case KeyCode
        Case vbKeyEscape
            If gState = LS_TITLE Then
                Unload Me
            Else
                ToTitle
            End If
        Case vbKeySpace, vbKeyJ, vbKeyReturn
            edgeFire = True
        Case vbKeyF2
            If gState = LS_TITLE Then
                entryRank = -1
                gState = LS_SCORES
                gStateTimer = 250
            End If
        Case vbKeyLeft, vbKeyA
            If gState = LS_TITLE Then gMenu = (gMenu + 3) Mod 4
        Case vbKeyRight, vbKeyD
            If gState = LS_TITLE Then gMenu = (gMenu + 1) Mod 4
        Case vbKeyUp, vbKeyW
            If gState = LS_TITLE And startLevel < 9 Then startLevel = startLevel + 1
        Case vbKeyDown, vbKeyS
            If gState = LS_TITLE And startLevel > 1 Then startLevel = startLevel - 1
        Case vbKeyP
            If gState = LS_PLAY Then
                gPaused = Not gPaused
                SoundPause gPaused
            End If
        Case vbKeyB
            If gState = LS_PLAY Then
                gDemo = Not gDemo
                If gLog Then Print "autopilot " & IIf(gDemo, "on", "off")
            End If
        Case vbKeyE
            ThrottleStep True
        Case vbKeyQ
            ThrottleStep False
    End Select
End Sub

Private Sub Form_Activate()
    If gLog Then Print "active"
End Sub

Private Sub Form_Deactivate()
    Dim k As Long
    For k = 0 To 255
        keyIsDown(k) = False
    Next k
    If gLog Then Print "inactive"
End Sub

Private Sub Form_KeyUp(KeyCode As Integer, Shift As Integer)
    keyIsDown(KeyCode And 255) = False
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    Dim ch As String
    If gState <> LS_ENTRY Then Exit Sub
    If KeyAscii = 13 Then
        If Len(entryName) = 0 Then entryName = "PILOT"
        entryRank = HsInsert(entryName, gScore)
        If Not HsSave(GameDir() & "lander_3d.scores") And gLog Then Print "cannot save the scores"
        gBest = hsScore(0)
        gState = LS_SCORES
        gStateTimer = 300
        If gLog Then Print "SCORES saved " & entryName & " " & gScore
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
    If gLog Then Print "bye"
End Sub

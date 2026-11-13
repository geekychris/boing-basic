' Boing Rally - the form: the title (the autopilot plays behind it), the game, game over.
'
'   BoingRally                 play
'   BoingRally --bench N       the autopilot plays N frames as fast as it can, drawing every
'                              one, then prints the state hash and the time a frame took
'   BoingRally --demo          start a game with the autopilot playing (screenshots)
'   BoingRally --seed N        the road's seed (default: a new one each game)
'   BoingRally --frames N      quit after N frames
'   BoingRally --fps           show frames a second (also F1)
'   BoingRally --saveshot F --shotframe N   save frame N (default 150) as a PNG and quit
'   BoingRally --nosound
'
' Keys: Left/Right (or A/D) steer, Space (or Up/W) jumps, P pauses, Esc back to the title
' (or quits from it), F1 the frame rate.
Option Explicit

Private Const S_TITLE As Long = 0
Private Const S_PLAY As Long = 1
Private Const S_OVER As Long = 2
Private Const KEY_F1 As Long = 112

Private state As Long, stateT As Long
Private paused As Boolean, autoplay As Boolean
Private best As Long, newBest As Boolean
Private seed As Long, fixedSeed As Boolean
Private benchN As Long, maxFrames As Long, frames As Long, noSound As Boolean, demoStart As Boolean
Private saveShot As String, shotFrame As Long
Private deaths As Long, games As Long, logDeaths As Boolean
Private showFps As Boolean, fpsCount As Long, fpsT As Double, fps As Double

Private Sub ParseArgs()
    Dim a() As String, i As Long, n As Long
    a = Split(Trim$(Command$), " ")
    For i = 0 To UBound(a)
        n = 0
        If i < UBound(a) Then If IsNumeric(a(i + 1)) Then n = CLng(a(i + 1))
        Select Case LCase$(a(i))
            Case "--bench": benchN = IIf(n > 0, n, 500)
            Case "--frames": maxFrames = n
            Case "--seed": seed = n: fixedSeed = True
            Case "--demo": demoStart = True
            Case "--fps": showFps = True
            Case "--nosound": noSound = True
            Case "--logdeaths": logDeaths = True
            Case "--shotframe": shotFrame = n
            Case "--saveshot": If i < UBound(a) Then saveShot = a(i + 1)
        End Select
    Next i
End Sub

Private Sub Form_Load()
    shotFrame = 150
    seed = 1
    ParseArgs
    best = Val(GetSetting("BoingRally", "Scores", "Best", "0"))
    DrawInit view
    If Not noSound And benchN = 0 Then SoundInit
    If benchN > 0 Then
        NewGame seed
        state = S_PLAY
        autoplay = True
    ElseIf demoStart Then
        StartGame
        autoplay = True
    Else
        ToTitle
    End If
    fpsT = Timer
End Sub

Private Sub ToTitle()
    state = S_TITLE
    stateT = 0
    autoplay = True
    NewGame 4242 + seed
End Sub

Private Sub StartGame()
    NewGame seed
    If Not fixedSeed Then seed = seed + 1
    state = S_PLAY
    stateT = 0
    autoplay = False
    paused = False
    newBest = False
End Sub

Private Function Keys() As Long
    Dim k As Long
    If autoplay Then Keys = AutoInput(): Exit Function
    If view.KeyDown(vbKeyLeft) Or view.KeyDown(vbKeyA) Then k = k Or IN_LEFT
    If view.KeyDown(vbKeyRight) Or view.KeyDown(vbKeyD) Then k = k Or IN_RIGHT
    If view.KeyDown(vbKeySpace) Or view.KeyDown(vbKeyUp) Or view.KeyDown(vbKeyW) Then k = k Or IN_JUMP
    Keys = k
End Function

' one frame: the game moves on a step, then everything is drawn
Private Sub Frame()
    If Not paused Then
        GameStep Keys()
        If lastEvent <> "" And state = S_PLAY Then SfxEvent lastEvent
        stateT = stateT + 1
        Select Case state
            Case S_TITLE
                If gameOver Or stateT > 25 * 60 Then ToTitle    ' the demo starts again
            Case S_PLAY
                If gameOver And benchN > 0 Then
                    games = games + 1                       ' --bench: the next game at once
                    NewGame seed + games
                ElseIf gameOver Then
                    state = S_OVER
                    stateT = 0
                    If score > best And Not autoplay Then         ' the autopilot's games don't count
                        best = score
                        newBest = True
                        SaveSetting "BoingRally", "Scores", "Best", CStr(best)
                    End If
                End If
            Case S_OVER
                If stateT > 25 * 8 Then ToTitle
        End Select
    End If
    DrawScene view
    DrawHud
End Sub

Private Sub DrawHud()
    Dim i As Long
    Select Case state
        Case S_TITLE
            CentreText view, 52, "BOING RALLY", RGB(255, 235, 120), 3
            CentreText view, 86, "a Boing BASIC OpenGL game", RGB(230, 230, 255), 1
            view.Alpha = 128                                    ' a dark band behind the help
            view.Box 30, 144, VW - 60, 50, vbBlack
            view.Alpha = 255
            If (stateT \ 12) And 1 Then CentreText view, 150, "PRESS SPACE TO ROLL", vbWhite, 1
            CentreText view, 170, "LEFT/RIGHT STEER   SPACE JUMPS", RGB(200, 210, 255), 1
            CentreText view, 182, "GEMS 100   BLOCKS HURT   MIND THE GAPS", RGB(200, 210, 255), 1
            CentreText view, 236, "BEST " & best, RGB(255, 220, 90), 1
        Case S_PLAY, S_OVER
            ShadowText view, 6, 5, "SCORE " & score, vbWhite
            ShadowText view, 6, 16, "DIST " & Int(-bz) & "m", RGB(200, 210, 255)
            ShadowText view, VW - 6 - view.TextWidth("BEST " & best), 5, "BEST " & best, RGB(255, 220, 90)
            For i = 1 To lives
                view.Circle VW - 4 - i * 11, 21, 4, RGB(230, 40, 40), True
                view.PSet VW - 5 - i * 11, 19, vbWhite
            Next i
            If boost > 0.05 And state = S_PLAY Then CentreText view, 30, "BOOST!", RGB(60, 255, 190), 1
            If crashT > 0 And state = S_PLAY Then CentreText view, 110, IIf(crashKind = "fall", "SPLASH... INTO THE CLOUDS", "CRASH!"), RGB(255, 120, 90), 1
            If state = S_OVER Then
                CentreText view, 80, "GAME OVER", RGB(255, 110, 90), 3
                CentreText view, 120, "SCORE " & score & "   GEMS " & gems, vbWhite, 1
                If newBest Then If (stateT \ 8) And 1 Then CentreText view, 136, "A NEW BEST!", RGB(255, 230, 90), 1
            End If
            If paused Then CentreText view, 120, "PAUSED - P GOES ON", vbWhite, 1
            If autoplay And state = S_PLAY And benchN = 0 Then ShadowText view, 6, VH - 14, "AUTOPILOT", RGB(150, 255, 150)
    End Select
    If showFps Then ShadowText view, VW - 60, VH - 14, Format$(fps, "0.0") & " fps", vbGreen
End Sub

' --bench: the frames back to back, from the first timer tick
Private Sub RunBench()
    Dim t0 As Double, ms As Double, n As Long
    tick.Enabled = False
    t0 = Timer
    For n = 1 To benchN
        Frame
        view.Refresh
        If lastEvent = "crash" Or lastEvent = "fall" Then deaths = deaths + 1: If logDeaths Then Print "lost a life: " & lastEvent & " at " & Int(-bz) & "m lives " & lives & " score " & score & " frame " & frameNo
        DoEvents
    Next n
    ms = (Timer - t0) * 1000
    Print "Boing Rally --bench " & benchN & ": score " & score & " gems " & gems & " lives " & lives & _
          " dist " & Int(-bz) & " lost " & deaths & " games " & games & " hash " & Hex$(StateHash()) & " picture " & Hex$(view.Hash)
    Print "time: " & Format$(ms / benchN, "0.00") & " ms/frame (" & Format$(benchN * 1000 / ms, "0.0") & " fps)"
    Unload Me
End Sub

Private Sub tick_Timer()
    Dim now As Double
    If benchN > 0 Then RunBench: Exit Sub
    Frame
    view.Refresh
    frames = frames + 1
    fpsCount = fpsCount + 1
    now = Timer
    If now - fpsT >= 1 Or now < fpsT Then
        If now > fpsT Then fps = fpsCount / (now - fpsT)
        fpsCount = 0
        fpsT = now
    End If
    If saveShot <> "" And frames = shotFrame Then
        view.SavePNG saveShot
        Unload Me
        Exit Sub
    End If
    If maxFrames > 0 And frames >= maxFrames Then Unload Me
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Select Case KeyCode
        Case vbKeySpace, vbKeyReturn
            If state = S_TITLE Then StartGame
            If state = S_OVER And stateT > 25 Then StartGame
        Case vbKeyP
            If state = S_PLAY Then paused = Not paused
        Case vbKeyEscape
            If state = S_TITLE Then Unload Me Else ToTitle
        Case KEY_F1
            showFps = Not showFps
    End Select
End Sub

Private Sub Form_Unload(Cancel As Integer)
    SoundCleanup
    GLDetach
End Sub

' squash.bas - Boing Squash, a bat-and-ball game (exercise 6 of the Boing BASIC manual).
' Left/Right (or Z/X) move the bat, Space starts, P pauses, Esc quits.
' Arguments: --auto lets the computer play (a demo), --frames N ends after N frames.
Option Explicit

' the court, in canvas pixels (the canvas is 320 x 256, shown twice as big: scale=2)
Const W = 320, H = 256
Const WALL = 8                       ' thickness of the walls
Const BATW = 44, BATH = 6, BATY = 236
Const BALLR = 4                      ' the ball's radius
Const FRAME_MS = 20                  ' one step of the game: 20 ms, 50 steps a second

' what the game is doing
Const TITLE = 0, PLAYING = 1, PAUSED = 2, GAMEOVER = 3
Private state As Integer

Private batX As Double               ' the bat's left edge
Private ballX As Double, ballY As Double, ballDX As Double, ballDY As Double
Private score As Long, best As Long, lives As Integer
Private lastMs As Double             ' TimerMs at the last frame
Private auto As Boolean, maxFrames As Long, frames As Long

Private Sub Form_Load()
    Dim args As String
    args = Command()
    auto = InStr(args, "--auto") > 0
    If InStr(args, "--frames") > 0 Then maxFrames = Val(Mid(args, InStr(args, "--frames") + 8))
    best = Val(GetSetting("BoingSquash", "Scores", "Best", "0"))
    Randomize
    state = TITLE
    If auto Then NewGame
    lastMs = TimerMs
End Sub

Private Sub Form_Unload(Cancel As Integer)
    SaveSetting "BoingSquash", "Scores", "Best", CStr(best)
End Sub

' --- the keyboard ---------------------------------------------------------------------------
' Keys that do one thing when pressed come as events. Keys that are held down (the bat) are
' read with view.KeyDown(...) in every frame instead, so the bat moves smoothly.

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Select Case KeyCode
    Case vbKeySpace
        If state = TITLE Or state = GAMEOVER Then NewGame
    Case vbKeyP
        If state = PLAYING Then
            state = PAUSED
        ElseIf state = PAUSED Then
            state = PLAYING
        End If
    Case vbKeyEscape
        Unload Me
    End Select
End Sub

' --- the game loop: the Timer calls this every FRAME_MS ------------------------------------

Private Sub tick_Timer()
    Dim now As Double, steps As Long
    ' How many 20 ms steps have passed since the last frame? Usually 1; more if the computer
    ' was busy. Moving one step at a time keeps the game's speed the same on any machine.
    now = TimerMs
    steps = Int((now - lastMs) / FRAME_MS)
    If steps < 1 Then steps = 1
    If steps > 5 Then steps = 5          ' after a long pause don't jump far ahead
    lastMs = lastMs + steps * FRAME_MS
    If now - lastMs > FRAME_MS * 5 Then lastMs = now

    Do While steps > 0
        If state = PLAYING Then MoveBat: MoveBall
        steps = steps - 1
    Loop
    DrawFrame

    frames = frames + 1
    If maxFrames > 0 And frames >= maxFrames Then Unload Me
End Sub

Private Sub NewGame()
    score = 0
    lives = 3
    batX = (W - BATW) / 2
    ServeBall
    state = PLAYING
End Sub

' Put the ball near the top, heading down at a random angle.
Private Sub ServeBall()
    ballX = W / 2
    ballY = 60
    ballDX = (Rnd * 2 - 1) * 2
    ballDY = 2
End Sub

Private Sub MoveBat()
    If auto Then
        ' the demo player: follow the ball
        If ballX < batX + BATW / 2 - 4 Then batX = batX - 4
        If ballX > batX + BATW / 2 + 4 Then batX = batX + 4
    Else
        If view.KeyDown(vbKeyLeft) Or view.KeyDown(vbKeyZ) Then batX = batX - 5
        If view.KeyDown(vbKeyRight) Or view.KeyDown(vbKeyX) Then batX = batX + 5
    End If
    If batX < WALL Then batX = WALL
    If batX > W - WALL - BATW Then batX = W - WALL - BATW
End Sub

Private Sub MoveBall()
    ballX = ballX + ballDX
    ballY = ballY + ballDY

    ' the walls: left, right and top
    If ballX < WALL + BALLR Then ballX = WALL + BALLR: ballDX = -ballDX
    If ballX > W - WALL - BALLR Then ballX = W - WALL - BALLR: ballDX = -ballDX
    If ballY < WALL + BALLR Then ballY = WALL + BALLR: ballDY = -ballDY

    ' the bat: only when the ball is coming down onto it
    If ballDY > 0 And ballY + BALLR >= BATY And ballY + BALLR <= BATY + BATH + 4 Then
        If ballX >= batX - BALLR And ballX <= batX + BATW + BALLR Then
            ballY = BATY - BALLR
            ballDY = -ballDY
            ' where it hits the bat sets the angle: the ends send it off sideways
            ballDX = (ballX - (batX + BATW / 2)) / (BATW / 2) * 3
            score = score + 1
            If score Mod 5 = 0 Then ballDY = ballDY * 1.1   ' faster every 5 hits
        End If
    End If

    ' missed: the ball fell out of the bottom
    If ballY > H + BALLR Then
        lives = lives - 1
        If lives > 0 Then
            ServeBall
        Else
            state = GAMEOVER
            If score > best Then best = score
            If auto Then NewGame
        End If
    End If
End Sub

' --- drawing: the whole picture again every frame, then Refresh shows it ------------------

Private Sub DrawFrame()
    Dim msg As String
    view.Cls RGB(0, 0, 40)                                   ' the background
    view.Box 0, 0, W, WALL, RGB(90, 110, 160)                ' top wall
    view.Box 0, 0, WALL, H, RGB(90, 110, 160)                ' left wall
    view.Box W - WALL, 0, WALL, H, RGB(90, 110, 160)         ' right wall
    view.Box batX, BATY, BATW, BATH, RGB(255, 200, 60)       ' the bat
    If state <> TITLE Then view.Circle ballX, ballY, BALLR, vbWhite, True
    view.DrawText 14, 12, "SCORE " & score, vbWhite
    view.DrawText W - 14 - view.TextWidth("BEST " & best), 12, "BEST " & best, RGB(160, 160, 160)
    view.DrawText 14, 24, "LIVES " & lives, RGB(255, 120, 120)

    Select Case state
    Case TITLE: msg = "BOING SQUASH - PRESS SPACE"
    Case PAUSED: msg = "PAUSED - PRESS P"
    Case GAMEOVER: msg = "GAME OVER - PRESS SPACE"
    Case Else: msg = ""
    End Select
    If msg <> "" Then view.DrawText (W - view.TextWidth(msg)) \ 2, H \ 2, msg, vbYellow
    view.Refresh                                             ' show the finished frame
End Sub

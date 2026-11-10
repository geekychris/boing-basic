' Bat and ball, played by the program itself on an off-screen canvas
Option Explicit

Private ballX As Long, ballY As Long, dx As Long, dy As Long
Private batX As Long, score As Long, misses As Long

Sub GameStart(cv As Canvas)
    ballX = cv.Width \ 2: ballY = 20
    dx = 3: dy = 2
    batX = cv.Width \ 2 - 20
End Sub

' one frame: read the keys, move, draw, show
Sub GameFrame(cv As Canvas)
    Dim w As Long, h As Long
    w = cv.Width: h = cv.Height
    If cv.KeyDown(vbKeyLeft) And batX > 0 Then batX = batX - 4
    If cv.KeyDown(vbKeyRight) And batX < w - 40 Then batX = batX + 4
    ballX = ballX + dx: ballY = ballY + dy
    If ballX < 4 Or ballX > w - 5 Then dx = -dx
    If ballY < 4 Then dy = -dy
    If ballY >= h - 12 And ballY < h - 8 And ballX >= batX And ballX < batX + 40 Then
        dy = -dy
        score = score + 1
    ElseIf ballY > h Then
        misses = misses + 1
        ballX = w \ 2: ballY = 20
    End If
    cv.Cls RGB(0, 0, 48)
    cv.Box batX, h - 10, 40, 4, vbWhite
    cv.Circle ballX, ballY, 4, RGB(255, 200, 0), True
    cv.DrawText 4, 2, "SCORE " & score & "  MISSED " & misses, vbWhite
    cv.Refresh
End Sub

Sub Main()
    Dim cv As Canvas, f As Long
    Set cv = CreateObject("Boing.Canvas")
    cv.Resize 200, 150
    GameStart cv
    For f = 1 To 500
        ' a "player" that presses the keys: keep the bat under the ball
        cv.InjectKey vbKeyLeft, ballX < batX + 10
        cv.InjectKey vbKeyRight, ballX > batX + 30
        GameFrame cv
    Next f
    Print "frames"; cv.Frames; " score"; score; " missed"; misses
    Print "picture hash"; cv.Hash
End Sub

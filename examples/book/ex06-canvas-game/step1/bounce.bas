' bounce.bas - a ball bouncing round the canvas, moved by a Timer.
Option Explicit

Private x As Long, y As Long, dx As Long, dy As Long

Private Sub Form_Load()
    x = 160: y = 128: dx = 3: dy = 2
End Sub

' Every 20 ms: move the ball, draw the frame, show it.
Private Sub tick_Timer()
    x = x + dx
    y = y + dy
    If x < 10 Or x > view.Width - 10 Then dx = -dx      ' bounce off the sides
    If y < 10 Or y > view.Height - 10 Then dy = -dy     ' and off the top and bottom
    view.Cls RGB(0, 0, 40)
    view.Circle x, y, 10, RGB(255, 80, 80), True
    view.DrawText 4, 4, "FRAME " & view.Frames, vbWhite
    view.Refresh
End Sub

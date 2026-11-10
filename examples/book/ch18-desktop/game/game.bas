' game.bas - pauses when the window is not active or is iconified
Option Explicit

Private x As Long, ballX As Long, ballY As Long, score As Long
Private paused As Boolean

Private Sub Form_Load()
    x = 160: ballX = 100: ballY = 0
End Sub

' another window was activated: pause, so the player doesn't lose
Private Sub Form_Deactivate()
    paused = True
    DrawFrame
End Sub

Private Sub Form_Resize()
    If Me.WindowState = 1 Then paused = True     ' iconified
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    Select Case KeyCode
    Case vbKeyP, vbKeySpace: paused = Not paused
    Case vbKeyHelp: paused = True: MsgBox "Cursor keys: move" & vbLf & "P: pause", vbInformation, "Boing Catch"
    Case vbKeyEscape
        paused = True
        If MsgBox("Quit the game?", vbYesNo + vbQuestion, "Boing Catch") = vbYes Then Unload Me
    End Select
End Sub

Private Sub tick_Timer()
    If Not paused Then
        If view.KeyDown(vbKeyLeft) And x > 20 Then x = x - 4
        If view.KeyDown(vbKeyRight) And x < 300 Then x = x + 4
        ballY = ballY + 3
        If ballY > 190 Then
            If Abs(ballX - x) < 24 Then score = score + 1
            ballY = 0: ballX = 20 + (ballX * 7 + 53) Mod 280
        End If
    End If
    DrawFrame
End Sub

Private Sub DrawFrame()
    view.Cls RGB(0, 0, 40)
    view.Circle ballX, ballY, 6, RGB(255, 60, 60), True
    view.FillRect x - 20, 192, 40, 6, RGB(255, 255, 255)
    view.DrawText 4, 2, "SCORE " & score, vbWhite
    If paused Then view.DrawText 130, 90, "PAUSED", vbYellow
    view.Refresh
End Sub
